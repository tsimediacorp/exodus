import 'package:flutter/material.dart';

/// A run of verses that fits on one page.
@immutable
class BiblePage {
  /// 1-based, inclusive.
  final int firstVerse;
  final int lastVerse;

  const BiblePage({required this.firstVerse, required this.lastVerse});

  bool contains(int verse) => verse >= firstVerse && verse <= lastVerse;
  int get verseCount => lastVerse - firstVerse + 1;
}

/// Breaks a chapter into pages that fit the reader's viewport.
///
/// Pages break on VERSE boundaries rather than mid-sentence. True text-flow
/// pagination would pack slightly tighter, but every verse has to stay an
/// individually tappable target for select-to-explain — splitting a verse
/// across two pages would break that, and a half-verse you can't select is a
/// worse trade than a little whitespace at the foot of a page.
class BiblePaginator {
  /// Measure [verses] (1-based content) against [size] and return the pages.
  ///
  /// [verseNumberStyle] and [verseTextStyle] must match what the reader
  /// actually renders, or the measurement is fiction.
  static List<BiblePage> paginate({
    required List<String> verses,
    required Size size,
    required TextStyle verseTextStyle,
    required TextStyle verseNumberStyle,
    required double verseSpacing,
    required TextScaler textScaler,
  }) {
    if (verses.isEmpty) {
      return const [BiblePage(firstVerse: 1, lastVerse: 1)];
    }

    final pages = <BiblePage>[];
    var pageStart = 1;
    var used = 0.0;

    for (var i = 0; i < verses.length; i++) {
      final height = _measure(
        number: i + 1,
        text: verses[i],
        maxWidth: size.width,
        textStyle: verseTextStyle,
        numberStyle: verseNumberStyle,
        textScaler: textScaler,
      );
      final needed = height + verseSpacing;

      // A verse taller than a whole page (Psalm 119 at large text scale, say)
      // still has to live somewhere: give it its own page rather than loop.
      if (needed > size.height && used == 0) {
        pages.add(BiblePage(firstVerse: pageStart, lastVerse: i + 1));
        pageStart = i + 2;
        used = 0;
        continue;
      }

      if (used + needed > size.height && used > 0) {
        pages.add(BiblePage(firstVerse: pageStart, lastVerse: i));
        pageStart = i + 1;
        used = needed;
      } else {
        used += needed;
      }
    }

    if (pageStart <= verses.length) {
      pages.add(BiblePage(firstVerse: pageStart, lastVerse: verses.length));
    }
    return pages.isEmpty
        ? [BiblePage(firstVerse: 1, lastVerse: verses.length)]
        : pages;
  }

  /// Height of one rendered verse row at [maxWidth].
  static double _measure({
    required int number,
    required String text,
    required double maxWidth,
    required TextStyle textStyle,
    required TextStyle numberStyle,
    required TextScaler textScaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: '$number ', style: numberStyle),
        TextSpan(text: text, style: textStyle),
      ]),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  /// Index of the page holding [verse], or 0 if it isn't found — used to jump
  /// straight to a deep-linked passage.
  static int pageIndexOf(List<BiblePage> pages, int verse) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].contains(verse)) return i;
    }
    return 0;
  }
}
