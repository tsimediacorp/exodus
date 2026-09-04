/// Follow-up questions EXODUS offers at the end of a reply.
///
/// The model is asked to close each Counsel reply with a machine-readable
/// line — `[[NEXT: question one | question two]]` — which this strips out and
/// turns into tappable chips. It is the cheapest way to get genuinely
/// contextual next steps: no second model call, no guessing from keywords.
///
/// The whole thing is best-effort by design. A model that ignores the
/// instruction, half-writes the marker, or is cut off mid-token must still
/// produce a clean reply — so [strip] is written to remove anything
/// marker-shaped, and a reply with no follow-ups simply shows none.
class FollowUps {
  FollowUps._();

  /// Matches a complete marker anywhere in the text, case-insensitively.
  static final RegExp _complete =
      RegExp(r'\[\[\s*NEXT\s*:(.*?)\]\]', caseSensitive: false, dotAll: true);

  /// An OPENING marker with no close. A stopped or truncated reply can end
  /// mid-marker, and showing the user a dangling "[[NEXT: how do we" is worse
  /// than showing nothing.
  static final RegExp _dangling =
      RegExp(r'\[\[\s*NEXT\s*:.*$', caseSensitive: false, dotAll: true);

  /// The questions offered, in order. Empty when there are none.
  ///
  /// Capped at three: this is a nudge, not a menu, and a column of six
  /// suggestions turns a conversation into a quiz.
  static List<String> parse(String content) {
    final match = _complete.firstMatch(content);
    if (match == null) return const [];
    final found = <String>[];
    for (final part in (match.group(1) ?? '').split('|')) {
      final question = part.trim().replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
      // A stray empty segment ("a || b") should not become an empty chip.
      if (question.isNotEmpty && question.length <= 120) found.add(question);
      if (found.length == 3) break;
    }
    return found;
  }

  /// The reply as the couple should read it, with any marker removed.
  static String strip(String content) {
    var text = content.replaceAll(_complete, '');
    text = text.replaceAll(_dangling, '');
    // Collapse the blank lines the removal leaves behind, then trim — a reply
    // should never end in the whitespace where a marker used to be.
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight();
  }

  /// Whether [content] still has an unterminated marker being written.
  ///
  /// While streaming, the marker arrives character by character; without this
  /// the user watches "[[NEXT: how" type itself out before it disappears.
  static bool isWritingMarker(String content) =>
      _complete.firstMatch(content) == null && _dangling.hasMatch(content);
}
