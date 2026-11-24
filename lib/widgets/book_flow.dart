import 'dart:math' as math;

import '../services/bible_art.dart';
import '../services/bible_typesetter.dart';

/// A leaf of the open book: a page of text, a plate, or the colophon.
sealed class BookLeaf {
  const BookLeaf();
}

/// Part of one chapter's text on a page: band [slice] of its setting, with
/// the chapter's heading above it when [slice] is its opening.
class PageRun {
  final int chapter;
  final int slice;

  /// Space above the heading when the chapter opens part way down a page.
  final double gap;
  const PageRun(this.chapter, this.slice, this.gap);

  bool get opens => slice == 0;
}

/// A page of text. Usually one run; where a chapter ends part way down, the
/// next chapter's heading and opening lines follow on the same page.
class TextLeaf extends BookLeaf {
  final List<PageRun> runs;
  const TextLeaf(this.runs);
}

/// A full page of art.
class PlateLeaf extends BookLeaf {
  final BiblePlate plate;
  const PlateLeaf(this.plate);
}

/// The colophon after the book's last page.
class ColophonLeaf extends BookLeaf {
  const ColophonLeaf();
}

/// One chapter as set for the open book.
class SetChapter {
  final TypesetChapter set;
  final HeadingSpec heading;

  /// Leaves where the chapter opens and where its last line falls; -1 until
  /// that page has been closed.
  int openingLeaf = -1;
  int lastLeaf = -1;

  SetChapter(this.set, this.heading);
}

/// A book set in type as a printed Bible sets it: the chapters run on, one
/// after another, each opening below the last line of the one before when
/// there is room for its heading and a few lines, and on a fresh page when
/// there is not. Plates stand after the page their verse falls on.
///
/// The flow always starts at chapter one, so a given chapter lands on the
/// same page however the reader arrived at it. Chapters are set on demand
/// ([ensure]) a little ahead of the reader, since setting all 150 Psalms at
/// once would cost a visible pause.
class BookFlow {
  final int book;
  final int chapterCount;
  final int per;
  final double width;
  final double content;
  final BibleType type;
  final List<String> Function(int chapter) versesOf;
  final List<BiblePlate> Function(int chapter) platesOf;
  final HeadingSpec Function(int chapter, List<BiblePlate> plates, bool compact)
      headingOf;
  final String omittedLabel;

  BookFlow({
    required this.book,
    required this.chapterCount,
    required this.per,
    required this.width,
    required this.content,
    required this.type,
    required this.versesOf,
    required this.platesOf,
    required this.headingOf,
    required this.omittedLabel,
  });

  final List<SetChapter> chapters = [];
  final List<BookLeaf> leaves = [];

  // The page being filled, not yet among [leaves].
  final List<PageRun> _page = [];
  double _used = 0;
  final List<BookLeaf> _afterPage = [];

  bool get complete => chapters.length == chapterCount;

  SetChapter? operator [](int chapter) =>
      chapter >= 1 && chapter <= chapters.length ? chapters[chapter - 1] : null;

  /// Set chapters until [chapter] and the one after it are on closed pages,
  /// with a page to spare for the facing side.
  bool ensure(int chapter) {
    var grew = false;
    bool enough() {
      if (complete) return true;
      final next = this[math.min(chapter + 1, chapterCount)];
      return next != null &&
          next.lastLeaf >= 0 &&
          leaves.length > next.lastLeaf + 2;
    }

    while (!enough()) {
      _setNext();
      grew = true;
    }
    return grew;
  }

  void _close() {
    if (_page.isEmpty) return;
    final at = leaves.length;
    for (final r in _page) {
      final c = chapters[r.chapter - 1];
      if (r.opens) c.openingLeaf = at;
      if (r.slice == c.set.slices.length - 1) c.lastLeaf = at;
    }
    leaves.add(TextLeaf(List.of(_page)));
    leaves.addAll(_afterPage);
    _page.clear();
    _afterPage.clear();
    _used = 0;
  }

  void _setNext() {
    final n = chapters.length + 1;
    final plates = platesOf(n);
    var heading = headingOf(n, plates, false);

    // Room for the heading, the drop cap and two lines under it, or the
    // chapter waits for the next page rather than opening on a scrap. Short
    // of room for its art, it opens with its title alone.
    var gap = _used > 0 ? type.linePx * 1.4 : 0.0;
    final opening = type.linePx * (type.capLines + 2);
    var compact = false;
    if (_used > 0 && content - _used - gap - heading.height < opening) {
      final small = headingOf(n, plates, true);
      if (content - _used - gap - small.height >= opening) {
        heading = small;
        compact = true;
      } else {
        _close();
        gap = 0;
      }
    }
    final set = TypesetChapter.layout(
      verses: versesOf(n),
      width: width,
      type: type,
      openingHeight: content - _used - gap - heading.height,
      pageHeight: content,
      omittedLabel: omittedLabel,
    );
    final chapter = SetChapter(set, heading);
    chapters.add(chapter);

    // Folded, the first plate heads the chapter; every other plate has a
    // page of its own after the page its verse is on.
    final standing = per == 1 && !compact ? plates.skip(1) : plates;
    final bySlice = <int, List<BiblePlate>>{};
    for (final p in standing) {
      bySlice.putIfAbsent(set.sliceOfVerse(p.verse), () => []).add(p);
    }

    for (var i = 0; i < set.slices.length; i++) {
      if (i > 0) _close();
      _page.add(PageRun(n, i, i == 0 ? gap : 0));
      final slice = set.slices[i];
      _used = i == 0
          ? _used +
              gap +
              heading.height +
              (set.lead == null ? 0 : set.leadHeight) +
              slice.height
          : slice.height;
      for (final p in bySlice[i] ?? const <BiblePlate>[]) {
        _afterPage.add(PlateLeaf(p));
      }
    }

    if (complete) {
      _close();
      leaves.add(const ColophonLeaf());
    }
  }

  /// The leaf on which verse [verse] of [chapter] begins.
  int leafOf(int chapter, int verse) {
    ensure(chapter);
    final c = this[chapter];
    if (c == null) return 0;
    final slice = c.set.sliceOfVerse(verse);
    for (var i = math.max(0, c.openingLeaf); i < leaves.length; i++) {
      final l = leaves[i];
      if (l is TextLeaf &&
          l.runs.any((r) => r.chapter == chapter && r.slice == slice)) {
        return i;
      }
    }
    return math.max(0, c.openingLeaf);
  }

  void dispose() {
    for (final c in chapters) {
      c.set.dispose();
    }
  }
}

/// The heading over a chapter's first page, as measured.
class HeadingSpec {
  final String kicker;
  final String title;
  final String? vignette;
  final String? headpiece;
  final double headpieceHeight;
  final double titleSize;
  final double height;

  const HeadingSpec({
    required this.kicker,
    required this.title,
    required this.vignette,
    required this.headpiece,
    required this.headpieceHeight,
    required this.titleSize,
    required this.height,
  });
}
