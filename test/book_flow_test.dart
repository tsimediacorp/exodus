import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/bible_art.dart';
import 'package:exodus/services/bible_typesetter.dart';
import 'package:exodus/widgets/book_flow.dart';

/// A book of [lengths.length] chapters, chapter n having lengths[n-1] verses.
BookFlow _book(
  List<int> lengths, {
  int per = 2,
  double content = 520,
  Map<int, List<int>> plateVerses = const {},
}) {
  HeadingSpec heading(int c, List<BiblePlate> plates, bool compact) =>
      HeadingSpec(
        kicker: 'Book',
        title: 'Chapter $c',
        vignette: compact ? null : 'v',
        headpiece: null,
        headpieceHeight: 0,
        titleSize: 32,
        height: compact ? 70 : 170,
      );
  var number = 0;
  final plates = {
    for (final e in plateVerses.entries)
      e.key: [
        for (final v in e.value)
          BiblePlate(
            id: 'p${e.key}-$v',
            book: 0,
            chapter: e.key,
            verse: v,
            title: 'Plate',
            isMap: false,
            number: ++number,
          ),
      ],
  };
  return BookFlow(
    book: 0,
    chapterCount: lengths.length,
    per: per,
    width: 320,
    content: content,
    type: const BibleType(),
    versesOf: (c) => [
      for (var v = 1; v <= lengths[c - 1]; v++)
        'And it came to pass in the days of the judges, verse $v of '
            'chapter $c, that there was a famine in the land.',
    ],
    platesOf: (c) => plates[c] ?? const [],
    headingOf: heading,
    omittedLabel: 'Omitted.',
  );
}

Iterable<PageRun> _runs(BookFlow f) sync* {
  for (final l in f.leaves) {
    if (l is TextLeaf) yield* l.runs;
  }
}

void main() {
  test('every line of every chapter is printed once, in order', () {
    final f = _book([12, 3, 1, 25, 7, 40, 2]);
    f.ensure(7);
    expect(f.complete, isTrue);
    final runs = _runs(f).toList();
    var i = 0;
    for (var c = 1; c <= 7; c++) {
      final slices = f[c]!.set.slices.length;
      for (var s = 0; s < slices; s++) {
        expect((runs[i].chapter, runs[i].slice), (c, s));
        i++;
      }
    }
    expect(i, runs.length);
    f.dispose();
  });

  test('chapters run on: a short one shares its page with the next', () {
    final f = _book([1, 1, 1, 30], content: 900);
    f.ensure(4);
    final shared = f.leaves
        .whereType<TextLeaf>()
        .where((l) => l.runs.where((r) => r.opens).length >= 2);
    expect(shared, isNotEmpty);
    // A chapter opening part way down a page has space set above it.
    expect(_runs(f).where((r) => r.opens && r.gap > 0), isNotEmpty);
    f.dispose();
  });

  test('no page holds more than fits on it', () {
    final f = _book([9, 4, 33, 1, 1, 18, 6, 50]);
    f.ensure(8);
    for (final l in f.leaves.whereType<TextLeaf>()) {
      var used = 0.0;
      for (final r in l.runs) {
        final c = f[r.chapter]!;
        final slice = c.set.slices[r.slice];
        used += r.gap + slice.height;
        if (r.opens) {
          used += c.heading.height +
              (c.set.lead == null ? 0 : c.set.leadHeight);
        }
      }
      expect(used, lessThanOrEqualTo(f.content + 0.5));
    }
    f.dispose();
  });

  test('a chapter short of room for its art opens with its title alone', () {
    // Chapter one fills most of a page; chapter two's full heading does not
    // fit under it, but its title and first lines do.
    const type = BibleType();
    final f = _book([7, 20], content: 170 + type.linePx * 12);
    f.ensure(2);
    final two = f[2]!;
    final opening = _runs(f).firstWhere((r) => r.chapter == 2 && r.opens);
    if (opening.gap > 0) {
      expect(two.heading.vignette, isNull,
          reason: 'opened low on a page, so compact');
    }
    f.dispose();
  });

  test('it sets ahead of the reader, not the whole book at once', () {
    final f = _book(List.filled(60, 6));
    f.ensure(3);
    expect(f.complete, isFalse);
    expect(f.chapters.length, lessThan(15));
    f.dispose();
  });

  test('a chapter lands on the same page however the reader got there', () {
    final a = _book(List.filled(40, 9), plateVerses: const {5: [3], 20: [8]});
    final b = _book(List.filled(40, 9), plateVerses: const {5: [3], 20: [8]});
    a.ensure(40);
    final atA = a.leafOf(25, 4);
    final atB = b.leafOf(25, 4);
    expect(atB, atA);
    a.dispose();
    b.dispose();
  });

  test('plates stand after the page their verse is on', () {
    final f = _book([30, 30], plateVerses: const {1: [20]});
    f.ensure(2);
    final plateAt = f.leaves.indexWhere((l) => l is PlateLeaf);
    expect(plateAt, greaterThan(0));
    final before = f.leaves[plateAt - 1] as TextLeaf;
    final verseLeaf = f.leafOf(1, 20);
    expect(f.leaves.indexOf(before), verseLeaf);
    f.dispose();
  });

  test('folded, the first plate heads its chapter instead of standing', () {
    final f = _book([30], per: 1, plateVerses: const {1: [1, 20]});
    f.ensure(1);
    final standing = f.leaves.whereType<PlateLeaf>().toList();
    expect(standing.map((p) => p.plate.verse), [20]);
    f.dispose();
  });

  test('the book closes with a colophon', () {
    final f = _book([5, 5]);
    f.ensure(2);
    expect(f.leaves.last, isA<ColophonLeaf>());
    expect(f.leaves.whereType<ColophonLeaf>().length, 1);
    f.dispose();
  });
}
