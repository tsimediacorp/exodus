import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/bible_books.dart';
import '../models/bible_ref.dart';

/// One book of the bundled translation.
class BibleBook {
  final String name;
  final List<List<String>> chapters;
  const BibleBook({required this.name, required this.chapters});

  int get chapterCount => chapters.length;
  List<String> verses(int chapter) =>
      (chapter >= 1 && chapter <= chapters.length)
          ? chapters[chapter - 1]
          : const [];
}

/// The in-app Bible. Loads the bundled translation once, lazily, and answers
/// lookups against it.
///
/// The text is ~4.5MB of JSON, so the parse runs off the UI isolate and the
/// result is cached for the process lifetime — the reader shows a spinner on
/// first open only.
class BibleService {
  BibleService._();
  static final BibleService instance = BibleService._();

  /// The translation shipped in the bundle. Swapping or adding one is an
  /// asset change plus this constant — nothing else knows the translation.
  static const String translation = 'KJV';
  static const String _assetPath = 'assets/bible/kjv.json';

  List<BibleBook>? _books;
  Future<List<BibleBook>>? _loading;

  bool get isLoaded => _books != null;

  /// Books in canon order. Await [load] first, or use [books] after [isLoaded].
  List<BibleBook> get books => _books ?? const [];

  Future<List<BibleBook>> load() {
    final cached = _books;
    if (cached != null) return Future.value(cached);
    // Share one in-flight load between concurrent callers rather than
    // parsing 4.5MB twice.
    return _loading ??= _doLoad();
  }

  Future<List<BibleBook>> _doLoad() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final parsed = await compute(_parse, raw);
      _books = parsed;
      return parsed;
    } finally {
      _loading = null;
    }
  }

  /// Runs in a background isolate — must be a top-level/static function.
  static List<BibleBook> _parse(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return BibleBook(
        name: m['n'] as String,
        chapters: (m['c'] as List<dynamic>)
            .map((c) => (c as List<dynamic>).map((v) => v as String).toList())
            .toList(),
      );
    }).toList();
  }

  String bookName(int index) =>
      (index >= 0 && index < BibleBooks.names.length)
          ? BibleBooks.names[index]
          : '';

  /// Human label for a reference, e.g. "Ephesians 5:25-27".
  String label(BibleRef ref) => ref.label(bookName(ref.bookIndex));

  /// The verses a reference points at, as "1 In the beginning…" lines.
  /// Empty when the reference is out of range or the text isn't loaded.
  List<String> versesFor(BibleRef ref) {
    if (!isLoaded) return const [];
    if (ref.bookIndex < 0 || ref.bookIndex >= books.length) return const [];
    final all = books[ref.bookIndex].verses(ref.chapter);
    if (all.isEmpty) return const [];
    if (!ref.hasVerses) return all;
    final start = ref.verseStart!.clamp(1, all.length);
    final end = (ref.verseEnd ?? start).clamp(start, all.length);
    return all.sublist(start - 1, end);
  }

  /// The plain text of a reference, verses joined — for quoting into a prompt.
  String textFor(BibleRef ref) => versesFor(ref).join(' ').trim();

  /// Clamp a reference to something that actually exists, so a model that
  /// invents "Psalm 151:9" lands on the nearest real passage instead of a
  /// blank screen.
  BibleRef? resolve(BibleRef ref) {
    if (!isLoaded) return ref;
    if (ref.bookIndex < 0 || ref.bookIndex >= books.length) return null;
    final book = books[ref.bookIndex];
    if (book.chapterCount == 0) return null;
    final chapter = ref.chapter.clamp(1, book.chapterCount);
    final verseCount = book.verses(chapter).length;
    if (verseCount == 0) return null;
    if (!ref.hasVerses) {
      return BibleRef(bookIndex: ref.bookIndex, chapter: chapter);
    }
    final start = ref.verseStart!.clamp(1, verseCount);
    final end = (ref.verseEnd ?? start).clamp(start, verseCount);
    return BibleRef(
      bookIndex: ref.bookIndex,
      chapter: chapter,
      verseStart: start,
      verseEnd: end == start ? null : end,
    );
  }

  // ---------------- Reference parsing ----------------

  /// Matches "Ephesians 5:25", "1 Cor 13:4-7", "Ps 23", "John 3 : 16".
  ///
  /// The book group covers the three shapes a book name takes: a bare word,
  /// an ordinal plus a word ("1 Corinthians"), and "X of Y" ("Song of
  /// Solomon"). It deliberately does NOT try to skip the prose in front of a
  /// reference — see [_scan], which walks candidate positions instead.
  static final RegExp _refPattern = RegExp(
    r'((?:[123]\s*)?[A-Za-z]+(?:\s+of\s+[A-Za-z]+)?)\.?\s*'
    r'(\d{1,3})\s*(?::\s*(\d{1,3})\s*(?:[-–—]\s*(\d{1,3}))?)?',
  );

  /// Walk [text] yielding every reference whose book actually resolves.
  ///
  /// On a match whose book is not a real book, this advances by ONE character
  /// rather than past the whole match. That matters: in "…says in 1
  /// Corinthians 13:4-7" the pattern first matches "in 1" (book "in",
  /// chapter 1). Skipping the whole match would step over the "1" and leave a
  /// bare "Corinthians", which is unresolvable on its own. Advancing by one
  /// lets the scan re-enter at "1 Corinthians 13:4-7" and read it correctly.
  Iterable<BibleRef> _scan(String text) sync* {
    var offset = 0;
    while (offset < text.length) {
      final match = _refPattern.firstMatch(text.substring(offset));
      if (match == null) return;
      final ref = _fromMatch(match);
      if (ref != null) {
        yield ref;
        offset += match.end;
      } else {
        offset += match.start + 1;
      }
    }
  }

  /// Parse a single reference string, e.g. a devotional's `scriptureRef`.
  BibleRef? parse(String input) {
    for (final ref in _scan(input.trim())) {
      return ref;
    }
    return null;
  }

  /// Find every reference mentioned in a block of prose — used to make the
  /// scripture EXODUS cites in a reply tappable.
  List<BibleRef> findAll(String text) {
    final found = <BibleRef>[];
    final seen = <BibleRef>{};
    for (final ref in _scan(text)) {
      if (seen.add(ref)) found.add(ref);
    }
    return found;
  }

  /// Resolve a captured book phrase, dropping leading words until something
  /// matches — "look at Ephesians" → "at Ephesians" → "Ephesians". Longest
  /// first, so "Song of Solomon" wins over a bare "Solomon" and
  /// "1 Corinthians" is never reduced to an unresolvable "Corinthians".
  static int? _resolveBook(String phrase) {
    final words = phrase.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    for (var start = 0; start < words.length; start++) {
      final index = BibleBooks.indexOf(words.sublist(start).join(' '));
      if (index != null) return index;
    }
    return null;
  }

  BibleRef? _fromMatch(RegExpMatch m) {
    final bookIndex = _resolveBook(m.group(1) ?? '');
    if (bookIndex == null) return null;
    final chapter = int.tryParse(m.group(2) ?? '');
    if (chapter == null || chapter < 1) return null;
    final start = int.tryParse(m.group(3) ?? '');
    final end = int.tryParse(m.group(4) ?? '');
    return BibleRef(
      bookIndex: bookIndex,
      chapter: chapter,
      verseStart: start,
      verseEnd: end,
    );
  }

  // ---------------- Plain-text search ----------------

  /// Literal substring search across the whole translation. Complements the
  /// AI search: this finds exact wording, that one finds meaning.
  List<BibleRef> searchText(String query, {int limit = 100}) {
    if (!isLoaded) return const [];
    final needle = query.trim().toLowerCase();
    if (needle.length < 3) return const [];
    final hits = <BibleRef>[];
    for (var b = 0; b < books.length; b++) {
      final chapters = books[b].chapters;
      for (var c = 0; c < chapters.length; c++) {
        final verses = chapters[c];
        for (var v = 0; v < verses.length; v++) {
          if (verses[v].toLowerCase().contains(needle)) {
            hits.add(BibleRef(
                bookIndex: b, chapter: c + 1, verseStart: v + 1));
            if (hits.length >= limit) return hits;
          }
        }
      }
    }
    return hits;
  }
}
