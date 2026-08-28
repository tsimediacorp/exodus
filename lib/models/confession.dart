/// Something confessed, and the prayer EXODUS returned over it.
///
/// Confidentiality is the whole feature, so the shape is deliberately spare:
/// there is no author, no couple, no id that ties this to a person. It never
/// leaves the device except as the text of one model request — see
/// [ConfessionService] — and it is never written to memory, which is what
/// would otherwise let a confession resurface in a check-in card in front of a
/// spouse.
class Confession {
  /// Local identity only — a timestamp-derived key for storage and deletion.
  /// Not an account id and not sent anywhere.
  final String id;

  final DateTime createdAt;

  /// What was confessed. Stored so the prayer has something to sit beneath;
  /// [ConfessionService.forget] removes both together.
  final String text;

  /// The prayer EXODUS prayed over it. Empty while it is still being written,
  /// or if the model could not be reached.
  String prayer;

  /// Scripture the prayer rests on, e.g. "1 John 1:9". May be empty.
  String scriptureRef;

  /// Set when the prayer came from the built-in bank rather than the model —
  /// surfaced in the UI so a canned response is never passed off as a fresh
  /// one.
  bool isFallback;

  Confession({
    required this.id,
    required this.createdAt,
    required this.text,
    this.prayer = '',
    this.scriptureRef = '',
    this.isFallback = false,
  });

  factory Confession.now(String text) => Confession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        text: text,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'text': text,
        'prayer': prayer,
        'scriptureRef': scriptureRef,
        'isFallback': isFallback,
      };

  factory Confession.fromJson(Map<String, dynamic> j) => Confession(
        id: j['id'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        text: j['text'] as String? ?? '',
        prayer: j['prayer'] as String? ?? '',
        scriptureRef: j['scriptureRef'] as String? ?? '',
        isFallback: j['isFallback'] as bool? ?? false,
      );
}
