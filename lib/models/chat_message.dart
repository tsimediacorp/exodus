enum Sender { user, exodus }

class ChatMessage {
  Sender sender;
  String content;
  DateTime timestamp;
  bool isLoading;
  bool isStreaming;

  /// Attached images, stored as self-contained data URLs
  /// ("data:image/jpeg;base64,..."). The same form is sent to vision models
  /// (OpenAI-compatible `image_url`) and decoded for in-bubble previews.
  /// Empty for text-only messages and all assistant replies.
  List<String> images;

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
    List<String>? images,
  })  : images = images ?? [],
        timestamp = timestamp ?? DateTime.now();

  /// OpenAI-compatible message. With no images, `content` is a plain string.
  /// With images (user turns only), `content` becomes the multimodal parts
  /// array: a text block followed by one `image_url` block per attachment.
  Map<String, dynamic> toApiFormat() {
    final role = sender == Sender.user ? 'user' : 'assistant';
    if (images.isEmpty) {
      return {'role': role, 'content': content};
    }
    return {
      'role': role,
      'content': [
        if (content.trim().isNotEmpty) {'type': 'text', 'text': content},
        for (final url in images)
          {
            'type': 'image_url',
            'image_url': {'url': url},
          },
      ],
    };
  }

  Map<String, dynamic> toJson() => {
        'sender': sender.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
        if (images.isNotEmpty) 'images': images,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        sender: Sender.values.firstWhere((e) => e.name == json['sender']),
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        responseTimeMs: json['responseTimeMs'] as int?,
        images: (json['images'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );
}
