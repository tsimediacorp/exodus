import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/follow_ups.dart';

/// The marker must NEVER reach the reader. A model that ignores the
/// instruction, half-writes it, or is stopped mid-token still has to produce a
/// clean reply — leaking "[[NEXT: how do we" into a devotional answer would be
/// worse than having no follow-ups at all.
void main() {
  group('parse', () {
    test('reads the questions in order', () {
      expect(
        FollowUps.parse('Sit with that.\n[[NEXT: How do we start? | What if she refuses?]]'),
        ['How do we start?', 'What if she refuses?'],
      );
    });

    test('a reply with no marker offers nothing', () {
      expect(FollowUps.parse('Sit with that.'), isEmpty);
    });

    test('caps at three — this is a nudge, not a quiz', () {
      expect(
        FollowUps.parse('x [[NEXT: a | b | c | d | e]]'),
        ['a', 'b', 'c'],
      );
    });

    test('empty segments do not become empty chips', () {
      expect(FollowUps.parse('x [[NEXT: a || b]]'), ['a', 'b']);
    });

    test('strips quotes the model likes to add', () {
      expect(FollowUps.parse('x [[NEXT: "How do we start?"]]'), ['How do we start?']);
    });

    test('tolerates loose spacing and casing', () {
      expect(FollowUps.parse('x [[ next :  a  |  b ]]'), ['a', 'b']);
    });

    test('an absurdly long segment is dropped rather than shown', () {
      final long = 'q' * 200;
      expect(FollowUps.parse('x [[NEXT: $long | ok]]'), ['ok']);
    });
  });

  group('strip', () {
    test('removes a complete marker', () {
      expect(FollowUps.strip('Sit with that.\n\n[[NEXT: a | b]]'),
          'Sit with that.');
    });

    test('removes a DANGLING marker from a truncated reply', () {
      // A stopped reply can end mid-marker; a half-written one must not show.
      expect(FollowUps.strip('Sit with that.\n\n[[NEXT: How do we'),
          'Sit with that.');
    });

    test('leaves an ordinary reply untouched', () {
      const reply = 'Anger is not the sin.\n\nAnger nursed is.';
      expect(FollowUps.strip(reply), reply);
    });

    test('does not eat square brackets that are not markers', () {
      const reply = 'Read 1 John 2:23 — the [but] clause matters.';
      expect(FollowUps.strip(reply), reply);
    });

    test('collapses the gap the marker leaves behind', () {
      expect(FollowUps.strip('One.\n\n\n[[NEXT: a]]'), 'One.');
    });
  });

  group('isWritingMarker', () {
    test('true while the marker is still arriving', () {
      expect(FollowUps.isWritingMarker('Sit with that. [[NEXT: How do'), isTrue);
    });

    test('false once it is complete', () {
      expect(FollowUps.isWritingMarker('Sit with that. [[NEXT: a]]'), isFalse);
    });

    test('false for a reply that has none', () {
      expect(FollowUps.isWritingMarker('Sit with that.'), isFalse);
    });
  });
}
