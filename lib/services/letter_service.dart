import 'dart:async';
import 'dart:io';
import '../config/journey_catalog.dart';
import '../config/letter_prompt.dart';
import '../models/chat_message.dart';
import '../models/devotional.dart';
import '../models/marriage_letter.dart';
import 'ai_service.dart';
import 'memory_store.dart';
import 'storage_service.dart';

/// What the couple actually did in a given week, gathered from local storage.
/// Kept as a value so the UI can show the basis before spending a request.
class WeekBasis {
  final List<Devotional> devotionals;
  final int actionsDone;
  final int coachingSessions;
  final int coachingMinutes;
  final int versesKept;
  final List<String> journeyProgress;
  final List<String> memoryFacts;
  final String goal;

  const WeekBasis({
    required this.devotionals,
    required this.actionsDone,
    required this.coachingSessions,
    required this.coachingMinutes,
    required this.versesKept,
    required this.journeyProgress,
    required this.memoryFacts,
    required this.goal,
  });

  /// True when there is genuinely nothing to write about.
  bool get isEmpty =>
      devotionals.isEmpty &&
      actionsDone == 0 &&
      coachingSessions == 0 &&
      versesKept == 0 &&
      journeyProgress.isEmpty;

  /// Short line for the UI — what fed this letter.
  String get summary {
    final parts = <String>[
      if (devotionals.isNotEmpty)
        '${devotionals.length} devotional${devotionals.length == 1 ? '' : 's'}',
      if (actionsDone > 0) '$actionsDone action${actionsDone == 1 ? '' : 's'}',
      if (coachingSessions > 0)
        '$coachingSessions coaching session${coachingSessions == 1 ? '' : 's'}',
      if (versesKept > 0) '$versesKept verse${versesKept == 1 ? '' : 's'} kept',
      if (journeyProgress.isNotEmpty) 'journey progress',
    ];
    return parts.isEmpty ? 'A quiet week' : parts.join(' · ');
  }

  /// The prose block handed to the model.
  String get prompt {
    final b = StringBuffer();
    if (devotionals.isEmpty) {
      b.writeln('- They did not open a devotional this week.');
    } else {
      b.writeln('- Devotionals they read:');
      for (final d in devotionals) {
        b.writeln('    · "${d.title}" (${d.scriptureRef})');
      }
    }
    b.writeln('- Together-actions they marked done: $actionsDone of 7 days.');
    if (coachingSessions > 0) {
      b.writeln('- Live coaching: $coachingSessions session(s), '
          '$coachingMinutes minutes total.');
    } else {
      b.writeln('- No live coaching sessions this week.');
    }
    if (versesKept > 0) b.writeln('- Verses they kept: $versesKept.');
    for (final j in journeyProgress) {
      b.writeln('- $j');
    }
    if (memoryFacts.isNotEmpty) {
      b.writeln('- What you already know about them:');
      for (final f in memoryFacts) {
        b.writeln('    · $f');
      }
    }
    return b.toString();
  }
}

/// Writes the weekly letter from what the couple actually did.
class LetterService {
  final AiService _ai = AiService();
  final StorageService _storage = StorageService.instance;

  String? lastError;

  /// Gather the week beginning [weekStart] (Monday) from local storage.
  WeekBasis gather(DateTime weekStart) {
    final start = MarriageLetter.startOfWeek(weekStart);
    final end = start.add(const Duration(days: 7));
    bool inWeek(DateTime d) => !d.isBefore(start) && d.isBefore(end);

    final devotionals = _storage
        .loadDevotionals()
        .where((d) => inWeek(d.day) && !d.isFallback)
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));

    final actions = _storage.loadActionDays().where((key) {
      final parsed = DateTime.tryParse(key);
      return parsed != null && inWeek(parsed);
    }).length;

    final sessions = _storage
        .loadCoachingSessions()
        .where((s) => inWeek(s.startedAt))
        .toList();

    final verses =
        _storage.loadSavedVerses().where((v) => inWeek(v.savedAt)).length;

    final journeys = <String>[];
    for (final entry in _storage.loadJourneys().entries) {
      final journey = JourneyCatalog.byId(entry.key);
      if (journey == null) continue;
      final done = entry.value.completed.length;
      if (done == 0) continue;
      journeys.add(entry.value.isComplete(journey.totalDays)
          ? 'They finished the plan "${journey.title}".'
          : 'They are $done of ${journey.totalDays} days into "${journey.title}".');
    }

    return WeekBasis(
      devotionals: devotionals,
      actionsDone: actions,
      coachingSessions: sessions.length,
      coachingMinutes: sessions.fold(0, (sum, s) => sum + s.lengthMinutes),
      versesKept: verses,
      journeyProgress: journeys,
      // Capped: the letter needs colour, not the couple's whole history.
      memoryFacts:
          MemoryStore.instance.items.take(12).map((m) => m.text).toList(),
      goal: _storage.loadDevotionalGoal()?.text ?? '',
    );
  }

  /// Write and persist the letter for [weekStart]. Returns null on failure —
  /// [lastError] then explains why.
  Future<MarriageLetter?> generate(DateTime weekStart) async {
    lastError = null;
    final start = MarriageLetter.startOfWeek(weekStart);
    final basis = gather(start);
    final letter = MarriageLetter(
      weekStart: start,
      body: '',
      basis: basis.summary,
    );

    try {
      final body = await _ai.ask(
        userMessage: LetterPrompt.task(
          weekLabel: letter.rangeLabel,
          basis: basis.prompt,
          goal: basis.goal,
        ),
        history: const <ChatMessage>[],
        maxTokens: 2000,
        timeout: const Duration(seconds: 45),
      );
      if (body.trim().isEmpty) {
        lastError = 'EXODUS returned an empty letter. Try again.';
        return null;
      }
      final finished = MarriageLetter(
        weekStart: start,
        body: body.trim(),
        basis: basis.summary,
      );
      await _storage.saveLetter(finished);
      return finished;
    } catch (e) {
      lastError = _friendlyError(e);
      return null;
    }
  }

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

  void dispose() => _ai.dispose();
}
