import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Wraps flutter_tts for reading assistant replies aloud. Exposes a
/// [speakingMessageKey] notifier so message bubbles can show a play/stop
/// toggle for the message currently being read.
class TtsService {
  TtsService._() {
    _init();
  }
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();

  /// Identifies which message is currently being spoken (we use the message's
  /// timestamp ISO string as a stable key). null = nothing speaking.
  final ValueNotifier<String?> speakingKey = ValueNotifier<String?>(null);

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    // Let an utterance play through fully — reduces the choppy starts/stops
    // some iOS voices have when speak() is fired without awaiting completion.
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('en-GB');
    await _selectBritishMaleVoice();
    // Slightly slower than the iOS default reads noticeably smoother.
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Clear the speaking indicator whenever playback ends or is cancelled.
    _tts.setCompletionHandler(() => speakingKey.value = null);
    _tts.setCancelHandler(() => speakingKey.value = null);
    _tts.setErrorHandler((_) => speakingKey.value = null);
  }

  /// Pick a natural British male voice. On iOS the classic en-GB male voice is
  /// "Daniel" (with "(Enhanced)"/"(Premium)" variants when downloaded). Falls
  /// back to any en-GB voice, preferring known male names.
  Future<void> _selectBritishMaleVoice() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      final voices = raw.whereType<Map>().toList();
      final enGB = voices
          .where((v) =>
              (v['locale'] ?? '').toString().toLowerCase().startsWith('en-gb'))
          .toList();
      if (enGB.isEmpty) return;

      const malePref = ['daniel', 'arthur', 'oliver', 'george', 'james', 'malcolm'];
      bool isMale(Map v) =>
          malePref.any((n) => v['name'].toString().toLowerCase().contains(n));
      // Enhanced/Premium voices sound far smoother than the compact default.
      bool isHiFi(Map v) {
        final s = '${v['name']} ${v['quality'] ?? ''}'.toLowerCase();
        return s.contains('enhanced') || s.contains('premium');
      }

      Map? firstMatch(bool Function(Map) test) {
        for (final v in enGB) {
          if (test(v)) return v;
        }
        return null;
      }

      // Priority: male + high-fidelity -> male -> any high-fidelity -> first.
      Map? pick = firstMatch((v) => isMale(v) && isHiFi(v));
      pick ??= firstMatch(isMale);
      pick ??= firstMatch(isHiFi);
      pick ??= enGB.first;
      await _tts.setVoice({
        'name': pick['name'].toString(),
        'locale': pick['locale'].toString(),
      });
    } catch (_) {
      // Voice list unavailable (some platforms) — en-GB language alone still
      // gives a British accent.
    }
  }

  /// Speak [text] aloud, tagging it with [key]. If the same key is already
  /// playing, this stops it (toggle behavior).
  Future<void> toggle(String key, String text) async {
    await _init();
    if (speakingKey.value == key) {
      await stop();
      return;
    }
    await _tts.stop();
    speakingKey.value = key;
    await _tts.speak(_stripMarkdown(text));
  }

  Future<void> stop() async {
    await _tts.stop();
    speakingKey.value = null;
  }

  /// Remove markdown syntax so the TTS engine doesn't read "asterisk" etc.
  String _stripMarkdown(String md) {
    return md
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' code block ')
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
