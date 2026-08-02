import 'devotional.dart';

/// A multi-day guided plan. The catalog entries are static (see
/// [JourneyCatalog]); the day-by-day content is generated per couple.
class Journey {
  final String id;
  final String title;

  /// One-line promise shown on the card.
  final String subtitle;

  /// What the plan is actually about — fed to the model as the through-line
  /// so every day builds on the same arc instead of drifting.
  final String theme;

  final int totalDays;

  const Journey({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.theme,
    required this.totalDays,
  });
}

/// A couple's progress through one [Journey]. Days are generated lazily — a
/// day exists here only once it has been opened.
class JourneyProgress {
  final String journeyId;
  final DateTime startedAt;

  /// Generated content, keyed by 1-based day number. Journey days have the
  /// same shape as a devotional, so [Devotional] is reused rather than
  /// duplicated.
  final Map<int, Devotional> days;

  /// 1-based day numbers the couple has marked done.
  final Set<int> completed;

  DateTime? finishedAt;

  JourneyProgress({
    required this.journeyId,
    DateTime? startedAt,
    Map<int, Devotional>? days,
    Set<int>? completed,
    this.finishedAt,
  })  : startedAt = startedAt ?? DateTime.now(),
        days = days ?? {},
        completed = completed ?? <int>{};

  /// The next unfinished day, or null when the whole plan is done.
  int? nextDay(int totalDays) {
    for (var d = 1; d <= totalDays; d++) {
      if (!completed.contains(d)) return d;
    }
    return null;
  }

  bool isComplete(int totalDays) => completed.length >= totalDays;

  /// Scripture already used in this plan, so later days don't repeat it.
  List<String> get usedRefs => days.values
      .map((d) => d.scriptureRef)
      .where((r) => r.trim().isNotEmpty)
      .toList();

  Map<String, dynamic> toJson() => {
        'journeyId': journeyId,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        'completed': completed.toList(),
        'days': days.map((k, v) => MapEntry(k.toString(), v.toJson())),
      };

  factory JourneyProgress.fromJson(Map<String, dynamic> j) => JourneyProgress(
        journeyId: j['journeyId'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        finishedAt: j['finishedAt'] != null
            ? DateTime.parse(j['finishedAt'] as String)
            : null,
        completed: ((j['completed'] as List<dynamic>?) ?? [])
            .map((e) => e as int)
            .toSet(),
        days: ((j['days'] as Map<String, dynamic>?) ?? {}).map(
          (k, v) => MapEntry(
              int.parse(k), Devotional.fromJson(v as Map<String, dynamic>)),
        ),
      );
}
