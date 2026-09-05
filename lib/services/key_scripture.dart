/// The one passage a reply is built on.
///
/// EXODUS marks it with `[[KEY: 1 Peter 5:7]]` — the model is the only thing
/// that knows which of the verses it cited is the ANCHOR rather than a
/// supporting reference, and guessing from position or citation count gets it
/// wrong exactly when the answer is layered.
///
/// The marker is stripped before anything renders. It must never reach the
/// reader, so the same three cases the follow-up marker taught us are handled:
/// a complete marker, a DANGLING one from a stopped or truncated reply, and
/// the gap left behind.
class KeyScripture {
  KeyScripture._();

  static final RegExp _complete =
      RegExp(r'\[\[\s*KEY\s*:(.*?)\]\]', caseSensitive: false, dotAll: true);

  static final RegExp _dangling =
      RegExp(r'\[\[\s*KEY\s*:.*$', caseSensitive: false, dotAll: true);

  /// The marked reference, or null when the reply has no single anchor.
  ///
  /// Null is the normal case for a practical answer with no verse at its
  /// centre — a hero card on every reply would make the card mean nothing.
  static String? parse(String content) {
    final match = _complete.firstMatch(content);
    if (match == null) return null;
    final reference = (match.group(1) ?? '')
        .trim()
        .replaceAll(RegExp(r'^["“]|["”]$'), '')
        .trim();
    // A reference is short. Anything long is the model having written prose
    // into the marker, which is not something to render as a citation.
    if (reference.isEmpty || reference.length > 40) return null;
    return reference;
  }

  /// The reply as the couple should read it, with the marker removed.
  static String strip(String content) {
    var text = content.replaceAll(_complete, '');
    text = text.replaceAll(_dangling, '');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight();
  }
}
