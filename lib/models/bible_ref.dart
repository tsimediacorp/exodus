/// A scripture reference: a book, a chapter, and optionally a verse range.
///
/// [bookIndex] is the 0-based position in canon order, which is also the index
/// into the bundled translation — so a ref resolves to text without a lookup
/// table.
class BibleRef {
  final int bookIndex;
  final int chapter; // 1-based

  /// 1-based inclusive verse range. Null means the whole chapter.
  final int? verseStart;
  final int? verseEnd;

  const BibleRef({
    required this.bookIndex,
    required this.chapter,
    this.verseStart,
    this.verseEnd,
  });

  bool get hasVerses => verseStart != null;

  /// Whether [verse] (1-based) falls inside this reference's range.
  bool covers(int verse) {
    if (verseStart == null) return false;
    return verse >= verseStart! && verse <= (verseEnd ?? verseStart!);
  }

  BibleRef withChapter(int c) => BibleRef(bookIndex: bookIndex, chapter: c);

  String label(String bookName) {
    if (verseStart == null) return '$bookName $chapter';
    if (verseEnd == null || verseEnd == verseStart) {
      return '$bookName $chapter:$verseStart';
    }
    return '$bookName $chapter:$verseStart-$verseEnd';
  }

  @override
  bool operator ==(Object other) =>
      other is BibleRef &&
      other.bookIndex == bookIndex &&
      other.chapter == chapter &&
      other.verseStart == verseStart &&
      other.verseEnd == verseEnd;

  @override
  int get hashCode => Object.hash(bookIndex, chapter, verseStart, verseEnd);
}
