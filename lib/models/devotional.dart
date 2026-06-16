/// The couple's current devotional goal. Editable at any time.
class DevotionalGoal {
  String text;
  DateTime updatedAt;

  DevotionalGoal({required this.text, DateTime? updatedAt})
      : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() =>
      {'text': text, 'updatedAt': updatedAt.toIso8601String()};

  factory DevotionalGoal.fromJson(Map<String, dynamic> j) => DevotionalGoal(
        text: j['text'] as String,
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );
}

/// A single day's devotional, generated for the couple's goal.
class Devotional {
  /// Day key, yyyy-mm-dd — also the storage identity (one per day).
  final String dayKey;
  final DateTime day;
  final String title;
  final String scriptureRef;
  final String scriptureText;
  final String reflection;
  final String prayer;
  final String action;

  /// The goal this devotional was generated for (snapshot).
  final String goalSnapshot;

  Devotional({
    required this.day,
    required this.title,
    required this.scriptureRef,
    required this.scriptureText,
    required this.reflection,
    required this.prayer,
    required this.action,
    required this.goalSnapshot,
  }) : dayKey = keyFor(day);

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Build from the model's JSON object. Tolerates missing keys.
  factory Devotional.fromGenerated({
    required DateTime day,
    required Map<String, dynamic> json,
    required String goal,
  }) {
    String s(String k) => (json[k] ?? '').toString().trim();
    return Devotional(
      day: day,
      title: s('title').isEmpty ? 'Today\'s Devotional' : s('title'),
      scriptureRef: s('scriptureRef'),
      scriptureText: s('scriptureText'),
      reflection: s('reflection'),
      prayer: s('prayer'),
      action: s('action'),
      goalSnapshot: goal,
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day.toIso8601String(),
        'title': title,
        'scriptureRef': scriptureRef,
        'scriptureText': scriptureText,
        'reflection': reflection,
        'prayer': prayer,
        'action': action,
        'goalSnapshot': goalSnapshot,
      };

  factory Devotional.fromJson(Map<String, dynamic> j) => Devotional(
        day: DateTime.parse(j['day'] as String),
        title: j['title'] as String? ?? '',
        scriptureRef: j['scriptureRef'] as String? ?? '',
        scriptureText: j['scriptureText'] as String? ?? '',
        reflection: j['reflection'] as String? ?? '',
        prayer: j['prayer'] as String? ?? '',
        action: j['action'] as String? ?? '',
        goalSnapshot: j['goalSnapshot'] as String? ?? '',
      );
}
