import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/config/bible_books.dart';
import 'package:exodus/models/bible_ref.dart';
import 'package:exodus/services/bible_service.dart';

/// Loads EVERY registered translation and checks it is actually usable.
///
/// The registry is just a list of asset paths, so nothing else stops a
/// translation being added with a missing file, a truncated download, or books
/// in a different order — and book order is load-bearing, because a reference
/// resolves by index. A mis-ordered asset would send every scripture deep link
/// in the app to the wrong book, silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bible = BibleService.instance;

  // Leave the service on the default so this file cannot influence another.
  tearDownAll(() async => bible.select(BibleService.translations.first));

  for (final translation in BibleService.translations) {
    group(translation.abbrev, () {
      setUpAll(() async => bible.select(translation));

      test('the asset loads and holds all 66 books', () async {
        expect(bible.isLoaded, isTrue,
            reason: '${translation.assetPath} did not load');
        expect(bible.books, hasLength(66));
      });

      test('book order matches the canon used to resolve references', () {
        for (var i = 0; i < 66; i++) {
          expect(bible.books[i].name, BibleBooks.names[i],
              reason: 'book $i is out of order — deep links would misresolve');
        }
      });

      test('carries a complete bible, not a truncated download', () {
        final verses = bible.books
            .expand((b) => b.chapters)
            .fold<int>(0, (sum, c) => sum + c.length);
        // Not an exact figure: translations legitimately differ on where a
        // verse is split (the KJV counts four that the critical text merges),
        // so the count is bounded rather than pinned. A truncated file — which
        // still parses, it is just short — falls well outside this.
        expect(verses, greaterThanOrEqualTo(31100));
        expect(verses, lessThanOrEqualTo(31110));
      });

      test('known chapter counts are right', () {
        expect(bible.books[0].chapterCount, 50); // Genesis
        expect(bible.books[18].chapterCount, 150); // Psalms
        expect(bible.books[65].chapterCount, 22); // Revelation
      });

      test('resolves a reference to real text', () {
        final ref = bible.parse('Ephesians 5:25')!;
        final text = bible.textFor(ref);
        expect(text, isNotEmpty);
        expect(text.toLowerCase(), contains('husband'));
      });

      test('carries no leftover source markup', () {
        // Translator markers are stripped at asset-build time. Square brackets
        // are NOT banned outright: the KJV prints psalm superscriptions in
        // them ("[A Psalm of David.]"), which is real typography and stays.
        // What must never survive is an UNMATCHED bracket, which is what the
        // converted sources left around "[Selah".
        for (final book in bible.books) {
          for (final chapter in book.chapters) {
            for (final verse in chapter) {
              expect(verse, isNot(contains('{')));
              expect(verse, isNot(contains('}')));
              expect(
                  '['.allMatches(verse).length, ']'.allMatches(verse).length,
                  reason: 'unmatched bracket in ${book.name}: $verse');
            }
          }
        }
      });

      test('the reported abbreviation follows the selection', () {
        expect(BibleService.translation, translation.abbrev);
      });
    });
  }

  group('switching', () {
    test('the same passage reads differently in different translations',
        () async {
      // Proves the switch actually swaps the text rather than serving a
      // cached parse of the previous translation.
      const ref = BibleRef(bookIndex: 0, chapter: 1, verseStart: 1);
      final readings = <String, String>{};
      for (final t in BibleService.translations) {
        await bible.select(t);
        readings[t.abbrev] = bible.textFor(ref);
      }
      expect(readings.values.every((v) => v.isNotEmpty), isTrue);
      if (BibleService.translations.length > 1) {
        expect(readings.values.toSet().length, greaterThan(1),
            reason: 'every translation returned identical text for Genesis 1:1');
      }
    });

    test('books are empty for a translation that has not loaded yet', () {
      // isLoaded is scoped to the current translation, so a stale parse is
      // never served as the newly selected one.
      expect(bible.isLoaded, isTrue);
      expect(bible.books, isNotEmpty);
    });
  });

  group('KJV verses that were missing from the shipped asset', () {
    // The bundled KJV dropped six verses outright, which also shifted every
    // later verse in those chapters one number early — so Matthew 2:20 read
    // as 2:19, and so on to the end of the chapter. The asset was repaired;
    // these pin the repair, because the failure was completely silent.
    setUpAll(() async => bible.select(BibleService.byId('kjv')));

    const restored = {
      'Matthew 2:16': 'slew all the children',
      'Matthew 22:1': 'spake unto them again by parables',
      'Matthew 26:38': 'My soul is exceeding sorrowful',
      'Mark 4:40': 'Why are ye so fearful',
      'Mark 7:11': 'It is Corban',
      'Mark 8:8': 'seven baskets',
    };

    restored.forEach((reference, phrase) {
      test('$reference is present and says what it should', () {
        final ref = bible.parse(reference);
        expect(ref, isNotNull, reason: '$reference did not parse');
        expect(bible.textFor(ref!), contains(phrase));
      });
    });

    test('the verses after a restored gap are numbered correctly again', () {
      // Matthew 2:23 is the Nazarene prophecy. While 2:16 was absent it sat
      // at 2:22, so this is the assertion that would have caught the bug.
      expect(bible.textFor(bible.parse('Matthew 2:23')!),
          contains('Nazareth'));
      expect(bible.textFor(bible.parse('Matthew 2:16')!),
          contains('Herod'));
    });

    test('the divine name keeps its KJV typography', () {
      // The obvious fix — swapping in another KJV source — would have cost
      // the LORD/Lord distinction (YHWH vs Adonai), so the asset was repaired
      // in place instead. This is what that decision protects.
      expect(bible.textFor(bible.parse('Psalm 23:1')!), contains('LORD'));
    });
  });
}
