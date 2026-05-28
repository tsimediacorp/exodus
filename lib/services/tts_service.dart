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
    await _tts.setSpeechRate(0.5); // 0.5 ≈ natural pace on iOS/web
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Clear the speaking indicator whenever playback ends or is cancelled.
    _tts.setCompletionHandler(() => speakingKey.value = null);
    _tts.setCancelHandler(() => speakingKey.value = null);
    _tts.setErrorHandler((_) => speakingKey.value = null);
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
