/// A verse the couple kept, pulled from a devotional or journey day.
/// The reference is the identity — saving the same passage twice replaces it.
class SavedVerse {
  final String reference;
  final String text;
  final DateTime savedAt;

  /// Where it came from, e.g. "Daily devotional" or a journey title. Shown as
  /// context so a saved verse still means something months later.
  final String source;

  SavedVerse({
    required this.reference,
    required this.text,
    required this.source,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'text': text,
        'source': source,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedVerse.fromJson(Map<String, dynamic> j) => SavedVerse(
        reference: j['reference'] as String? ?? '',
        text: j['text'] as String? ?? '',
        source: j['source'] as String? ?? '',
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
}
