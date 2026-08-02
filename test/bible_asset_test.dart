import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/config/bible_books.dart';
import 'package:exodus/models/bible_ref.dart';
import 'package:exodus/services/bible_service.dart';

/// Exercises the real bundled translation. The critical invariant is that
/// [BibleBooks.names] is in the same order as the asset — a reference resolves
/// by index, so a mismatch would silently send every deep link to the wrong
/// book.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bible = BibleService.instance;

  setUpAll(() async => bible.load());

  test('loads all 66 books', () {
    expect(bible.books.length, 66);
    expect(bible.isLoaded, isTrue);
  });

  test('asset book order matches the canon list used for references', () {
    for (var i = 0; i < 66; i++) {
      expect(bible.books[i].name, BibleBooks.names[i],
          reason: 'book $i is out of order — deep links would misresolve');
    }
  });

  test('known chapter counts', () {
    expect(bible.books[0].chapterCount, 50); // Genesis
    expect(bible.books[18].chapterCount, 150); // Psalms
    expect(bible.books[65].chapterCount, 22); // Revelation
  });

  test('resolves a reference to the right text', () {
    final ref = bible.parse('John 3:16')!;
    expect(bible.textFor(ref), contains('For God so loved the world'));
  });

  test('resolves a multi-verse range to all of its verses', () {
    final ref = bible.parse('1 Corinthians 13:4-7')!;
    final verses = bible.versesFor(ref);
    expect(verses.length, 4);
    expect(verses.first, contains('Charity suffereth long'));
  });

  test('a whole-chapter reference returns the whole chapter', () {
    final ref = bible.parse('Psalm 23')!;
    expect(bible.versesFor(ref).length, 6);
  });

  test('label round-trips through the service', () {
    expect(bible.label(bible.parse('Ephesians 5:25')!), 'Ephesians 5:25');
  });

  group('resolve clamps invented references', () {
    test('a chapter past the end clamps to the last chapter', () {
      final resolved =
          bible.resolve(const BibleRef(bookIndex: 64, chapter: 99))!; // Jude
      expect(resolved.chapter, 1);
    });

    test('a verse past the end clamps to the last verse', () {
      // Psalm 23 has 6 verses; a model citing v40 should land on v6.
      final resolved = bible.resolve(
          const BibleRef(bookIndex: 18, chapter: 23, verseStart: 40))!;
      expect(resolved.verseStart, 6);
    });

    test('an out-of-range book is rejected rather than clamped', () {
      expect(bible.resolve(const BibleRef(bookIndex: 99, chapter: 1)), isNull);
    });
  });

  test('translator-supplied words keep their braces stripped', () {
    // The source text marks these with {}; the asset build removes the braces
    // but keeps the words.
    final ref = bible.parse('Genesis 1:2')!;
    final text = bible.textFor(ref);
    expect(text, isNot(contains('{')));
    expect(text, isNot(contains('}')));
    expect(text, contains('without form'));
  });

  test('literal search finds exact wording', () {
    final hits = bible.searchText('a threefold cord', limit: 5);
    expect(hits, isNotEmpty);
    expect(bible.label(hits.first), 'Ecclesiastes 4:12');
  });
}
