/// Instruction layer for proactive check-ins.
///
/// Doctrine and voice come from `MasterPrompt.build()`, injected by
/// [AiService]. This only supplies the task: read what EXODUS knows about the
/// couple and decide what is genuinely worth coming back to.
class CheckInPrompt {
  static String find({
    required String memory,
    required String existing,
    required String recentActivity,
  }) =>
      '''
Below is what you know about this couple, gathered from your past
conversations with them.

WHAT YOU KNOW:
$memory

WHAT THEY HAVE BEEN DOING LATELY:
$recentActivity
${existing.isEmpty ? '' : '''
YOU ARE ALREADY PLANNING TO ASK ABOUT THESE — do not repeat them:
$existing
'''}
Decide what, if anything, you should follow up on unprompted — the way someone
who actually cares would remember and come back to it later.

Good candidates:
- A struggle or conflict they named that had no resolution.
- Something they asked prayer for.
- A decision they were weighing.
- A goal or commitment they made to each other.
- A hard season they mentioned in passing.

Do NOT follow up on:
- Anything already resolved, or that reads as settled.
- Small talk, preferences, or facts with nothing at stake.
- Anything you are already planning to ask about (listed above).
- Anything so private or raw that an unprompted question would feel intrusive
  rather than caring. When in doubt, leave it.

Return ONLY a valid JSON array — no markdown, no code fences, no text before
or after. Between 0 and 3 items, most important first. Return [] if nothing
genuinely warrants it; an empty list is a perfectly good answer and far better
than a manufactured question.

Each element:
{
  "question": "what you would actually say to them — one or two warm sentences, addressed to them directly",
  "because": "the specific thing from their history that prompted this, in one short phrase",
  "topic": "one of: conflict, money, intimacy, prayer, family, work, faith, health, general",
  "waitDays": <integer 2-30 — how long to leave it before asking, given how raw or ongoing it is>
}

The question is spoken to them, not about them. Warm and specific — "You
mentioned things had been tense with your mother-in-law. How has that been
since?" — never generic like "How are things going?".
''';
}
