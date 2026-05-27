import 'chat_message.dart';

class Conversation {
  final String id;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Conversation.empty() {
    final now = DateTime.now();
    return Conversation(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      title: 'New conversation',
      messages: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Derive a short title from the first user message. Called after the first
  /// exchange so the drawer entry isn't stuck on "New conversation."
  void deriveTitleFromFirstUserMessage() {
    final firstUser = messages.firstWhere(
      (m) => m.sender == Sender.user && m.content.trim().isNotEmpty,
      orElse: () => ChatMessage(content: '', sender: Sender.user),
    );
    if (firstUser.content.trim().isEmpty) return;
    final raw = firstUser.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    title = raw.length <= 48 ? raw : '${raw.substring(0, 45)}...';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages
            .where((m) => !m.isLoading && m.content.isNotEmpty)
            .map((m) => m.toJson())
            .toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Conversation',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List<dynamic>)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
