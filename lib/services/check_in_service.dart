import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/check_in_prompt.dart';
import '../models/chat_message.dart';
import '../models/check_in.dart';
import 'ai_service.dart';
import 'memory_store.dart';
import 'progress.dart';
import 'storage_service.dart';

/// Decides what EXODUS should come back to the couple about, and when.
///
/// The hard part here is restraint, not extraction. An assistant that surfaces
/// every remembered detail becomes noise and gets ignored, so the limits below
/// are the feature as much as the generation is.
class CheckInService extends ChangeNotifier {
  CheckInService._();
  static final CheckInService instance = CheckInService._();

  final StorageService _storage = StorageService.instance;

  /// At most one check-in shown at a time. Two questions at once is an
  /// interrogation.
  static const int maxRaisedAtOnce = 1;

  /// Leave at least this long between check-ins, however many are queued.
  static const Duration minGapBetweenCheckIns = Duration(days: 3);

  /// Don't re-scan memory more often than this — it costs a request and the
  /// couple's history rarely changes fast enough to matter.
  static const Duration scanInterval = Duration(days: 2);

  /// Never hold more than this many open; beyond it, the oldest are dropped.
  static const int maxOpen = 8;

  List<CheckIn> get all => _storage.loadCheckIns();

  /// The one check-in to show right now, or null if it isn't time.
  ///
  /// Returns null when: nothing is due, one was raised too recently, or the
  /// couple has dismissed everything.
  CheckIn? get current {
    if (!_storage.loadCheckInsEnabled()) return null;
    final items = all;
    final lastResolved = items
        .where((c) => c.resolvedAt != null)
        .map((c) => c.resolvedAt!)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (lastResolved != null &&
        DateTime.now().difference(lastResolved) < minGapBetweenCheckIns) {
      return null;
    }

    // Something already raised and unanswered stays on screen rather than
    // being replaced — finish one conversation before starting another.
    final raised = items.where((c) => c.status == CheckInStatus.raised).toList()
      ..sort((a, b) => (a.raisedAt ?? a.dueAt).compareTo(b.raisedAt ?? b.dueAt));
    if (raised.isNotEmpty) return raised.first;

    final due = items.where((c) => c.isDue).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return due.isEmpty ? null : due.first;
  }

  Future<void> markRaised(CheckIn c) async {
    c.status = CheckInStatus.raised;
    c.raisedAt = DateTime.now();
    await _storage.saveCheckIn(c);
    notifyListeners();
  }

  Future<void> markAnswered(CheckIn c) async {
    c.status = CheckInStatus.answered;
    c.resolvedAt = DateTime.now();
    await _storage.saveCheckIn(c);
    notifyListeners();
  }

  Future<void> dismiss(CheckIn c) async {
    c.status = CheckInStatus.dismissed;
    c.resolvedAt = DateTime.now();
    await _storage.saveCheckIn(c);
    notifyListeners();
  }

  /// Push a check-in out by [days] — "not now" without discarding it.
  Future<void> snooze(CheckIn c, {int days = 7}) async {
    final moved = CheckIn(
      id: c.id,
      question: c.question,
      because: c.because,
      topic: c.topic,
      createdAt: c.createdAt,
      dueAt: DateTime.now().add(Duration(days: days)),
      status: CheckInStatus.pending,
    );
    await _storage.saveCheckIn(moved);
    notifyListeners();
  }

  /// Whether a memory scan is worth running now.
  bool get shouldScan {
    if (!_storage.loadCheckInsEnabled()) return false;
    if (MemoryStore.instance.items.length < 3) return false; // nothing to go on
    final last = _storage.loadLastCheckInScan();
    if (last == null) return true;
    return DateTime.now().difference(last) >= scanInterval;
  }

  /// Read memory and queue anything worth following up on.
  ///
  /// Best-effort and silent: this runs in the background, so a failure must
  /// never surface to the couple. Returns how many were added.
  Future<int> scan({ProgressController? progress, bool force = false}) async {
    if (!force && !shouldScan) return 0;
    await _storage.saveLastCheckInScan(DateTime.now());

    final memory = MemoryStore.instance.items;
    if (memory.isEmpty) return 0;

    final open = all.where((c) => c.isOpen).toList();
    // Dismissed items are included so the model doesn't re-propose something
    // they've already said no to.
    final excluded = all
        .where((c) => !c.isOpen)
        .map((c) => c.question)
        .followedBy(open.map((c) => c.question))
        .take(20)
        .map((q) => '- $q')
        .join('\n');

    final ai = AiService();
    try {
      final raw = await ai.ask(
        userMessage: CheckInPrompt.find(
          memory: memory.map((m) => '- ${m.text}').join('\n'),
          existing: excluded,
          recentActivity: _recentActivity(),
        ),
        history: const <ChatMessage>[],
        maxTokens: 1200,
        timeout: const Duration(seconds: 30),
        progress: progress,
        workingMessage: 'Reviewing what you have shared…',
      );
      return await _ingest(raw);
    } catch (_) {
      return 0; // best-effort; never surfaced
    } finally {
      ai.dispose();
    }
  }

  /// Parse the model's proposals and queue the ones that survive the filters.
  Future<int> _ingest(String raw) async {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return 0;
    late final List<dynamic> parsed;
    try {
      parsed = jsonDecode(raw.substring(start, end + 1)) as List<dynamic>;
    } catch (_) {
      return 0;
    }

    final existing = all;
    final seen = existing.map((c) => c.fingerprint).toSet();
    var added = 0;

    for (final item in parsed) {
      if (item is! Map) continue;
      final question = (item['question'] ?? '').toString().trim();
      if (question.isEmpty) continue;

      final candidate = CheckIn(
        id: '${DateTime.now().microsecondsSinceEpoch}_$added',
        question: question,
        because: (item['because'] ?? '').toString().trim(),
        topic: (item['topic'] ?? 'general').toString().trim(),
        // Clamped: the model can propose a wait, but not an unbounded one, and
        // never so soon that it feels like it was listening a moment ago.
        dueAt: DateTime.now().add(Duration(
          days: (int.tryParse('${item['waitDays']}') ?? 7).clamp(2, 30),
        )),
      );
      if (!seen.add(candidate.fingerprint)) continue; // duplicate

      await _storage.saveCheckIn(candidate);
      added++;
    }

    if (added > 0) await _prune();
    notifyListeners();
    return added;
  }

  /// Keep the queue bounded — drop the oldest open items beyond [maxOpen].
  Future<void> _prune() async {
    final open = all.where((c) => c.isOpen).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (open.length <= maxOpen) return;
    for (final stale in open.sublist(maxOpen)) {
      await _storage.deleteCheckIn(stale.id);
    }
  }

  /// A short picture of their recent rhythm, so a check-in can acknowledge it
  /// ("I noticed you haven't opened a devotional in a while").
  String _recentActivity() {
    final now = DateTime.now();
    final devotionals = _storage
        .loadDevotionals()
        .where((d) => now.difference(d.day).inDays <= 14 && !d.isFallback)
        .length;
    final sessions = _storage
        .loadCoachingSessions()
        .where((s) => now.difference(s.startedAt).inDays <= 14)
        .length;
    final actions = _storage.loadActionDays().where((k) {
      final d = DateTime.tryParse(k);
      return d != null && now.difference(d).inDays <= 14;
    }).length;
    final goal = _storage.loadDevotionalGoal()?.text ?? '';

    return [
      if (goal.isNotEmpty) '- Their devotional goal: "$goal"',
      '- Devotionals read in the last two weeks: $devotionals',
      '- Together-actions completed in the last two weeks: $actions',
      '- Coaching sessions in the last two weeks: $sessions',
    ].join('\n');
  }

  /// The opening message when a check-in is taken into Counsel, so the
  /// conversation starts already knowing what it is about.
  String seedPrompt(CheckIn c) => '''
You are following up with this couple, unprompted, about something you
remembered.

WHAT PROMPTED THIS: ${c.because}
WHAT YOU ASKED THEM: "${c.question}"

They have just opened this conversation to answer. Greet them briefly, restate
what you are asking about so it is clear you remember, and then let them talk.
Keep the opening short — two or three sentences. Do not lecture, and do not
assume how it went.
''';

  /// Small helper for jittering due dates so several check-ins created in one
  /// scan don't all land on the same day.
  static int jitterDays(int base) =>
      base + Random(base).nextInt(3) - 1;
}
