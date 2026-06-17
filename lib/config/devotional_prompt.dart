/// Instruction layer for generating a daily devotional.
///
/// Like the rest of EXODUS, the devotional must operate from the master
/// prompt — that grounding is supplied automatically because [DevotionalService]
/// generates through [AiService], which already injects `MasterPrompt.build()`
/// as the system message. This file only provides the per-day task: produce a
/// structured devotional tied to the couple's goal. It must not restate or
/// contradict doctrine — that lives in master_prompt.dart.
class DevotionalPrompt {
  /// The task message asking for today's devotional as strict JSON.
  /// [recentRefs] are scripture references used in recent days — the model must
  /// pick a DIFFERENT passage so devotionals don't repeat the same verse daily.
  static String task({
    required String goal,
    required String dateLabel,
    List<String> recentRefs = const [],
  }) {
    final avoid = recentRefs.isEmpty
        ? ''
        : '''

IMPORTANT — variety: do NOT use any of these recently-used passages (pick a
genuinely different book/passage of Scripture):
${recentRefs.map((r) => '- $r').join('\n')}
''';
    return '''
Create a daily devotional for $dateLabel for this young Christian couple,
tailored to the goal they are working on together:

GOAL: "$goal"
$avoid
Choose a fresh passage of Scripture for today — over time the devotionals
should draw from a wide range of books, not repeat the same verse.

Return ONLY a single valid JSON object — no markdown, no code fences, no text
before or after. Use exactly these keys, all string values in plain prose
(no markdown inside them):

{
  "title": "a short, warm title",
  "scriptureRef": "book chapter:verse, e.g. Ephesians 5:25",
  "scriptureText": "the verse(s), quoted",
  "reflection": "2-3 short paragraphs connecting the scripture to their goal",
  "prayer": "a short prayer they can pray together",
  "action": "one concrete thing to do together today"
}

Keep it scripture-first and fully aligned with who you are and what you
believe (above). Speak to them as a couple.
''';
  }

  /// Opening line for the conversational goal-setting flow.
  static String goalIntakeOpener() =>
      "Before I build your devotionals, tell me — what's the one thing the "
      "two of you most want God to grow in your marriage right now?";

  /// A coaching layer for the goal-intake conversation, appended to the user's
  /// first turn so EXODUS interviews them toward one clear goal.
  static String goalIntakeGuidance() => '''
[You are helping this couple name ONE clear devotional goal for their marriage.
Ask warm, short follow-up questions, one at a time, until the goal is specific.
Keep replies to 2-3 sentences. Do not produce a devotional yet.]
''';

  /// Ask the model to distill the conversation into a one-line goal.
  static String goalSummaryTask() =>
      "Based on our conversation, state the couple's devotional goal as ONE "
      "clear sentence, in plain text only — no preamble, no quotes.";
}
