import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exodus/services/bible_marks.dart';
import 'package:exodus/services/storage_service.dart';
import 'package:exodus/widgets/bible_cover.dart';
import 'package:exodus/widgets/book_spread.dart';
import 'package:exodus/widgets/ink_layer.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    BibleMarks.instance.reset();
  });

  group('the highlighter', () {
    test('a wobbly pass along a line is laid flat on it', () {
      final flat = steadyMarkerLine(const [
        Offset(10, 100),
        Offset(40, 103),
        Offset(70, 98),
        Offset(120, 101),
      ]);
      expect(flat, hasLength(2));
      expect(flat.first.dy, flat.last.dy);
      expect(flat.first.dx, 10);
      expect(flat.last.dx, 120);
    });

    test('a stroke down the margin is left as drawn', () {
      const down = [Offset(5, 10), Offset(6, 60), Offset(5, 120)];
      expect(steadyMarkerLine(down), down);
    });

    testWidgets('a highlighter stroke is saved as marker, pinned to its verse',
        (tester) async {
      final keys = {1: GlobalKey(), 2: GlobalKey()};
      Widget verse(int v) =>
          SizedBox(key: keys[v], width: 300, height: 60, child: Text('v$v'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InkLayer(
            book: 0,
            chapter: 1,
            verses: const [1, 2],
            verseKeys: keys,
            tool: InkTool.marker,
            inkColor: 0,
            markerColor: 2,
            child: Column(children: [verse(1), verse(2)]),
          ),
        ),
      ));
      final origin = tester.getTopLeft(find.byType(InkLayer));
      final g = await tester.startGesture(origin + const Offset(20, 90));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(Offset(25, i.isEven ? 2 : -2));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      final ink = BibleMarks.instance.chapter(0, 1).ink;
      expect(ink, hasLength(1));
      expect(ink.single.marker, isTrue);
      expect(ink.single.verse, 2);
      expect(ink.single.color, 2);
      expect(ink.single.points, hasLength(2)); // straightened
    });

    test('marker strokes survive storage', () {
      final s = InkStroke(
          id: 'x',
          verse: 1,
          color: 1,
          marker: true,
          width: 21,
          points: const [Offset(0, 0.5), Offset(1, 0.5)]);
      expect(InkStroke.fromJson(s.toJson()).marker, isTrue);
      expect(
          InkStroke.fromJson(InkStroke(
                  id: 'y',
                  verse: 1,
                  color: 0,
                  points: const [Offset.zero]).toJson())
              .marker,
          isFalse);
    });
  });

  group('the turning page', () {
    testWidgets('one page a view turns one page at a time', (tester) async {
      var view = 0;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: BookSpread(
              pagesPerView: 1,
              pageCount: 5,
              spread: view,
              onSpreadChanged: (s) => setState(() => view = s),
              pageBuilder: (_, i) => ColoredBox(
                  color: Colors.white, child: Center(child: Text('page $i'))),
              blankBuilder: (_) => const SizedBox(),
            ),
          ),
        ),
      ));
      await tester.fling(find.byType(BookSpread), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
      expect(view, 1);
      expect(find.text('page 1').hitTestable(), findsOneWidget);
      expect(find.text('page 0').hitTestable(), findsNothing);
    });

    test('the leaf lifts from the free edge, arches, and lands flat', () {
      const page = Size(300, 500);
      double edge(double t, {bool projected = false}) => PageCurlPainter.edgeAt(
          t: t, page: page, spine: 300, cameraX: 300, projected: projected);
      // Untouched it lies flat on the right; turned, flat on the left.
      expect(edge(0, projected: true), closeTo(600, 1));
      expect(edge(1, projected: true), closeTo(0, 1));
      // Mid-turn it stands up off the book: nearer the reader, so larger.
      expect(edge(0.3, projected: true), greaterThan(edge(0.3)));
      // The edge moves steadily across: the finger can always find it.
      for (var t = 0.0; t < 1; t += 0.05) {
        expect(edge(t + 0.05), lessThan(edge(t)));
      }
      // The free edge leads: early on it has lifted while the spine side
      // still lies flat.
      expect(PageCurlPainter.angleAt(0.15, 1), greaterThan(0.6));
      expect(PageCurlPainter.angleAt(0.15, 0), lessThan(0.05));
    });

    test('painting a turn mid-way does not throw', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final t in [0.01, 0.3, 0.5, 0.8, 0.99]) {
        PageCurlPainter(
          t: t,
          grab: 0.9,
          spine: 150,
          cameraX: 150,
          page: const Size(150, 400),
          front: null,
          back: null,
          paper: Colors.white,
        ).paint(canvas, const Size(300, 400));
      }
      recorder.endRecording().dispose();
    });
  });

  group('the cover', () {
    testWidgets('a tap swings it open', (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BibleCover(
            ownerName: 'The Tejadas',
            onOpened: () => opened++,
            onEditName: () {},
          ),
        ),
      ));
      expect(find.text('The Tejadas'), findsOneWidget);
      await tester.tap(find.text('HOLY'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('an unnamed Bible invites a name', (tester) async {
      var asked = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BibleCover(
            ownerName: '',
            onOpened: () {},
            onEditName: () => asked++,
          ),
        ),
      ));
      await tester.tap(find.text('Add your name'));
      expect(asked, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
