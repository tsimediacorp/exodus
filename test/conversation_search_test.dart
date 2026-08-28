import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/conversation_search.dart';

void main() {
  group('occurrences', () {
    test('finds every hit, case-insensitively', () {
      final hits = ConversationSearch.occurrences(
          'Anger is not the sin. ANGER nursed is.', 'anger');
      expect(hits, [0, 22]);
    });

    test('matches inside words, not just whole words', () {
      // People search for fragments as often as words.
      final hits = ConversationSearch.occurrences('forgiveness', 'forgiv');
      expect(hits, [0]);
    });

    test('does not overlap itself', () {
      // "aaa" contains one "aa", not two: the scan resumes past each hit.
      expect(ConversationSearch.occurrences('aaa', 'aa'), [0]);
      expect(ConversationSearch.occurrences('aaaa', 'aa'), [0, 2]);
    });

    test('an empty or whitespace query matches nothing', () {
      expect(ConversationSearch.occurrences('anything', ''), isEmpty);
      expect(ConversationSearch.occurrences('anything', '   '), isEmpty);
    });

    test('offsets index the original text, not the lowercased copy', () {
      const text = 'Grace. GRACE. grace.';
      final hits = ConversationSearch.occurrences(text, 'grace');
      for (final at in hits) {
        expect(text.substring(at, at + 5).toLowerCase(), 'grace');
      }
      expect(hits, hasLength(3));
    });
  });

  group('matches', () {
    const thread = [
      'We fought about money again.',
      'Money is rarely the real argument. Money is where it surfaces.',
      'That helps.',
    ];

    test('counts occurrences, not messages', () {
      final found = ConversationSearch.matches(thread, 'money');
      // One in the first message, two in the second.
      expect(found, hasLength(3));
    });

    test('numbers occurrences from zero within each message', () {
      final found = ConversationSearch.matches(thread, 'money');
      expect(found[0], (message: 0, occurrence: 0));
      expect(found[1], (message: 1, occurrence: 0));
      expect(found[2], (message: 1, occurrence: 1));
    });

    test('stays in thread order', () {
      final found = ConversationSearch.matches(thread, 'money');
      expect([for (final m in found) m.message], [0, 1, 1]);
    });

    test('the nth match agrees with what the bubble would highlight', () {
      // The contract the two callers depend on: match N names a message and an
      // occurrence index, and that index selects the same hit the bubble finds
      // when it scans that message on its own.
      final found = ConversationSearch.matches(thread, 'money');
      final third = found[2];
      final hits =
          ConversationSearch.occurrences(thread[third.message], 'money');
      expect(third.occurrence, lessThan(hits.length));
      final at = hits[third.occurrence];
      expect(thread[third.message].substring(at, at + 5).toLowerCase(), 'money');
    });

    test('no query means no matches', () {
      expect(ConversationSearch.matches(thread, ''), isEmpty);
    });

    test('a term nobody said returns nothing', () {
      expect(ConversationSearch.matches(thread, 'chariot'), isEmpty);
    });
  });
}
