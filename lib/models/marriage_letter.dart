/// A weekly letter EXODUS writes to the couple, drawn from what they actually
/// did that week. Identity is the week it covers, so regenerating a week
/// replaces it rather than piling up duplicates.
class MarriageLetter {
  /// Monday of the week this letter covers, normalised to midnight.
  final DateTime weekStart;
  final String weekKey;
  final String body;
  final DateTime generatedAt;

  /// Short human summary of what fed the letter ("3 devotionals · 1 coaching
  /// session"), so the couple can see it was built from their real week.
  final String basis;

  MarriageLetter({
    required DateTime weekStart,
    required this.body,
    required this.basis,
    DateTime? generatedAt,
  })  : weekStart = startOfWeek(weekStart),
        weekKey = keyFor(weekStart),
        generatedAt = generatedAt ?? DateTime.now();

  /// Monday 00:00 of the week containing [d].
  static DateTime startOfWeek(DateTime d) {
    final midnight = DateTime(d.year, d.month, d.day);
    return midnight.subtract(Duration(days: midnight.weekday - DateTime.monday));
  }

  static String keyFor(DateTime d) {
    final s = startOfWeek(d);
    return '${s.year.toString().padLeft(4, '0')}-'
        '${s.month.toString().padLeft(2, '0')}-'
        '${s.day.toString().padLeft(2, '0')}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// e.g. "Jul 27 – Aug 2"
  String get rangeLabel {
    final end = weekStart.add(const Duration(days: 6));
    final a = '${_months[weekStart.month - 1]} ${weekStart.day}';
    final b = '${_months[end.month - 1]} ${end.day}';
    return '$a – $b';
  }

  Map<String, dynamic> toJson() => {
        'weekStart': weekStart.toIso8601String(),
        'body': body,
        'basis': basis,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory MarriageLetter.fromJson(Map<String, dynamic> j) => MarriageLetter(
        weekStart: DateTime.parse(j['weekStart'] as String),
        body: j['body'] as String? ?? '',
        basis: j['basis'] as String? ?? '',
        generatedAt: DateTime.parse(j['generatedAt'] as String),
      );
}
