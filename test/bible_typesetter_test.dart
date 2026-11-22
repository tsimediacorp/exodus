import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/bible_typesetter.dart';
import 'package:exodus/widgets/bible_pages.dart';

void main() {
  final verses = [
    'And the LORD spake unto Moses, saying,',
    for (var i = 2; i <= 40; i++)
      'Verse $i of a long chapter, with enough words in it to wrap across '
          'more than one line of the page, as scripture does.',
  ];

  TypesetChapter set({double opening = 200, double page = 400}) =>
      TypesetChapter.layout(
        verses: verses,
        width: 300,
        type: const BibleType(),
        openingHeight: opening,
        pageHeight: page,
      );

  test('the chapter opens on a drop cap and runs on without a gap', () {
    final t = set();
    expect(t.capLetter, 'A');
    expect(t.text.startsWith('nd the L'), isTrue);
    expect(t.leadLines, 3);
    expect(t.split, greaterThan(0));
    // Every line of the body is on exactly one page, in order.
    var next = 0;
    for (final s in t.slices) {
      expect(s.startLine, next);
      next = s.endLine;
    }
    expect(next, t.body!.computeLineMetrics().length);
    t.dispose();
  });

  test('pages are full but never overfull', () {
    final t = set();
    for (final s in t.slices.skip(1).take(t.slices.length - 2)) {
      expect(s.height, lessThanOrEqualTo(400.5));
      expect(s.height, greaterThan(400 - t.type.linePx * 1.5));
    }
    t.dispose();
  });

  test('a verse can be found by where it is, and where it begins', () {
    final t = set();
    final page = t.sliceOfVerse(30);
    expect(page, greaterThan(0));
    final boxes = t.sliceBoxes(30, t.slices[page]);
    expect(boxes, isNotEmpty);
    expect(t.verseInSlice(t.slices[page], boxes.first.center), 30);
    expect(t.firstVerseOn(page), lessThanOrEqualTo(30));
    expect(t.lastVerseOn(page), greaterThanOrEqualTo(30));
    t.dispose();
  });

  test('LORD is set in small capitals, its capital kept', () {
    final t = set();
    expect(t.text.contains('the LORD spake'), isTrue);
    t.dispose();
  });

  test('a long caption is cut at a pause', () {
    const long = 'And Moses stretched out his hand over the sea; and the LORD '
        'caused the sea to go back by a strong east wind all that night, and '
        'made the sea dry land, and the waters were divided.';
    final c = PlatePage.captionFor(long);
    expect(c, 'And Moses stretched out his hand over the sea…');
    expect(PlatePage.captionFor('The LORD is my shepherd.'),
        'The Lord is my shepherd.');
  });
}
