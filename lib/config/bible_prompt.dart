/// Instruction layer for the in-app Bible's AI features.
///
/// Doctrine and voice come from `MasterPrompt.build()`, injected by
/// [AiService]; this file only supplies the task.
class BiblePrompt {
  /// Ask for passages that answer a question or match a theme. The model
  /// returns references only — the app reads the actual text from the bundled
  /// translation, so it can never quote a verse that doesn't exist.
  static String search(String query, {String translation = 'KJV'}) => '''
The couple is searching the Bible for:

"$query"

Return the passages that genuinely speak to this — the ones you would actually
turn them to, not a keyword match. Between 3 and 8 of them, best first.

Return ONLY a valid JSON array — no markdown, no code fences, no text before or
after. Each element:

{
  "ref": "Book chapter:verse" or "Book chapter:verse-verse",
  "why": "one short sentence on why this passage speaks to their search"
}

Rules:
- Use full book names as they appear in an English Bible ($translation).
- Only cite passages you are certain exist, with correct chapter and verse.
- Do NOT quote the verse text — only the reference and your reason.
- If the search is unclear or has no scriptural answer, return [].
''';

  /// Explain a passage the couple selected in the reader. [question] is their
  /// own follow-up, when they asked one.
  static String explain({
    required String reference,
    required String text,
    String? question,
  }) {
    final ask = (question == null || question.trim().isEmpty)
        ? 'Explain this passage to them in detail.'
        : 'They asked: "${question.trim()}"';
    return '''
The couple is reading this passage in the Bible and has selected it:

$reference
"$text"

$ask

Cover, in plain prose:
- What it actually says, and what it meant in its own context.
- What it means for them — a young married couple — in practice.
- Anything commonly misread about it, if that applies.

Speak to the two of them directly. Reference other scripture where it genuinely
illuminates this one. Keep it tight — a few short paragraphs, not an essay.
''';
  }
}
