import 'package:exodus/models/bible_ref.dart';
import 'package:exodus/widgets/stone_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BibleRef?> Function() open(WidgetTester tester, Size size) {
    BibleRef? result;
    var done = false;
    return () async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await StonePicker.show(
                    context,
                    StonePicker(
                      currentBook: 1,
                      currentChapter: 14,
                      chapterCount: (b) => b == 1 ? 40 : (b == 5 ? 24 : 10),
                      titleOf: (b, c) => 'Through the Sea',
                      illustrated: (b, c) => c == 14,
                    ),
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      return result;
    };
  }

  testWidgets('unfolded: two tablets; a book then a chapter is chosen',
      (tester) async {
    await open(tester, const Size(951, 669))();
    expect(find.text('THE BOOKS'), findsOneWidget);
    expect(find.text('Through the Sea'), findsOneWidget);
    expect(find.bySemanticsLabel('Chapter 14, illustrated'), findsOneWidget);
    await tester.tap(find.text('JOSHUA'));
    await tester.pumpAndSettle();
    expect(find.text('24'), findsWidgets);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('THE BOOKS'), findsNothing);
  });

  testWidgets('folded: one tablet turns between chapters and books',
      (tester) async {
    await open(tester, const Size(466, 820))();
    expect(find.text('THE BOOKS'), findsNothing);
    expect(find.text('CHAPTERS'), findsOneWidget);
    await tester.tap(find.text('BOOKS'));
    await tester.pumpAndSettle();
    expect(find.text('GENESIS'), findsOneWidget);
    await tester.tap(find.text('NEW'));
    await tester.pumpAndSettle();
    expect(find.text('MATTHEW'), findsOneWidget);
    await tester.tap(find.text('MATTHEW'));
    await tester.pumpAndSettle();
    // Choosing a book turns the tablet back to its chapters.
    expect(find.text('10 chapters'), findsOneWidget);
  });

  test('every book has a part of the Bible', () {
    for (var b = 0; b < 66; b++) {
      expect(stoneSectionOf(b), isNotEmpty);
    }
    expect(stoneSectionOf(0), 'The Law');
    expect(stoneSectionOf(39), 'The Gospels');
    expect(stoneSectionOf(65), 'Prophecy');
  });
}
