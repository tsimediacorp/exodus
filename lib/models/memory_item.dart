/// One durable fact EXODUS remembers about the couple, across all conversations.
class MemoryItem {
  final String id;
  String text;
  final DateTime createdAt;

  /// Where it came from: 'chat', 'coaching', 'devotional', or 'manual'.
  final String source;

  MemoryItem({
    required this.id,
    required this.text,
    required this.source,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MemoryItem.create(String text, String source) => MemoryItem(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        text: text,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
        id: j['id'] as String,
        text: j['text'] as String,
        source: j['source'] as String? ?? 'chat',
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
