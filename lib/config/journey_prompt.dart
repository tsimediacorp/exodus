/// Instruction layer for generating one day of a guided [Journey].
///
/// Same contract as [DevotionalPrompt]: doctrine and voice come from
/// `MasterPrompt.build()`, which [AiService] injects as the system message.
/// This file only supplies the per-day task. The difference from a daily
/// devotional is the arc — each day is one step in a numbered plan, so the
/// model is told where in the plan it is and what has already been covered.
class JourneyPrompt {
  static String day({
    required String journeyTitle,
    required String theme,
    required int dayNumber,
    required int totalDays,
    List<String> usedRefs = const [],
    List<String> previousTitles = const [],
  }) {
    final avoid = usedRefs.isEmpty
        ? ''
        : '''

Scripture already used earlier in this plan — choose a genuinely different
passage:
${usedRefs.map((r) => '- $r').join('\n')}
''';
    final covered = previousTitles.isEmpty
        ? ''
        : '''

Ground already covered in this plan (build on it, don't repeat it):
${previousTitles.map((t) => '- $t').join('\n')}
''';

    final position = dayNumber == 1
        ? 'This is the OPENING day — set the foundation and name honestly what '
            'is at stake for a couple in this area.'
        : dayNumber == totalDays
            ? 'This is the FINAL day — bring the arc to a close, call them to a '
                'lasting commitment, and send them out with hope.'
            : 'This is a middle day — go deeper than day ${dayNumber - 1} did, '
                'and leave room for the days still ahead.';

    return '''
Write day $dayNumber of $totalDays in a guided plan for this young Christian
couple.

PLAN: "$journeyTitle"
WHAT THE PLAN IS ABOUT: $theme

$position
$covered$avoid
Each day must stand on its own but clearly belong to the arc — a couple working
through all $totalDays days should feel taken somewhere, not handed $totalDays
unrelated devotionals.

Return ONLY a single valid JSON object — no markdown, no code fences, no text
before or after. Use exactly these keys, all string values in plain prose
(no markdown inside them):

{
  "title": "a short, warm title for this day",
  "scriptureRef": "book chapter:verse, e.g. Ephesians 5:25",
  "scriptureText": "the verse(s), quoted",
  "reflection": "2-3 short paragraphs opening up the passage for this day's step",
  "prayer": "a short prayer they can pray together",
  "action": "one concrete thing to do together today"
}

Keep it scripture-first and fully aligned with who you are and what you
believe (above). Speak to them as a couple.
''';
  }
}
