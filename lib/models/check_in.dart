/// Where a check-in stands.
enum CheckInStatus {
  /// Waiting for its due date.
  pending,

  /// Shown to the couple; they haven't responded yet.
  raised,

  /// They engaged with it — opened it in Counsel and talked it through.
  answered,

  /// They dismissed it. Never raise this one again.
  dismissed,
}

/// Something EXODUS noticed and means to come back to.
///
/// Built from durable memory: a struggle they named, a prayer they asked for,
/// a decision they were weighing. The point is that the app remembers what
/// mattered to them and asks about it later, unprompted.
class CheckIn {
  final String id;

  /// The one-line thing being followed up on, in EXODUS's words — used as the
  /// card's body and the notification text.
  final String question;

  /// What in their history prompted this, kept so the couple can see why they
  /// are being asked and so the seeded conversation has context.
  final String because;

  /// Loose category, only for the card's icon and grouping.
  final String topic;

  final DateTime createdAt;

  /// When this becomes fair to raise. Deliberately not immediate — following
  /// up an hour after someone mentions a struggle is not care, it's nagging.
  final DateTime dueAt;

  CheckInStatus status;
  DateTime? raisedAt;
  DateTime? resolvedAt;

  CheckIn({
    required this.id,
    required this.question,
    required this.because,
    required this.topic,
    required this.dueAt,
    DateTime? createdAt,
    this.status = CheckInStatus.pending,
    this.raisedAt,
    this.resolvedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isOpen =>
      status == CheckInStatus.pending || status == CheckInStatus.raised;

  bool get isDue => isOpen && !DateTime.now().isBefore(dueAt);

  /// Rough duplicate key — the same struggle re-extracted from memory next
  /// week shouldn't become a second card.
  String get fingerprint =>
      question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'because': because,
        'topic': topic,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt.toIso8601String(),
        'status': status.name,
        if (raisedAt != null) 'raisedAt': raisedAt!.toIso8601String(),
        if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
      };

  factory CheckIn.fromJson(Map<String, dynamic> j) => CheckIn(
        id: j['id'] as String,
        question: j['question'] as String? ?? '',
        because: j['because'] as String? ?? '',
        topic: j['topic'] as String? ?? 'general',
        createdAt: DateTime.parse(j['createdAt'] as String),
        dueAt: DateTime.parse(j['dueAt'] as String),
        status: CheckInStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => CheckInStatus.pending,
        ),
        raisedAt: j['raisedAt'] != null
            ? DateTime.parse(j['raisedAt'] as String)
            : null,
        resolvedAt: j['resolvedAt'] != null
            ? DateTime.parse(j['resolvedAt'] as String)
            : null,
      );
}
