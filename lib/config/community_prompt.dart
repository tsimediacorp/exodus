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

  /// Ground a post can stand on.
  ///
  /// Rotated by the day rather than left to the model. Asked openly for "what
  /// couples struggle with" it returns hidden money, in-laws and a rebellious
  /// teenager every single time, which is why the feed read as static: each
  /// day generated a fresh variant of the same five stories.
  static const List<String> subjects = [
    'money, and who gets to decide',
    'a parent or in-law who will not stay out of it',
    'a child pulling away from the faith',
    'feeling invisible in your own house',
    'resentment that was never named out loud',
    'one of you believes and the other is pretending',
    'exhaustion, and having nothing left to give each other',
    'wanting different amounts of closeness',
    'a grief one of you is carrying alone',
    'anger that arrives faster than either of you expected',
    'jealousy of a friend, a sibling, or the life you did not pick',
    'work that has quietly become the third person in the marriage',
    'recovery, and living with someone else\'s',
    'an illness that reorganised everything',
    'stepchildren, and never quite knowing your place',
    'wanting a child, or not, or not yet',
    'moving somewhere neither of you knows anyone',
    'friendships that did not survive the marriage',
    'a betrayal that was not an affair',
    'praying about the same thing for years with no answer',
    'money arriving rather than money leaving',
    'a parent whose care has landed on you',
    'the difference between being forgiven and being trusted again',
    'silence that started as peace and became distance',
  ];

  /// [count] subjects for [dayIndex], never the same set two days running.
  ///
  /// Strided rather than shuffled so consecutive days cannot overlap: with a
  /// random pick, two days in a row landing on money would look exactly like
  /// the bug this replaced.
  static List<String> subjectsFor(int dayIndex, int count) {
    if (count <= 0) return const [];
    final start = (dayIndex * count) % subjects.length;
    return [
      for (var i = 0; i < count && i < subjects.length; i++)
        subjects[(start + i) % subjects.length],
    ];
  }

  /// Words that place a line of memory on one of [subjects], by index.
  ///
  /// This is the ONLY thing the feed takes from what a couple has told EXODUS:
  /// which of twenty-four broad subjects their life touches. The model that
  /// writes the stories is never shown the memory itself. It used to be handed
  /// the whole of it with an instruction not to write it back, and wrote it
  /// back anyway — the mother-in-law, the amount, the room. A model cannot
  /// reproduce a detail it was never given.
  static const Map<int, List<String>> _cues = {
    0: ['money', 'debt', 'budget', 'spend', 'financ', 'bills', 'tith', 'loan'],
    1: ['in-law', 'in law', 'his mother', 'her mother', 'his mom', 'her mom',
        'his parents', 'her parents'],
    2: ['rebel', 'teenage', 'prodigal'],
    3: ['unseen', 'invisible', 'ignored', 'unappreciated', 'taken for granted',
        'lonely', 'alone'],
    4: ['resent', 'bitter', 'grudge'],
    5: ['unbeliev', 'not a believer', 'lukewarm', 'doubt'],
    6: ['exhaust', 'tired', 'burnout', 'burned out', 'overwhelm', 'newborn'],
    7: ['intimacy', 'sex', 'affection', 'libido', 'porn', 'lust'],
    8: ['grief', 'griev', 'miscarriage', 'died', 'passed away', 'funeral'],
    9: ['anger', 'angry', 'temper', 'yell', 'shout', 'rage'],
    10: ['jealous', 'envy', 'envious'],
    11: ['work', 'job', 'shift', 'overtime', 'career', 'boss'],
    12: ['addict', 'alcohol', 'drinking', 'sober', 'recovery', 'gambl'],
    13: ['illness', 'sick', 'diagnos', 'cancer', 'chronic', 'depress',
        'anxiety', 'surgery'],
    14: ['stepson', 'stepdaughter', 'stepchild', 'blended', 'custody'],
    15: ['infertil', 'conceive', 'pregnan', 'ivf'],
    16: ['moved', 'moving', 'relocat'],
    17: ['friend'],
    18: ['lied', 'lying', 'betray', 'secret'],
    19: ['unanswered', 'no answer', 'waiting on god'],
    20: ['inherit', 'windfall', 'promotion', 'bonus'],
    21: ['caregiv', 'caring for', 'elderly', 'dementia', 'nursing home'],
    22: ['forgiv', 'affair', 'cheat', 'unfaithful', 'infidel'],
    23: ['silent', 'silence', 'distant', 'distance', 'roommate', 'stonewall'],
  };

  /// Which subjects [memory] touches, most-mentioned first.
  static List<int> themesIn(String memory) {
    final text = memory.toLowerCase();
    if (text.trim().isEmpty) return const [];
    final hits = <int, int>{};
    _cues.forEach((subject, words) {
      var count = 0;
      for (final word in words) {
        count += RegExp('\\b${RegExp.escape(word)}').allMatches(text).length;
      }
      if (count > 0) hits[subject] = count;
    });
    final found = hits.keys.toList()
      ..sort((a, b) {
        final byCount = hits[b]!.compareTo(hits[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return found;
  }

  /// The subjects for one batch: mostly other people's lives, sometimes one
  /// that is near the couple's own.
  ///
  /// A real group is full of people whose problems are not yours. So the
  /// batch is the day's rotation with the couple's own [themes] taken OUT of
  /// it, and then at most about a third put back deliberately. A couple with
  /// one thing on their mind does not get a story about it every day either:
  /// the fewer themes there are, the less often one comes round, because the
  /// same subject turning up daily is as conspicuous as the same story.
  static List<String> groundFor({
    required int dayIndex,
    required int count,
    List<int> themes = const [],
  }) {
    if (count <= 0) return const [];
    final size = count < subjects.length ? count : subjects.length;
    final near = themes.where((t) => t >= 0 && t < subjects.length).toList();

    // The rotation, skipping the couple's own ground.
    final picked = <int>[];
    final start = (dayIndex * count) % subjects.length;
    for (var i = 0; picked.length < size && i < subjects.length; i++) {
      final at = (start + i) % subjects.length;
      if (!near.contains(at)) picked.add(at);
    }
    // Everything is their ground: fall back to the plain rotation.
    for (var i = 0; picked.length < size && i < subjects.length; i++) {
      final at = (start + i) % subjects.length;
      if (!picked.contains(at)) picked.add(at);
    }

    final due = near.isNotEmpty &&
        (count >= 5 || near.length >= 3 || dayIndex % (4 - near.length) == 0);
    if (due) {
      var wanted = (size + 1) ~/ 3;
      if (wanted > near.length) wanted = near.length;
      for (var k = 0; k < wanted; k++) {
        final theme = near[(dayIndex + k) % near.length];
        if (picked.contains(theme)) continue;
        // Not always first. A feed that opens on your own trouble every
        // morning has stopped being a feed.
        picked[(dayIndex + k * 2) % size] = theme;
      }
    }
    return [for (final at in picked) subjects[at]];
  }

  static String task({
    required int count,
    required int dayIndex,
    List<int> themes = const [],
    List<String> recentTitles = const [],
    List<String> recentAuthors = const [],
    List<String> recentTags = const [],
  }) {
    final ground = groundFor(dayIndex: dayIndex, count: count, themes: themes);
    const knows = '''
You know nothing about who will read these, and you are not writing for
anyone in particular. Each post is one stranger's life. Write from the ground
listed below and nothing else.
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
THE GROUND FOR THIS BATCH

Write one post for each of these, in this order, and do not stray onto another
subject even if it feels more natural:

${ground.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

WHAT A POST IS

A member telling the group something they are IN or have been THROUGH, in
their own words. Not advice. Not a testimony delivered from the far side with
everything tidy. The reader is meant to finish it thinking "that is my house"
That only happens if the person sounds like someone who was actually there.

Make them specific. A category is not a story. "We fought about money" tells
the reader nothing; one exact thing that happened, with the detail that made it
sting, is a post. Reach for the ordinary and precise -- an amount, a room, a
sentence somebody actually said, the thing that turned out not to be the point.

Invent those details fresh every time. Do not reuse an example you have seen,
including anything in these instructions.

Skip the first story that comes to mind for a subject, because it is the first
one that comes to everyone's: the secret account or hidden card for money, the
mother-in-law with a key for family, the affair for trust. Go one further and
write the version nobody expects.

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
where a real person would reach for it, one verse, plainly, maybe
misremembered slightly, and in most posts not at all. A feed of people quoting
chapter and verse at each other is not a community, it is a tract.

PUNCTUATION. Never use an em dash or an en dash, anywhere, in any field. Not
one. Nobody typing on a phone reaches for those, and a single one gives the
whole thing away. Use a comma, or start a new sentence. The same goes for
double hyphens and for the single-character ellipsis. Ordinary commas, full
stops and question marks only.

Names: first name and last initial ("Marcus T.", "Dani R."). Vary ages,
backgrounds and how long they have been married.

WHAT NOT TO WRITE

- No one is a pastor, counsellor, doctor or lawyer, and no one gives
  instructions dressed as those.
- Nobody's marriage is saved by a single prayer or a single conversation. The
  turn, where there is one, took months and cost something.
- If a post touches abuse, addiction, or someone wanting to hurt themselves,
  the person got outside help, a counsellor, a doctor, a shelter, their
  church, and says so. Never "we prayed and it stopped." A reader in that
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
