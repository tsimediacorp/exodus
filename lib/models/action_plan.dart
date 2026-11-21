/// One day of an [ActionPlan]: a single concrete thing to do.
class PlanStep {
  /// 1-based.
  final int day;

  /// Short headline ("Name the argument, not the person").
  final String title;

  /// What to actually do today, in a sentence or two.
  final String action;

  /// A verse to carry with it, as a reference ("Ephesians 4:26"). Optional.
  final String scripture;

  DateTime? doneAt;

  PlanStep({
    required this.day,
    required this.title,
    required this.action,
    this.scripture = '',
    this.doneAt,
  });

  bool get done => doneAt != null;

  Map<String, dynamic> toJson() => {
        'day': day,
        'title': title,
        'action': action,
        if (scripture.isNotEmpty) 'scripture': scripture,
        if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
      };

  factory PlanStep.fromJson(Map<String, dynamic> j) => PlanStep(
        day: (j['day'] as num).toInt(),
        title: (j['title'] ?? '').toString(),
        action: (j['action'] ?? '').toString(),
        scripture: (j['scripture'] ?? '').toString(),
        doneAt: j['doneAt'] == null ? null : DateTime.parse(j['doneAt']),
      );
}

/// The lengths a plan can run. A month is thirty days, not "a calendar
/// month", so day N always means the same thing.
enum PlanLength {
  threeDays(3, '3 days'),
  fiveDays(5, '5 days'),
  week(7, '1 week'),
  month(30, '1 month');

  final int days;
  final String label;
  const PlanLength(this.days, this.label);

  static PlanLength forDays(int days) =>
      values.firstWhere((l) => l.days == days, orElse: () => week);
}

/// Active Steps: a concrete, day-by-day plan EXODUS wrote with the couple
/// for something they are facing.
///
/// Counsel is good at understanding and bad at follow-through: a couple can
/// leave a conversation moved and still not know what to do on Tuesday. A
/// plan turns the conversation into a goal with an end date and one small
/// thing per day, and EXODUS keeps asking about it until it is done.
class ActionPlan {
  final String id;

  /// The conversation it came out of, so the plan can lead back to it.
  final String? conversationId;

  /// What it is for, in a few words ("Stop the money argument").
  final String title;

  /// The concrete goal: what will be true at the end.
  final String goal;

  final DateTime startedAt;
  final List<PlanStep> steps;

  /// Set when the couple ends a plan early. A finished plan is one whose
  /// steps are all done.
  DateTime? endedAt;

  ActionPlan({
    required this.id,
    required this.title,
    required this.goal,
    required this.steps,
    this.conversationId,
    DateTime? startedAt,
    this.endedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  int get length => steps.length;
  int get doneCount => steps.where((s) => s.done).length;
  double get progress => steps.isEmpty ? 0 : doneCount / steps.length;
  bool get isComplete => steps.isNotEmpty && doneCount == steps.length;
  bool get isActive => endedAt == null && !isComplete;

  /// Which day of the plan [now] falls on, 1-based, clamped to the plan.
  int dayOn(DateTime now) {
    final start = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return (today.difference(start).inDays + 1).clamp(1, steps.length);
  }

  /// The step to show as "today": the first one not done, never ahead of
  /// the calendar day. Falling behind does not skip steps; it waits.
  PlanStep? currentStep(DateTime now) {
    for (final s in steps) {
      if (!s.done) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (conversationId != null) 'conversationId': conversationId,
        'title': title,
        'goal': goal,
        'startedAt': startedAt.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory ActionPlan.fromJson(Map<String, dynamic> j) => ActionPlan(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String?,
        title: (j['title'] ?? '').toString(),
        goal: (j['goal'] ?? '').toString(),
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt']),
        steps: (j['steps'] as List<dynamic>)
            .map((e) => PlanStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
