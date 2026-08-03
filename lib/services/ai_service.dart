import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/master_prompt.dart';
import '../config/api_keys.dart';
import '../models/chat_message.dart';
import 'memory_store.dart';
import 'progress.dart';

/// Routes requests to whichever provider is set in MasterPrompt.activeProvider.
/// OpenAI-compatible providers (OpenRouter, Venice, Zhipu's OpenAI-compat
/// endpoint) all share the same request shape, so one path handles them.
///
/// Two entry points:
///   - askStream(): yields token chunks as they arrive (preferred for UI)
///   - ask():      returns the full reply after it completes (fallback)
class AiService {
  final http.Client _client = http.Client();

  /// Last `finish_reason` reported by the provider. Useful for surfacing to
  /// the UI when a stream ended unexpectedly (e.g. "length" = hit max_tokens).
  String? lastFinishReason;

  /// Streamed completion via SSE. Yields content deltas as the model
  /// generates them. Throws on non-200 responses.
  ///
  /// [idleTimeout] bounds the GAP between chunks, not the total duration — it
  /// resets on every event, so long replies stream fine but a provider that
  /// accepts the connection and then stalls (never sending `[DONE]`, never
  /// closing) fails fast instead of hanging the caller forever.
  Stream<String> askStream({
    required String userMessage,
    required List<ChatMessage> history,
    List<String> images = const [],
    Duration idleTimeout = const Duration(seconds: 30),
    ProgressController? progress,
  }) async* {
    lastFinishReason = null;
    final provider = MasterPrompt.activeProvider;
    final config = _providerConfig(provider);
    if (config.apiKey.isEmpty) {
      throw Exception(
          'No API key configured for "$provider". Check the .env file.');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer ${config.apiKey}',
      if (provider == 'openrouter') ...{
        'HTTP-Referer': 'https://exodus.app',
        'X-Title': 'EXODUS',
      },
    };
    final body =
        jsonEncode(_buildBody(userMessage, history, stream: true, images: images));

    // Resilient streaming: retry transient failures (dropped handshake, socket
    // close, mid-receive "Connection closed while receiving data", timeout) as
    // long as NO tokens have been produced yet — so output is never duplicated.
    // If a drop happens AFTER text has started, keep the partial reply and end
    // gracefully rather than failing the whole message.
    var yielded = false;
    var attempt = 0;
    while (true) {
      try {
        progress?.stage(
          attempt == 0 ? 'Reaching EXODUS…' : 'Reconnecting…',
          attempt: attempt + 1,
          maxAttempts: 3,
        );
        final request = http.Request('POST', Uri.parse(config.endpoint))
          ..headers.addAll(headers)
          ..body = body;
        final response =
            await _client.send(request).timeout(const Duration(seconds: 45));
        if (response.statusCode != 200) {
          final errBody = await response.stream.bytesToString();
          throw Exception('AI request failed (${response.statusCode}): $errBody');
        }
        progress?.stage('Thinking…', attempt: attempt + 1, maxAttempts: 3);

        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(idleTimeout);

        await for (final line in lines) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          if (payload == '[DONE]') return;
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;
            final choice = choices[0] as Map<String, dynamic>;
            final finishReason = choice['finish_reason'] as String?;
            if (finishReason != null) lastFinishReason = finishReason;
            final delta = choice['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              // First token is the moment the wait visibly ends — hand the UI
              // back so it can swap the indicator for streaming text.
              if (!yielded) progress?.done();
              yielded = true;
              yield content;
            }
          } catch (_) {
            // Keepalive/comment lines or non-JSON pings — ignore.
          }
        }
        return; // stream completed
      } on Exception catch (e) {
        if (yielded) return; // partial reply already shown — keep it.
        if (attempt < 2 && _isTransient(e)) {
          attempt++;
          progress?.stage(
            _isOffline(e) ? 'No connection — retrying…' : 'Connection dropped — retrying…',
            attempt: attempt + 1,
            maxAttempts: 3,
          );
          await Future.delayed(Duration(milliseconds: 700 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Transient errors worth retrying: dropped TLS handshakes, socket drops,
  /// timeouts, and the http client's generic connection failures.
  ///
  /// Being offline is NOT transient — a failed DNS lookup means there's no
  /// network at all, and retrying it three times with backoff just made the
  /// user wait ~137s to be told something we knew on the first attempt.
  static bool _isTransient(Object e) {
    if (_isOffline(e)) return false;
    return e is SocketException ||
        e is HandshakeException ||
        e is TimeoutException ||
        e is http.ClientException;
  }

  /// A DNS failure — no route to the internet at all.
  static bool _isOffline(Object e) {
    if (e is SocketException) {
      final msg = e.osError?.message ?? e.message;
      return e.message.contains('Failed host lookup') ||
          msg.contains('nodename nor servname') ||
          msg.contains('Name or service not known') ||
          msg.contains('No address associated with hostname');
    }
    return e.toString().contains('Failed host lookup');
  }

  /// Non-streaming fallback. Kept for cases where the caller wants the
  /// finished string in one await.
  Future<String> ask({
    required String userMessage,
    required List<ChatMessage> history,
    List<String> images = const [],
    int? maxTokens,
    Duration timeout = const Duration(seconds: 60),
    ProgressController? progress,

    /// What to say while the model is composing. The caller knows what it
    /// asked for ("Writing today's devotional…"), so it words this.
    String workingMessage = 'Thinking…',
  }) async {
    lastFinishReason = null;
    final provider = MasterPrompt.activeProvider;
    final config = _providerConfig(provider);
    if (config.apiKey.isEmpty) {
      throw Exception(
          'No API key configured for "$provider". Check the .env file.');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      if (provider == 'openrouter') ...{
        'HTTP-Referer': 'https://exodus.app',
        'X-Title': 'EXODUS',
      },
    };
    final body = jsonEncode(_buildBody(userMessage, history,
        stream: false, images: images, maxTokens: maxTokens));

    // Hard timeout (no infinite hang) + retry on transient network/TLS errors.
    http.Response response;
    var attempt = 0;
    while (true) {
      try {
        progress?.stage(
          attempt == 0 ? workingMessage : 'Reconnecting…',
          attempt: attempt + 1,
          maxAttempts: 3,
        );
        response = await _client
            .post(Uri.parse(config.endpoint), headers: headers, body: body)
            .timeout(timeout);
        break;
      } on Exception catch (e) {
        if (attempt < 2 && _isTransient(e)) {
          attempt++;
          progress?.stage(
            _isOffline(e)
                ? 'No connection — retrying…'
                : 'Connection dropped — retrying…',
            attempt: attempt + 1,
            maxAttempts: 3,
          );
          await Future.delayed(Duration(milliseconds: 700 * attempt));
          continue;
        }
        rethrow;
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'AI request failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    final choice = (choices != null && choices.isNotEmpty)
        ? choices.first as Map<String, dynamic>
        : null;
    lastFinishReason = choice?['finish_reason'] as String?;
    // Reasoning models (e.g. glm-4.6v) can return a null `content` when they
    // spend the whole token budget on hidden reasoning and hit the length cap.
    // Never cast null → String (that was crashing callers); return "" instead.
    final content = (choice?['message'] as Map<String, dynamic>?)?['content'];
    return content is String ? content : '';
  }

  Map<String, dynamic> _buildBody(
    String userMessage,
    List<ChatMessage> history, {
    required bool stream,
    List<String> images = const [],
    int? maxTokens,
  }) {
    // Build the current user turn. With attachments it uses the multimodal
    // parts array (text + image_url blocks); without, a plain string.
    final Object currentContent = images.isEmpty
        ? userMessage
        : [
            if (userMessage.trim().isNotEmpty)
              {'type': 'text', 'text': userMessage},
            for (final url in images)
              {
                'type': 'image_url',
                'image_url': {'url': url},
              },
          ];

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': MasterPrompt.build() + MemoryStore.instance.promptBlock()},
      ...history
          .where((m) =>
              !m.isLoading && (m.content.isNotEmpty || m.images.isNotEmpty))
          .map((m) => m.toApiFormat()),
      {'role': 'user', 'content': currentContent},
    ];

    return {
      'model': MasterPrompt.models[MasterPrompt.activeProvider],
      'messages': messages,
      'temperature': MasterPrompt.temperature,
      'max_tokens': maxTokens ?? MasterPrompt.maxTokens,
      if (stream) 'stream': true,
    };
  }

  _ProviderConfig _providerConfig(String provider) {
    switch (provider) {
      case 'openrouter':
        return _ProviderConfig(
          endpoint: 'https://openrouter.ai/api/v1/chat/completions',
          apiKey: ApiKeys.openRouter,
        );
      case 'glm':
        return _ProviderConfig(
          endpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
          apiKey: ApiKeys.glm,
        );
      case 'venice':
        return _ProviderConfig(
          endpoint: 'https://api.venice.ai/api/v1/chat/completions',
          apiKey: ApiKeys.venice,
        );
      default:
        throw Exception('Unknown provider: $provider');
    }
  }

  void dispose() => _client.close();
}

class _ProviderConfig {
  final String endpoint;
  final String apiKey;
  _ProviderConfig({required this.endpoint, required this.apiKey});
}
