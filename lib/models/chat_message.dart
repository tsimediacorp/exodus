enum Sender { user, exodus }

class ChatMessage {
  Sender sender;
  String content;
  DateTime timestamp;
  bool isLoading;
  bool isStreaming;

  /// For assistant messages: how long the response took, in milliseconds.
  /// null until the stream finishes (or for user messages).
  int? responseTimeMs;

  ChatMessage({
    required this.content,
    required this.sender,
    DateTime? timestamp,
    this.isLoading = false,
    this.isStreaming = false,
    this.responseTimeMs,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, String> toApiFormat() => {
        'role': sender == Sender.user ? 'user' : 'assistant',
        'content': content,
      };

  Map<String, dynamic> toJson() => {
        'sender': sender.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        sender: Sender.values.firstWhere((e) => e.name == json['sender']),
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        responseTimeMs: json['responseTimeMs'] as int?,
      );
}
