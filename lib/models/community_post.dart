/// Strip the punctuation nobody types.
///
/// An em dash is the single clearest tell that a machine wrote a sentence.
/// People typing on a phone use commas, full stops and the occasional run-on;
/// they do not reach for U+2014. The prompt asks for this, and the model will
/// still produce them, so it is enforced here rather than hoped for.
///
/// Applied to everything in a member's voice, on the way in AND on the way out
/// of storage, so posts written before this existed are cleaned up too.
///
/// Horizontal whitespace only around each pattern: a dash opening a paragraph
/// must not swallow the blank line before it and weld two paragraphs together.
String asTyped(String text) {
  var out = text
      // " — ", "—", " -- " all become the comma a person would have used.
      .replaceAll(RegExp(r'[ \t]*(?:—|–|--)[ \t]*'), ', ')
      // A comma straight after other punctuation was doing no work.
      .replaceAllMapped(
          RegExp(r'([,.!?;:])[ \t]*,[ \t]*'), (m) => '${m[1]} ')
      .replaceAll(RegExp(r',[ \t]*,+'), ',')
      // The single-character ellipsis is the other giveaway.
      .replaceAll('…', '...')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ');

  // A comma cannot open a line or close one.
  out = out
      .replaceAllMapped(RegExp(r'(^|\n)[ \t]*,[ \t]*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r',[ \t]*(\n|$)'), (m) => m[1]!);
  return out.trim();
}

/// One story in the community feed, with the conversation underneath it.
///
/// Every post carries [composite] because every post currently IS one: written
/// by EXODUS from the patterns couples bring it, not typed by a stranger.
/// Nothing shown to the reader distinguishes them today. The flag is kept per
/// post anyway, and stored rather than inferred, because the plan is to clear
/// the generated ones at launch — and that is only possible if each post
/// already knows which it is.
class CommunityPost {
  final String id;

  /// A first name and a last initial. Not a real person.
  final String author;

  /// How long they say they have been married — the detail that makes a
  /// stranger feel like a peer rather than an example.
  final String authorContext;

  /// What this is about: 'Rebellion', 'Money', 'Trust'. Matched against the
  /// couple's own struggles, and shown as a chip.
  final String tag;

  final String title;

  /// The story: where they were, and what changed. Not advice — the whole
  /// point is that it is told from inside the thing.
  final String body;

  final DateTime createdAt;
  final List<CommunityReply> replies;

  /// Written by EXODUS rather than posted by a member. Not surfaced in the UI;
  /// this is what makes the generated posts findable when they are cleared.
  final bool composite;

  /// True once the couple has opened the thread.
  bool read;

  /// Written in the admin panel rather than generated on the device.
  ///
  /// Curated posts are replaced wholesale on every check-in, so this is what
  /// tells the device which of its posts it is allowed to throw away.
  bool get curated => id.startsWith('curated-');

  CommunityPost({
    required this.id,
    required this.author,
    required this.authorContext,
    required this.tag,
    required this.title,
    required this.body,
    required this.replies,
    this.composite = true,
    this.read = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'authorContext': authorContext,
        'tag': tag,
        'title': title,
        'body': body,
        'composite': composite,
        'read': read,
        'createdAt': createdAt.toIso8601String(),
        'replies': replies.map((r) => r.toJson()).toList(),
      };

  factory CommunityPost.fromJson(Map<String, dynamic> j) => CommunityPost(
        id: j['id'] as String,
        author: asTyped(j['author'] as String? ?? 'A member'),
        authorContext: asTyped(j['authorContext'] as String? ?? ''),
        tag: j['tag'] as String? ?? 'Marriage',
        title: asTyped(j['title'] as String? ?? ''),
        body: asTyped(j['body'] as String? ?? ''),
        composite: j['composite'] as bool? ?? true,
        read: j['read'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        replies: ((j['replies'] as List<dynamic>?) ?? const [])
            .map((e) => CommunityReply.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Build from one element of the model's JSON array.
  ///
  /// Lenient on purpose: a post missing its replies is still worth showing,
  /// and rejecting the whole batch over one malformed field would leave the
  /// couple staring at an empty feed. [isUsable] is what decides.
  factory CommunityPost.fromGenerated(
    Map<String, dynamic> json, {
    required String id,
    required DateTime createdAt,
  }) {
    final replies = ((json['replies'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return CommunityPost(
      id: id,
      author: asTyped(json['author'] as String? ?? ''),
      authorContext: asTyped(json['authorContext'] as String? ?? ''),
      tag: (json['tag'] as String? ?? 'Marriage').trim(),
      title: asTyped(json['title'] as String? ?? ''),
      body: asTyped(json['body'] as String? ?? ''),
      createdAt: createdAt,
      replies: [
        for (var i = 0; i < replies.length; i++)
          CommunityReply.fromGenerated(
            replies[i],
            id: '$id-r$i',
            // Replies land after the post, spaced so the thread reads as a
            // conversation over hours rather than a wall posted at once.
            createdAt: createdAt.add(Duration(hours: 2 + i * 5)),
          ),
      ],
    );
  }

  /// Enough of a post to be worth showing.
  ///
  /// A story with no body is an empty card, and one with no replies is not a
  /// community — it is a testimonial, which is the thing this must not become.
  bool get isUsable =>
      author.isNotEmpty &&
      title.isNotEmpty &&
      body.length > 40 &&
      replies.where((r) => r.isUsable).length >= 2;

  int get replyCount => replies.length;
}

/// One reply in a thread.
class CommunityReply {
  final String id;
  final String author;
  final String body;
  final DateTime createdAt;

  /// The original poster answering someone — what turns a list of comments
  /// into a back-and-forth.
  final bool fromAuthor;

  CommunityReply({
    required this.id,
    required this.author,
    required this.body,
    required this.fromAuthor,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'body': body,
        'fromAuthor': fromAuthor,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CommunityReply.fromJson(Map<String, dynamic> j) => CommunityReply(
        id: j['id'] as String,
        author: asTyped(j['author'] as String? ?? 'A member'),
        body: asTyped(j['body'] as String? ?? ''),
        fromAuthor: j['fromAuthor'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  factory CommunityReply.fromGenerated(
    Map<String, dynamic> json, {
    required String id,
    required DateTime createdAt,
  }) =>
      CommunityReply(
        id: id,
        author: asTyped(json['author'] as String? ?? ''),
        body: asTyped(json['body'] as String? ?? ''),
        fromAuthor: json['fromAuthor'] as bool? ?? false,
        createdAt: createdAt,
      );

  bool get isUsable => author.isNotEmpty && body.length > 15;
}
