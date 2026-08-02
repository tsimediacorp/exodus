import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/journey_prompt.dart';
import '../models/chat_message.dart';
import '../models/devotional.dart';
import '../models/journey.dart';
import 'ai_service.dart';

/// Generates the day-by-day content of a guided [Journey].
///
/// Mirrors [DevotionalService]'s contract deliberately: it retries, and it
/// never throws — a failed day surfaces as an error the caller can show and
/// retry, rather than an exception escaping into a fire-and-forget handler.
class JourneyService {
  final AiService _ai = AiService();

  /// Why the last [generateDay] failed, or null if it succeeded.
  String? lastError;

  /// Generate day [dayNumber] of [journey]. Returns null on failure — unlike
  /// a daily devotional there is no canned fallback, because a generic day
  /// would break the arc the plan depends on.
  Future<Devotional?> generateDay({
    required Journey journey,
    required int dayNumber,
    required JourneyProgress progress,
  }) async {
    lastError = null;
    const maxAttempts = 2;
    Object? lastFailure;

    final previousTitles = <String>[];
    for (var d = 1; d < dayNumber; d++) {
      final prior = progress.days[d];
      if (prior != null) previousTitles.add('Day $d: ${prior.title}');
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final raw = await _ai.ask(
          userMessage: JourneyPrompt.day(
            journeyTitle: journey.title,
            theme: journey.theme,
            dayNumber: dayNumber,
            totalDays: journey.totalDays,
            usedRefs: progress.usedRefs,
            previousTitles: previousTitles,
          ),
          history: const <ChatMessage>[],
          maxTokens: 4000,
          timeout: const Duration(seconds: 30),
        );
        final day = Devotional.fromGenerated(
          // Journey days are plan-relative, not calendar days. The date is
          // only carried so the shared model stays valid; nothing keys off it.
          day: DateTime.now(),
          json: _extractJson(raw),
          goal: journey.title,
        );
        if (day.reflection.trim().isNotEmpty &&
            day.scriptureText.trim().isNotEmpty) {
          return day;
        }
        lastFailure = 'The model returned an incomplete day.';
      } catch (e) {
        lastFailure = e;
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    lastError = _friendlyError(lastFailure);
    return null;
  }

  static String _friendlyError(Object? e) {
    if (e == null) return 'Could not reach EXODUS.';
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

  /// Same tolerant extraction the devotional generator uses: models wrap JSON
  /// in prose or fences, and a single unescaped quote shouldn't lose the day.
  Map<String, dynamic> _extractJson(String s) {
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
      } catch (_) {/* fall through to field extraction */}
    }
    const keys = [
      'title', 'scriptureRef', 'scriptureText', 'reflection', 'prayer', 'action'
    ];
    final fields = <String, dynamic>{};
    for (final key in keys) {
      final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(s);
      if (m != null) {
        fields[key] = m
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .trim();
      }
    }
    return fields;
  }

  void dispose() => _ai.dispose();
}
