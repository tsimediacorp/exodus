import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/bible_paginator.dart';

/// The invariant that matters: every verse in the chapter lands on exactly one
/// page, in order, with none dropped and none duplicated. A stranded verse is
/// invisible to the reader and impossible to select.
void main() {
  const textStyle = TextStyle(fontSize: 16, height: 1.7);
  const numberStyle = TextStyle(fontSize: 11, height: 1.7);

  List<BiblePage> run(List<String> verses, Size size,
          {TextScaler scaler = TextScaler.noScaling}) =>
      BiblePaginator.paginate(
        verses: verses,
        size: size,
        verseTextStyle: textStyle,
        verseNumberStyle: numberStyle,
        verseSpacing: 16,
        textScaler: scaler,
      );

  void expectFullCoverage(List<BiblePage> pages, int verseCount) {
    expect(pages, isNotEmpty);
    expect(pages.first.firstVerse, 1, reason: 'must start at verse 1');
    expect(pages.last.lastVerse, verseCount, reason: 'must end at the last verse');
    for (var i = 0; i < pages.length; i++) {
      expect(pages[i].firstVerse, lessThanOrEqualTo(pages[i].lastVerse),
          reason: 'page $i is inverted');
      if (i > 0) {
        expect(pages[i].firstVerse, pages[i - 1].lastVerse + 1,
            reason: 'gap or overlap between pages ${i - 1} and $i');
      }
    }
  }

  List<String> versesOf(int n, {int words = 25}) =>
      List.generate(n, (i) => List.filled(words, 'word').join(' '));

  group('coverage', () {
    test('a short chapter fits one page', () {
      final pages = run(versesOf(3), const Size(340, 700));
      expect(pages.length, 1);
      expectFullCoverage(pages, 3);
    });

    test('a long chapter splits across pages with no verse lost', () {
      final verses = versesOf(120);
      final pages = run(verses, const Size(340, 700));
      expect(pages.length, greaterThan(1));
      expectFullCoverage(pages, verses.length);
    });

    test('Psalm-119-scale chapter stays covered', () {
      final verses = versesOf(176);
      final pages = run(verses, const Size(340, 700));
      expectFullCoverage(pages, verses.length);
    });

    test('a single verse chapter works', () {
      expectFullCoverage(run(versesOf(1), const Size(340, 700)), 1);
    });
  });

  group('degenerate viewports', () {
    test('a verse taller than the page gets its own page rather than looping', () {
      // A very long verse against a very short viewport: the paginator must
      // terminate and still cover everything.
      final verses = versesOf(4, words: 400);
      final pages = run(verses, const Size(300, 120));
      expectFullCoverage(pages, verses.length);
      expect(pages.length, greaterThanOrEqualTo(4));
    });

    test('an empty chapter still yields a page', () {
      expect(run(const [], const Size(340, 700)), isNotEmpty);
    });
  });

  group('text scale', () {
    test('larger text produces at least as many pages', () {
      final verses = versesOf(60);
      final normal = run(verses, const Size(340, 700));
      final large = run(verses, const Size(340, 700),
          scaler: const TextScaler.linear(1.8));
      expect(large.length, greaterThanOrEqualTo(normal.length));
      expectFullCoverage(large, verses.length);
    });

    test('a taller viewport produces no more pages than a short one', () {
      final verses = versesOf(60);
      final short = run(verses, const Size(340, 400));
      final tall = run(verses, const Size(340, 900));
      expect(tall.length, lessThanOrEqualTo(short.length));
    });
  });

  group('pageIndexOf', () {
    test('finds the page holding a verse', () {
      final verses = versesOf(120);
      final pages = run(verses, const Size(340, 700));
      for (final probe in [1, 40, 80, 120]) {
        final i = BiblePaginator.pageIndexOf(pages, probe);
        expect(pages[i].contains(probe), isTrue,
            reason: 'verse $probe should be on page $i');
      }
    });

    test('falls back to the first page for a verse out of range', () {
      final pages = run(versesOf(10), const Size(340, 700));
      expect(BiblePaginator.pageIndexOf(pages, 999), 0);
    });
  });
}
