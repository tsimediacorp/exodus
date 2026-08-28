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

  /// The goal this devotional was generated for (snapshot). Compared against
  /// the current goal so a goal change invalidates already-stored days.
  final String goalSnapshot;

  /// True when this came from the built-in fallback bank rather than the model.
  /// Persisted so a day that fell back can be retried once the network is
  /// healthy again, instead of serving canned content until midnight.
  final bool isFallback;

  Devotional({
    required this.day,
    required this.title,
    required this.scriptureRef,
    required this.scriptureText,
    required this.reflection,
    required this.prayer,
    required this.action,
    required this.goalSnapshot,
    this.isFallback = false,
  }) : dayKey = keyFor(day);

  /// Whether what's stored for a day needs to be (re)generated: nothing saved,
  /// saved content was a canned fallback, or it was written for a goal the
  /// couple has since moved on from. Storage is keyed by day alone, so without
  /// the goal comparison a goal change would keep serving the old goal's
  /// devotional.
  static bool needsGeneration(Devotional? existing, String goal) =>
      existing == null || existing.isFallback || existing.goalSnapshot != goal;

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Build from the model's JSON object. Tolerates missing keys.
  factory Devotional.fromGenerated({
    required DateTime day,
    required Map<String, dynamic> json,
    required String goal,
    bool isFallback = false,
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
      isFallback: isFallback,
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
        'isFallback': isFallback,
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
        // Records written before this field existed are treated as real
        // (not fallback) so they aren't needlessly regenerated on upgrade.
        isFallback: j['isFallback'] as bool? ?? false,
      );
}
