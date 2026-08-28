/// Instruction layer for the weekly marriage letter.
///
/// Doctrine and voice come from `MasterPrompt.build()`, which [AiService]
/// injects as the system message; this only supplies the task. The letter is
/// the one place EXODUS speaks unprompted, so the guidance leans hard on
/// specificity — a generic encouraging note would be worse than nothing.
class LetterPrompt {
  static String task({
    required String weekLabel,
    required String basis,
    required String goal,
  }) {
    return '''
Write this young Christian couple a short personal letter about the week of
$weekLabel that has just ended.

${goal.isEmpty ? '' : 'THE GOAL THEY ARE WORKING ON: "$goal"\n'}
WHAT THEY ACTUALLY DID THIS WEEK:
$basis

Write it as a letter to the two of them — warm, direct, and specific to the
week above. Requirements:

- Reference concrete things from their week by name. If they read a devotional
  on patience, say so. If they went quiet for four days, notice it honestly
  without shaming them.
- Name ONE thing to celebrate and ONE thing to press into next week.
- Ground it in Scripture — quote one passage that fits their actual week, and
  say why it fits.
- If the week was thin or empty, be honest and gentle about it rather than
  inventing progress they did not make. A short, true letter beats a long,
  flattering one.
- No headings, no bullet points, no markdown. Plain paragraphs, as a letter.
- Around 200-300 words. Close the way you would close a letter.

Write only the letter itself — no preamble, no title, no commentary about the
task.
''';
  }
}
