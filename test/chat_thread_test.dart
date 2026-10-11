import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/models/community_post.dart';
import 'package:exodus/screens/chat_screen.dart';
import 'package:exodus/services/community_service.dart';
import 'package:exodus/widgets/day_divider.dart';

void main() {
  group('day dividers', () {
    final now = DateTime(2026, 10, 11, 9, 30); // a Sunday

    test('today and yesterday are named', () {
      expect(DayDivider.label(DateTime(2026, 10, 11, 0, 5), now: now), 'Today');
      expect(DayDivider.label(DateTime(2026, 10, 10, 23, 55), now: now),
          'Yesterday');
    });

    test('yesterday is a calendar day, not twenty-four hours', () {
      // Ten hours ago, but on the other side of midnight.
      expect(DayDivider.label(DateTime(2026, 10, 10, 23, 30), now: now),
          'Yesterday');
    });

    test('the past week goes by weekday, then by date', () {
      expect(DayDivider.label(DateTime(2026, 10, 7), now: now), 'Wednesday');
      expect(DayDivider.label(DateTime(2026, 10, 4), now: now), 'October 4');
      expect(DayDivider.label(DateTime(2025, 12, 25), now: now),
          'December 25, 2025');
    });

    test('same day ignores the hour', () {
      expect(
          DayDivider.sameDay(DateTime(2026, 3, 1, 0, 1), DateTime(2026, 3, 1, 23)),
          isTrue);
      expect(
          DayDivider.sameDay(DateTime(2026, 3, 1, 23, 59), DateTime(2026, 3, 2)),
          isFalse);
    });
  });

  group('starters', () {
    test('four at a time, all different', () {
      final four = ChatScreenState.startersFor(DateTime(2026, 10, 11));
      expect(four, hasLength(4));
      expect(four.toSet(), hasLength(4));
    });

    test('tomorrow offers four others', () {
      final today = ChatScreenState.startersFor(DateTime(2026, 10, 11)).toSet();
      final tomorrow =
          ChatScreenState.startersFor(DateTime(2026, 10, 12)).toSet();
      expect(today.intersection(tomorrow), isEmpty);
    });

    test('the same day always offers the same four', () {
      expect(ChatScreenState.startersFor(DateTime(2026, 10, 11, 7)),
          ChatScreenState.startersFor(DateTime(2026, 10, 11, 22)));
    });

    test('the greeting follows the clock', () {
      expect(ChatScreenState.greetingFor(DateTime(2026, 1, 1, 7)),
          'Good morning');
      expect(ChatScreenState.greetingFor(DateTime(2026, 1, 1, 14)),
          'Good afternoon');
      expect(ChatScreenState.greetingFor(DateTime(2026, 1, 1, 21)),
          'Good evening');
      expect(ChatScreenState.greetingFor(DateTime(2026, 1, 1, 2)),
          'Good evening');
    });
  });

  group('the feed is newest first', () {
    CommunityPost post(String id, DateTime at) => CommunityPost(
          id: id,
          author: 'A B.',
          authorContext: '',
          tag: 'Trust',
          title: id,
          body: 'body',
          createdAt: at,
          replies: [
            CommunityReply(
                id: '$id-r0',
                author: 'C D.',
                body: 'reply',
                fromAuthor: false,
                createdAt: at.add(const Duration(hours: 2))),
          ],
        );

    final now = DateTime(2026, 10, 11, 0, 30);

    // The shape of the bug: last night's batch, and one written just after
    // midnight whose back-dated times fall in among it.
    final lastNight = [
      post('old-1', DateTime(2026, 10, 10, 21, 23)),
      post('old-2', DateTime(2026, 10, 10, 19, 0)),
      post('old-3', DateTime(2026, 10, 10, 16, 37)),
    ];
    final tonight = [
      post('new-1', DateTime(2026, 10, 10, 23, 53)),
      post('new-2', DateTime(2026, 10, 10, 21, 30)),
      post('new-3', DateTime(2026, 10, 10, 19, 7)),
    ];

    test('a new batch never lands underneath an older story', () {
      final placed =
          CommunityService.restampForTest(tonight, lastNight, now);
      final feed = [...placed, ...lastNight]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      expect(feed.map((p) => p.id).toList(),
          ['new-1', 'new-2', 'new-3', 'old-1', 'old-2', 'old-3']);
    });

    test('nothing is dated in the future, and the batch keeps its order', () {
      final placed =
          CommunityService.restampForTest(tonight, lastNight, now);
      for (final p in placed) {
        expect(p.createdAt.isAfter(now), isFalse);
        expect(p.createdAt.isAfter(lastNight.first.createdAt), isTrue);
      }
      expect(placed.map((p) => p.id).toList(), ['new-1', 'new-2', 'new-3']);
    });

    test('replies move with the post they answer', () {
      final placed =
          CommunityService.restampForTest(tonight, lastNight, now);
      for (final p in placed) {
        expect(p.replies.single.createdAt.difference(p.createdAt),
            const Duration(hours: 2));
      }
    });

    test('a batch that is already newer is left exactly as written', () {
      final morning = [post('m-1', DateTime(2026, 10, 11, 8))];
      final placed = CommunityService.restampForTest(
          morning, lastNight, DateTime(2026, 10, 11, 9));
      expect(placed.single.createdAt, DateTime(2026, 10, 11, 8));
    });

    test('a clock that went backwards still puts new stories on top', () {
      final placed = CommunityService.restampForTest(
          tonight, lastNight, DateTime(2026, 10, 10, 12));
      final newestOld = lastNight.first.createdAt;
      expect(placed.every((p) => p.createdAt.isAfter(newestOld)), isTrue);
    });

    test('the first batch on an empty feed is untouched', () {
      expect(CommunityService.restampForTest(tonight, const [], now), tonight);
    });
  });
}
