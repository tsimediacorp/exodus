/// The task prompt for the community feed.
///
/// Routed through [AiService], so the system prompt is always
/// `MasterPrompt.build()` — these stories are EXODUS speaking, grounded in the
/// same source of truth as counsel, and the voice constraints there apply here
/// too.
class CommunityPrompt {
  CommunityPrompt._();

  /// What the feed is called.
  static const String sectionTitle = 'You are not the only one';

  static String task({
    required String memoryBlock,
    required int count,
    List<String> recentTitles = const [],
    List<String> recentAuthors = const [],
    List<String> recentTags = const [],
  }) {
    final knows = memoryBlock.trim().isEmpty
        ? '''
You do not yet know what this couple is carrying. Write about the things most
couples hit early: money and who decides, in-laws, a rebellious or distant
child, feeling unseen, resentment that never got named, disagreement about
church or faith, exhaustion.
'''
        : '''
Here is what you know about the couple who will read these. Choose situations
that RHYME with theirs — near enough that they recognise themselves, not so
near that it reads as their own file handed back to them.

$memoryBlock
''';

    final avoid = StringBuffer();
    if (recentTitles.isNotEmpty) {
      avoid.writeln('Titles already used (do not repeat or paraphrase): '
          '${recentTitles.join(' | ')}');
    }
    if (recentAuthors.isNotEmpty) {
      avoid.writeln('Names already used (use different ones): '
          '${recentAuthors.join(', ')}');
    }
    if (recentTags.isNotEmpty) {
      avoid.writeln('Topics covered recently (prefer different ground): '
          '${recentTags.join(', ')}');
    }

    return '''
Write $count posts for the EXODUS community feed.

$knows
${avoid.isEmpty ? '' : '\n$avoid'}
WHAT A POST IS

A member telling the group something they are IN or have been THROUGH, in
their own words. Not advice. Not a testimony delivered from the far side with
everything tidy. The reader is meant to finish it thinking "that is my house"
— which only happens if the person sounds like someone who was actually there.

Make them specific. "We fought about money" is nothing. "I found out he had
been putting 200 dollars a month into an account I did not know about, and the
worst part was he was not spending it on anything" is a post.

VARY THE DISTANCE FROM THE PROBLEM. Roughly:
- a third should be years past it, able to say plainly what changed
- a third should be through the worst but still doing the work
- a third should be IN it right now, with no resolution to offer

That last third matters most. A feed where everyone has already won is a feed
that makes a couple in the middle of it feel further behind, which is the
exact opposite of the point.

THE REPLIES

Two to four, and they must be a CONVERSATION, not a comment section. Someone
answers the post; the original poster answers them back (set "fromAuthor":
true on those). People disagree gently, ask a real question, admit their own
version is uglier. At least one reply per thread must come from the original
poster.

VOICE

These are ordinary people, not preachers. Contractions. Unfinished thoughts.
Somebody swears mildly at most; nobody quotes Greek. Scripture appears only
where a real person would reach for it — one verse, plainly, maybe misremembered
slightly — and in most posts not at all. A feed of people quoting chapter and
verse at each other is not a community, it is a tract.

Names: first name and last initial ("Marcus T.", "Dani R."). Vary ages,
backgrounds and how long they have been married.

WHAT NOT TO WRITE

- No one is a pastor, counsellor, doctor or lawyer, and no one gives
  instructions dressed as those.
- Nobody's marriage is saved by a single prayer or a single conversation. The
  turn, where there is one, took months and cost something.
- If a post touches abuse, addiction, or someone wanting to hurt themselves,
  the person got outside help — a counsellor, a doctor, a shelter, their
  church — and says so. Never "we prayed and it stopped." A reader in that
  situation may act on what they read here.
- No miracle money, no cured illness, no spouse transformed overnight.
- Do not mention EXODUS, this app, or any app.

FORMAT

Return ONLY a JSON array. No prose before or after, no markdown fence.

[
  {
    "author": "Marcus T.",
    "authorContext": "married 9 years",
    "tag": "Rebellion",
    "title": "short, in their voice, not a headline",
    "body": "2 to 4 short paragraphs, separated by \\n\\n",
    "replies": [
      {"author": "Dani R.", "body": "...", "fromAuthor": false},
      {"author": "Marcus T.", "body": "...", "fromAuthor": true}
    ]
  }
]

"tag" is one or two words naming the struggle, capitalised: Rebellion, Money,
Trust, Distance, In-Laws, Grief, Anger, Faith, Intimacy, Exhaustion.
''';
  }
}
