/// Finding a term inside an open conversation.
///
/// Two callers have to agree exactly on what "the 3rd match" means: the chat
/// screen counts matches to drive "3/12" and to decide which message to scroll
/// to, and the message bubble highlights the nth occurrence inside its own
/// text. If those two scans ever disagreed, the counter would point at one
/// word and the highlight would land on another — so both go through here.
class ConversationSearch {
  ConversationSearch._();

  /// Start offsets of every occurrence of [query] in [text], case-insensitive.
  ///
  /// Matches do not overlap: the scan resumes after the end of each hit, so
  /// "aaa" contains one "aa", not two. Whole-string comparison, not word
  /// boundaries — people search for fragments ("forgiv") as often as words.
  static List<int> occurrences(String text, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final hay = text.toLowerCase();
    final found = <int>[];
    var at = hay.indexOf(needle);
    while (at >= 0) {
      found.add(at);
      at = hay.indexOf(needle, at + needle.length);
    }
    return found;
  }

  /// Every occurrence across [texts], in thread order.
  ///
  /// Flat rather than grouped by message: "4 of 17" should count what a reader
  /// counts, which is words on screen, not messages containing them.
  static List<({int message, int occurrence})> matches(
      List<String> texts, String query) {
    final found = <({int message, int occurrence})>[];
    for (var i = 0; i < texts.length; i++) {
      final hits = occurrences(texts[i], query);
      for (var occurrence = 0; occurrence < hits.length; occurrence++) {
        found.add((message: i, occurrence: occurrence));
      }
    }
    return found;
  }
}
