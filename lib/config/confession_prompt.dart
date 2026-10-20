/// Instruction layer for responding to a confession.
///
/// Operates from the master prompt, supplied automatically because
/// [ConfessionService] generates through [AiService], which injects
/// `MasterPrompt.build()` as the system message. This file carries only the
/// task. It must not restate or contradict doctrine — that lives in
/// master_prompt.dart.
class ConfessionPrompt {
  /// The task message asking for a prayer over what was confessed.
  ///
  /// The instruction is unusually specific about what NOT to do, because the
  /// default failure mode here is pastoral counselling: follow-up questions,
  /// probing for detail, a plan. Someone who has just confessed something has
  /// not asked to be interviewed about it. They asked to be prayed for.
  ///
  /// [recentRefs] and [recentOpenings] come from the last few prayers on this
  /// device. Left to itself the model prays one prayer: "Father, we come
  /// before You with a heart that has been broken by…", over 1 John 1:9, which
  /// the format line below used to name as its example. Only the reference and
  /// the first few words of each prayer are sent, never what was confessed.
  static String task(
    String confession, {
    List<String> recentRefs = const [],
    List<String> recentOpenings = const [],
  }) {
    final avoid = recentRefs.isEmpty && recentOpenings.isEmpty
        ? ''
        : '''

Recent prayers here have already used what follows. Do not reuse any of it:
${recentRefs.map((r) => '- passage: $r').join('\n')}
${recentOpenings.map((o) => '- opening: "$o…"').join('\n')}
''';
    return '''
Someone has confessed the following, anonymously. They are not asking for
advice, a plan, or questions. They are asking to be prayed for.

CONFESSION:
"""
$confession
"""

Pray over them. Do not interrogate, do not ask follow-up questions, do not
propose steps, and do not tell them what they should have done. Do not
minimise it either — "it's not that bad" is not grace, it is dismissal.

Name the thing honestly, hold out the forgiveness that is actually available
in Christ, and pray. Speak to them as one person, not as a couple.

Let the prayer be about THIS confession, in its own words: its first line
should belong to what was confessed and could not be prayed over anything
else. Do not open with "Father, we come before You" or any stock opening, and
choose the passage that fits this sin and this person rather than the verse
most often quoted about confession.
$avoid
Return ONLY a single valid JSON object — no markdown, no code fences, no text
before or after. Use exactly these keys, values in plain prose:

{
  "scriptureRef": "one passage the prayer rests on, as book chapter:verse",
  "prayer": "3-5 sentences, addressed to God, on their behalf"
}
''';
  }
}
