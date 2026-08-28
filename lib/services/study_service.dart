import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/study_fallback.dart';
import '../config/study_prompt.dart';
import '../models/chat_message.dart';
import '../models/study_exercise.dart';
import 'ai_service.dart';
import 'progress.dart';

/// Generates the daily Bible study exercise. Routes through [AiService], so the
/// system prompt is always `MasterPrompt.build()` — the exercise is EXODUS,
/// grounded in the same source of truth as everything else.
class StudyService {
  final AiService _ai = AiService();

  /// Why the last [generate] call fell back, or null if it produced a real
  /// exercise. [generate] never throws, so this is how callers learn that what
  /// they got is canned content rather than a fresh practice.
  String? lastGenerateError;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Generate the exercise for [forDay] (default today).
  ///
  /// Guaranteed to NEVER throw: it retries the model, and if every attempt
  /// fails (network down, empty/garbled output, rate limit) it returns a
  /// complete built-in exercise. The tab therefore always has real content.
  ///
  /// [recentTitles] and [recentForms] are what has already been served, passed
  /// through so the model does not settle into three favourite practices.
  Future<StudyExercise> generate({
    DateTime? forDay,
    List<String> recentTitles = const [],
    List<String> recentForms = const [],
    ProgressController? progress,
  }) async {
    final day = forDay ?? DateTime.now();
    lastGenerateError = null;
    const maxAttempts = 2;
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final raw = await _ai.ask(
          userMessage: StudyPrompt.task(
            dateLabel: _dateLabel(day),
            recentTitles: recentTitles,
            recentForms: recentForms,
          ),
          history: const <ChatMessage>[],
          // Same headroom the devotional needs: a reasoning model spends
          // tokens thinking before the JSON, and too small a cap yields an
          // empty body rather than a short one.
          maxTokens: 4000,
          timeout: const Duration(seconds: 30),
          progress: progress,
          workingMessage: 'Building today\'s exercise…',
        );
        progress?.stage('Laying out the steps…');
        final exercise = StudyExercise.fromGenerated(
            day: day, json: _extractJson(raw));

        // An exercise with no steps is a devotional, which is the one thing
        // this tab must not serve. Reject it and retry rather than shipping it.
        if (exercise.steps.length >= 2 &&
            exercise.scriptureText.trim().isNotEmpty) {
          return exercise;
        }
        lastError = 'The model returned an exercise with no steps.';
      } catch (e) {
        // transient (timeout, network, parse) — try again, then fall back
        lastError = e;
      }
      if (attempt < maxAttempts - 1) {
        progress?.stage('That came back incomplete — trying again…',
            attempt: 2, maxAttempts: maxAttempts);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    lastGenerateError = _friendlyError(lastError);
    return fallbackFor(day);
  }

  /// Turn a raw exception into something worth showing a user.
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

  /// A complete, on-theme exercise that always works — used when the model
  /// can't produce one, and to show instantly while the real one generates.
  StudyExercise fallbackFor(DateTime day) => StudyExercise.fromGenerated(
        day: day,
        json: Map<String, dynamic>.from(StudyFallback.forDay(day)),
        isFallback: true,
      );

  /// Pull the exercise fields out of a model reply, tolerating stray text or
  /// code fences. Falls back to per-field extraction when strict parsing fails
  /// (an unescaped quote inside a value is the usual culprit) so the exercise
  /// still renders instead of dumping raw text on screen.
  Map<String, dynamic> _extractJson(String s) {
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
      } catch (_) {/* fall through to field extraction */}
    }

    final fields = <String, dynamic>{};
    const stringKeys = [
      'title', 'form', 'premise', 'scriptureRef', 'scriptureText',
      'question', 'closingPrayer',
    ];
    for (final key in stringKeys) {
      final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(s);
      if (m != null) {
        fields[key] = m
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .trim();
      }
    }

    // steps is an array, so it needs its own pass: grab the bracketed run and
    // pull the quoted strings out of it.
    final stepsMatch =
        RegExp(r'"steps"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(s);
    if (stepsMatch != null) {
      final steps = <String>[];
      for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"')
          .allMatches(stepsMatch.group(1)!)) {
        final text =
            m.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').trim();
        if (text.isNotEmpty) steps.add(text);
      }
      if (steps.isNotEmpty) fields['steps'] = steps;
    }

    return fields;
  }

  void dispose() => _ai.dispose();
}
