import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/confession_prompt.dart';
import '../models/chat_message.dart';
import '../models/confession.dart';
import 'ai_service.dart';
import 'progress.dart';
import 'storage_service.dart';

/// Confession, and the prayer returned over it.
///
/// What "anonymous" means here, precisely, so the UI can say the same thing:
///
///  * Nothing is sent to the couples backend. Confessions never touch Amplify,
///    never carry an authorId, and are never shared with a partner — unlike
///    every other shared surface in the app.
///  * Nothing is written to memory. This matters more than it looks: memory
///    feeds the check-in scanner, which surfaces cards in Counsel, which is a
///    screen a spouse can be looking at. A confession in memory could come
///    back as a question in front of the person it was kept from.
///  * The text IS sent to the model provider to generate the prayer, with no
///    identity attached. That is not the same as never leaving the device, and
///    the screen says so rather than claiming more privacy than exists.
class ConfessionService {
  final AiService _ai = AiService();
  final StorageService _storage = StorageService.instance;

  /// Why the last [pray] call fell back, or null if it produced a real prayer.
  String? lastError;

  /// Prayers used when the model can't be reached. Someone who has just
  /// confessed something and got a spinner and an error has been left worse
  /// than if the button had done nothing, so there is always a response.
  static const List<Map<String, String>> _fallbackPrayers = [
    {
      'scriptureRef': '1 John 1:9',
      'prayer':
          'Father, You said that if we confess our sins, You are faithful and just '
              'to forgive us and to cleanse us. This has been said out loud now, and '
              'it is in Your hands rather than hidden. Do what You promised: forgive, '
              'cleanse, and do not leave them carrying what You have already lifted. Amen.',
    },
    {
      'scriptureRef': 'Psalm 103:12',
      'prayer':
          'Lord, as far as the east is from the west, so far have You removed our '
              'transgressions from us. Take this that distance. Where shame keeps '
              'walking it back, meet them with the finished work of Christ and let '
              'them rest in it. Amen.',
    },
    {
      'scriptureRef': 'Romans 8:1',
      'prayer':
          'God, there is no condemnation for those who are in Christ Jesus. Not '
              'reduced condemnation, not deferred — none. Quiet the voice that says '
              'otherwise tonight, and give them the courage to walk back toward You '
              'rather than away. Amen.',
    },
  ];

  /// Confess [text] and get a prayer back. Never throws: a network failure
  /// yields a built-in prayer, flagged as such, rather than an error.
  Future<Confession> pray(String text, {ProgressController? progress}) async {
    final confession = Confession.now(text.trim());
    lastError = null;

    try {
      final raw = await _ai.ask(
        userMessage: ConfessionPrompt.task(confession.text),
        // No history: this conversation has no past, by design.
        history: const <ChatMessage>[],
        maxTokens: 2000,
        timeout: const Duration(seconds: 30),
        progress: progress,
        workingMessage: 'Praying over this…',
      );
      final json = _extractJson(raw);
      final prayer = (json['prayer'] ?? '').toString().trim();
      if (prayer.isNotEmpty) {
        confession.prayer = prayer;
        confession.scriptureRef = (json['scriptureRef'] ?? '').toString().trim();
        return confession;
      }
      lastError = 'The response came back empty.';
    } catch (e) {
      lastError = _friendlyError(e);
    }

    final fallback = _fallbackPrayers[
        confession.createdAt.millisecondsSinceEpoch % _fallbackPrayers.length];
    confession.prayer = fallback['prayer']!;
    confession.scriptureRef = fallback['scriptureRef']!;
    confession.isFallback = true;
    return confession;
  }

  /// Everything confessed on this device, newest first.
  List<Confession> all() => _storage.loadConfessions();

  Future<void> keep(Confession confession) =>
      _storage.saveConfession(confession);

  /// Remove one confession and its prayer for good.
  Future<void> forget(String id) => _storage.deleteConfession(id);

  /// Remove every confession on the device.
  Future<void> forgetAll() => _storage.clearConfessions();

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (e is TimeoutException || s.contains('TimeoutException')) {
      return 'The connection timed out.';
    }
    if (e is SocketException || s.contains('SocketException')) {
      return 'No internet connection.';
    }
    if (s.contains('(401)') || s.contains('(403)')) {
      return 'The API key was rejected. Check Settings.';
    }
    if (s.contains('(429)')) return 'Rate limited — try again in a moment.';
    return s.replaceFirst('Exception: ', '');
  }

  Map<String, dynamic> _extractJson(String s) {
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
      } catch (_) {/* fall through */}
    }
    final fields = <String, dynamic>{};
    for (final key in ['scriptureRef', 'prayer']) {
      final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(s);
      if (m != null) {
        fields[key] = m
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .trim();
      }
    }
    // A model that ignored the JSON instruction and just prayed is still a
    // usable prayer — take the prose rather than falling back to canned text.
    if (fields['prayer'] == null && s.trim().isNotEmpty && !s.contains('{')) {
      fields['prayer'] = s.trim();
    }
    return fields;
  }

  void dispose() => _ai.dispose();
}
