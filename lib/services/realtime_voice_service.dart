import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import '../config/coaching_prompt.dart';
import '../models/coaching_session.dart';

enum VoiceState { idle, connecting, connected, listening, speaking, error, closed }

/// Drives a live spoken coaching session with OpenAI's realtime model over
/// WebRTC. WebRTC (rather than raw websocket + PCM) is used deliberately:
/// flutter_webrtc captures the mic and plays the model's audio natively, so
/// we never hand-manage audio buffers. The data channel carries JSON events
/// (transcripts, turn boundaries) in both directions.
///
/// Lifecycle: [connect] → talk → [hangUp]. UI binds to the [ValueNotifier]s.
class RealtimeVoiceService {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _localStream;
  Timer? _connectTimeout;

  /// Coarse session state for the UI (the orb, status line).
  final ValueNotifier<VoiceState> state = ValueNotifier(VoiceState.idle);

  /// Live partial transcript of whoever is currently speaking.
  final ValueNotifier<String> liveCaption = ValueNotifier('');

  /// A human-readable error, when [state] is [VoiceState.error].
  final ValueNotifier<String?> error = ValueNotifier(null);

  /// Emitted whenever a turn (couple or coach) is finalized — the session
  /// screen appends these to the transcript.
  final void Function(CoachingTurn turn)? onTurn;

  RealtimeVoiceService({this.onTurn});

  bool get isConnected =>
      _pc != null && state.value != VoiceState.error && state.value != VoiceState.closed;

  /// Build the realtime session config (GA schema): instructions, voice,
  /// server-VAD turn detection (enables natural barge-in), and input
  /// transcription so we can caption the couple.
  Map<String, dynamic> _sessionConfig(String instructions) => {
        'type': 'realtime',
        'model': CoachingPrompt.model,
        'instructions': instructions,
        'output_modalities': ['audio'],
        'audio': {
          'input': {
            'transcription': {'model': 'whisper-1'},
            'turn_detection': {'type': 'server_vad', 'create_response': true},
          },
          'output': {'voice': CoachingPrompt.voice},
        },
      };

  /// Friendly message for HTTP 429 from the realtime API. New OpenAI projects
  /// have low realtime session limits, and rapid re-connects trip them.
  static const _rateLimitMsg =
      "EXODUS's live voice is busy right now (rate limit). Give it a few "
      "seconds, then start the session again.";

  /// POST with up to [tries] attempts, backing off on HTTP 429. Honors the
  /// server's Retry-After header when present (OpenAI realtime sends it on
  /// rate/concurrency limits), otherwise uses linear backoff.
  Future<http.Response> _postRetrying(
    Uri url, {
    required Map<String, String> headers,
    required Object body,
    int tries = 4,
  }) async {
    http.Response res = await http.post(url, headers: headers, body: body);
    var attempt = 1;
    while (res.statusCode == 429 && attempt < tries) {
      final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
      final waitMs =
          (retryAfter != null ? retryAfter * 1000 : 1500 * attempt).clamp(1000, 8000);
      await Future.delayed(Duration(milliseconds: waitMs));
      res = await http.post(url, headers: headers, body: body);
      attempt++;
    }
    return res;
  }

  /// Mint an ephemeral realtime key (GA endpoint) from the standalone OpenAI
  /// key, with the full session config baked in. Keeps the long-lived key out
  /// of the SDP exchange. Returns the ephemeral client secret.
  Future<String> _mintEphemeralKey({required String instructions}) async {
    final res = await _postRetrying(
      Uri.parse('https://api.openai.com/v1/realtime/client_secrets'),
      headers: {
        'Authorization': 'Bearer ${ApiKeys.openAi}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'session': _sessionConfig(instructions)}),
    );
    if (res.statusCode == 429) throw Exception(_rateLimitMsg);
    if (res.statusCode != 200) {
      throw Exception('Realtime session mint failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['value'] as String;
  }

  Future<void> connect({required int minutes}) async {
    if (ApiKeys.openAi.isEmpty) {
      _fail('Missing OPENAI_API_KEY — add it to .env to run voice coaching.');
      return;
    }
    state.value = VoiceState.connecting;
    error.value = null;
    final instructions = CoachingPrompt.build(minutes: minutes);

    try {
      final ephemeral = await _mintEphemeralKey(instructions: instructions);

      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ],
      });
      _pc = pc;

      // The model's audio track plays automatically once attached to the
      // peer connection — no manual buffering needed with WebRTC.
      pc.onTrack = (RTCTrackEvent e) {};
      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          if (state.value != VoiceState.closed) _fail('Connection lost.');
        }
      };

      // Mic capture.
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      // Events channel.
      final dc = await pc.createDataChannel('oai-events', RTCDataChannelInit());
      _dc = dc;
      dc.onMessage = (RTCDataChannelMessage msg) => _handleEvent(msg.text);
      dc.onDataChannelState = (s) {
        // The data channel opens asynchronously, AFTER connect() returns. Only
        // here is it safe to send events — so greet the couple now, not earlier.
        if (s == RTCDataChannelState.RTCDataChannelOpen) {
          _connectTimeout?.cancel();
          state.value = VoiceState.listening;
          kickoff();
        }
      };

      // SDP offer → OpenAI → answer.
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      final sdpRes = await _postRetrying(
        Uri.parse('https://api.openai.com/v1/realtime/calls?model=${CoachingPrompt.model}'),
        headers: {
          'Authorization': 'Bearer $ephemeral',
          'Content-Type': 'application/sdp',
        },
        body: offer.sdp ?? '',
      );
      if (sdpRes.statusCode == 429) throw Exception(_rateLimitMsg);
      if (sdpRes.statusCode >= 300) {
        throw Exception('SDP exchange failed (${sdpRes.statusCode}): ${sdpRes.body}');
      }
      await pc.setRemoteDescription(RTCSessionDescription(sdpRes.body, 'answer'));
      state.value = VoiceState.connected;

      // Surface a failure instead of hanging on "Connecting…" if the data
      // channel never opens (ICE blocked, no mic permission, network, etc.).
      _connectTimeout = Timer(const Duration(seconds: 15), () {
        if (state.value != VoiceState.listening &&
            state.value != VoiceState.speaking &&
            state.value != VoiceState.closed) {
          _fail("Couldn't connect the voice channel — check your internet and "
              "that microphone access is allowed, then try again.");
        }
      });
    } catch (e) {
      _fail('$e');
    }
  }

  void _send(Map<String, dynamic> event) {
    _dc?.send(RTCDataChannelMessage(jsonEncode(event)));
  }

  // Accumulators for the in-flight coach reply.
  final StringBuffer _coachBuf = StringBuffer();

  void _handleEvent(String raw) {
    Map<String, dynamic> e;
    try {
      e = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = e['type'] as String? ?? '';

    // Match on suffixes so we tolerate the GA rename of audio events
    // (e.g. response.audio_transcript.delta → response.output_audio_transcript.delta).
    if (type == 'input_audio_buffer.speech_started') {
      state.value = VoiceState.listening;
      liveCaption.value = '';
    } else if (type.contains('input_audio_transcription.completed')) {
      final t = (e['transcript'] as String?)?.trim() ?? '';
      if (t.isNotEmpty) onTurn?.call(CoachingTurn(speaker: 'couple', text: t));
      liveCaption.value = '';
    } else if (type.endsWith('audio_transcript.delta')) {
      state.value = VoiceState.speaking;
      _coachBuf.write(e['delta'] as String? ?? '');
      liveCaption.value = _coachBuf.toString();
    } else if (type.endsWith('audio_transcript.done')) {
      final full = (e['transcript'] as String?)?.trim() ?? _coachBuf.toString().trim();
      if (full.isNotEmpty) onTurn?.call(CoachingTurn(speaker: 'exodus', text: full));
      _coachBuf.clear();
      liveCaption.value = '';
      state.value = VoiceState.listening;
    } else if (type == 'error') {
      final msg = (e['error'] as Map<String, dynamic>?)?['message'] as String?;
      _fail(msg ?? 'Realtime error');
    }
  }

  /// Ask the coach to begin (greeting / opening question).
  void kickoff() {
    _send({
      'type': 'response.create',
      'response': {
        'instructions':
            'Greet the couple warmly in one or two sentences and ask what they want to work on today.',
      },
    });
  }

  void _fail(String message) {
    error.value = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
    state.value = VoiceState.error;
  }

  Future<void> hangUp() async {
    _connectTimeout?.cancel();
    try {
      await _dc?.close();
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      await _pc?.close();
    } catch (_) {
      // Best-effort teardown.
    } finally {
      _dc = null;
      _pc = null;
      state.value = VoiceState.closed;
    }
  }

  void dispose() {
    hangUp();
    state.dispose();
    liveCaption.dispose();
    error.dispose();
  }
}
