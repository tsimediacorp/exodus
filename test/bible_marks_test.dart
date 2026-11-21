import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exodus/services/bible_marks.dart';
import 'package:exodus/services/storage_service.dart';
import 'package:exodus/widgets/book_spread.dart';
import 'package:exodus/widgets/ink_layer.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    BibleMarks.instance.reset();
  });

  group('highlights and notes', () {
    test('highlight, recolour and clear verses', () async {
      final marks = BibleMarks.instance;
      await marks.highlight(0, 1, [1, 2, 3], 2);
      expect(marks.chapter(0, 1).highlights, {1: 2, 2: 2, 3: 2});
      await marks.highlight(0, 1, [2], 4);
      expect(marks.chapter(0, 1).highlights[2], 4);
      await marks.highlight(0, 1, [1, 2, 3], null);
      expect(marks.chapter(0, 1).highlights, isEmpty);
    });

    test('notes persist, and an empty note deletes', () async {
      final marks = BibleMarks.instance;
      await marks.setNote(42, 3, 16, '  For God so loved.  ');
      marks.reset(); // reload from storage
      expect(marks.chapter(42, 3).notes[16], 'For God so loved.');
      await marks.setNote(42, 3, 16, '');
      expect(marks.chapter(42, 3).notes, isEmpty);
    });

    test('notes list in Bible order', () async {
      final marks = BibleMarks.instance;
      await marks.setNote(42, 3, 16, 'b');
      await marks.setNote(0, 1, 2, 'a');
      await marks.setNote(42, 1, 1, 'c');
      expect(marks.allNotes().map((n) => n.text), ['a', 'c', 'b']);
    });

    test('marks are per chapter, not shared across books', () async {
      final marks = BibleMarks.instance;
      await marks.highlight(0, 1, [1], 0);
      expect(marks.chapter(1, 1).highlights, isEmpty);
      expect(marks.chapter(0, 2).highlights, isEmpty);
    });
  });

  group('ink', () {
    test('strokes round-trip compactly', () {
      final s = InkStroke(
        id: 'x',
        verse: 5,
        color: 2,
        points: const [Offset(0.1234567, 0.5), Offset(0.9, 1.02)],
      );
      final back = InkStroke.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.verse, 5);
      expect(back.color, 2);
      expect(back.points.first.dx, closeTo(0.123, 0.001));
      expect(back.points.last.dy, closeTo(1.02, 0.001));
    });

    testWidgets('a pen stroke is pinned to the verse it starts on',
        (tester) async {
      final keys = {1: GlobalKey(), 2: GlobalKey()};
      Widget verse(int v) => SizedBox(
            key: keys[v],
            width: 300,
            height: 100,
            child: Text('verse $v'),
          );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InkLayer(
            book: 0,
            chapter: 1,
            verses: const [1, 2],
            verseKeys: keys,
            tool: InkTool.pen,
            inkColor: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [verse(1), verse(2)],
            ),
          ),
        ),
      ));
      final origin = tester.getTopLeft(find.byType(InkLayer));
      // Underline the second verse: start inside it, near its foot.
      final g = await tester.startGesture(origin + const Offset(30, 190));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(24, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();

      final ink = BibleMarks.instance.chapter(0, 1).ink;
      expect(ink, hasLength(1));
      expect(ink.single.verse, 2);
      expect(ink.single.color, 1);
      // Stored relative to verse 2's box: 30pt in of 300, 90pt down of 100.
      expect(ink.single.points.first.dx, closeTo(0.1, 0.02));
      expect(ink.single.points.first.dy, closeTo(0.9, 0.02));
    });

    testWidgets('with the pen down, the page does not turn', (tester) async {
      var turned = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BookSpread(
            pageCount: 6,
            spread: 0,
            interactive: false,
            onSpreadChanged: (_) => turned = true,
            pageBuilder: (_, i) => Center(child: Text('page $i')),
            blankBuilder: (_) => const SizedBox(),
          ),
        ),
      ));
      await tester.fling(find.byType(BookSpread), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(turned, isFalse);
      expect(find.text('page 0'), findsOneWidget);
    });
  });
}
