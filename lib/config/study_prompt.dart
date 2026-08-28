/// Instruction layer for generating a daily Bible study exercise.
///
/// Like the rest of EXODUS this operates from the master prompt, supplied
/// automatically because [StudyService] generates through [AiService], which
/// injects `MasterPrompt.build()` as the system message. This file only
/// carries the per-day task. It must not restate or contradict doctrine —
/// that lives in master_prompt.dart.
class StudyPrompt {
  /// The forms a study exercise can take.
  ///
  /// Naming forms explicitly is what stops the model producing a devotional
  /// with the word "exercise" on it. Asked for "a Bible study exercise" it
  /// reliably returns read-a-verse-and-reflect; given a form to work in, it
  /// produces an actual practice. The list is deliberately varied in posture —
  /// adversarial, analytical, imaginative, physical, relational — so a week of
  /// exercises does not feel like one exercise with different verses.
  static const List<String> forms = [
    'courtroom — write out what the accuser says about you, then answer each '
        'accusation with what Scripture says, as evidence entered before God '
        'as judge',
    'word study — trace one word through several passages and watch what it '
        'means in each',
    'cross-examination — interrogate a character\'s choice in a narrative: '
        'what they knew, what they feared, what they did',
    'lament — write your own psalm of complaint in the structure the psalms '
        'actually use, ending where they end',
    'rewrite the prayer — take a prayer from Scripture and rewrite it in your '
        'own circumstances, line by line',
    'copy by hand — write a passage out longhand and mark what you notice on '
        'the third reading that you missed on the first',
    'preach to yourself — argue a promise of God against the thing you '
        'actually believe about yourself at 3am',
    'contrast study — put two passages side by side that appear to disagree, '
        'and work out what each is actually claiming',
    'promise inventory — collect every promise in a passage and name which '
        'one you are currently living as though were false',
    'timeline — map the sequence of events in a narrative and find the moment '
        'the outcome became inevitable',
    'name the idol — trace a desire in your own week back to what it is '
        'promising you, and find where Scripture addresses that promise',
    'intercession — pray a passage for your spouse, phrase by phrase, out '
        'loud, in front of them',
    'obedience audit — take one command and list, concretely, what obeying it '
        'this week would cost',
    'question the text — write down every question a passage raises that you '
        'cannot answer, then find which ones Scripture answers elsewhere',
    'testimony — tell the story of something God did in your marriage using '
        'the shape of a biblical deliverance narrative',
  ];

  /// The task message asking for today's exercise as strict JSON.
  ///
  /// [recentTitles] and [recentForms] are what has already been served, so the
  /// model picks something genuinely new rather than rotating three favourites.
  static String task({
    required String dateLabel,
    List<String> recentTitles = const [],
    List<String> recentForms = const [],
  }) {
    final avoidTitles = recentTitles.isEmpty
        ? ''
        : '''

Do NOT repeat any of these recent exercises:
${recentTitles.map((t) => '- $t').join('\n')}
''';
    final avoidForms = recentForms.isEmpty
        ? ''
        : '''
Recently used forms — choose a DIFFERENT one:
${recentForms.map((f) => '- $f').join('\n')}
''';

    return '''
Create today's Bible study exercise for $dateLabel, for a young Christian
couple. This is $dateLabel — make it feel written for today, not generic.

An EXERCISE is something they DO, not something they read. It must have
concrete steps they can work through in 15-25 minutes, with paper or out
loud. If what you produce could be read passively from start to finish and
still be "finished", it is a devotional and it is wrong.

Work in ONE of these forms:
${forms.map((f) => '- $f').join('\n')}
$avoidForms$avoidTitles
Pick a fresh passage — over time these should range widely across Scripture,
Old Testament as well as New.

Return ONLY a single valid JSON object — no markdown, no code fences, no text
before or after. Use exactly these keys, all values in plain prose (no
markdown inside them):

{
  "title": "a short, vivid name for the practice",
  "form": "the form you chose, in one or two words",
  "premise": "one sentence on what this practice is for",
  "scriptureRef": "book chapter:verse, e.g. Ephesians 6:12",
  "scriptureText": "the passage, quoted",
  "steps": ["4 to 6 concrete instructions, each one action, in order"],
  "question": "one question to sit with once the steps are done",
  "closingPrayer": "a short prayer to close with, 2-3 sentences"
}

Write the steps as instructions to the couple ("Write down…", "Read it aloud
and stop at…"), never as description of what the exercise is about. Keep it
scripture-first and fully aligned with who you are and what you believe.
''';
  }
}
