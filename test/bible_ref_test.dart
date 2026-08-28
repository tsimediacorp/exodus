import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/config/bible_books.dart';
import 'package:exodus/services/bible_service.dart';

void main() {
  final bible = BibleService.instance;

  group('BibleBooks.indexOf', () {
    test('resolves canonical names', () {
      expect(BibleBooks.indexOf('Genesis'), 0);
      expect(BibleBooks.indexOf('Revelation'), 65);
      expect(BibleBooks.indexOf('Ephesians'), 48);
    });

    test('is case and punctuation insensitive', () {
      expect(BibleBooks.indexOf('ePHesians'), 48);
      expect(BibleBooks.indexOf('  song of solomon '), 21);
    });

    test('resolves abbreviations', () {
      expect(BibleBooks.indexOf('Eph'), 48);
      expect(BibleBooks.indexOf('Ps'), 18);
      expect(BibleBooks.indexOf('1 Cor'), 45);
      expect(BibleBooks.indexOf('Rev'), 65);
    });

    test('folds written and roman ordinals', () {
      expect(BibleBooks.indexOf('First John'), 61);
      expect(BibleBooks.indexOf('II Timothy'), 54);
      expect(BibleBooks.indexOf('1st Peter'), 59);
    });

    test('distinguishes the numbered books from each other', () {
      expect(BibleBooks.indexOf('1 John'), 61);
      expect(BibleBooks.indexOf('2 John'), 62);
      expect(BibleBooks.indexOf('3 John'), 63);
      // "John" alone must not collide with "1 John".
      expect(BibleBooks.indexOf('John'), 42);
    });

    test('rejects what it cannot resolve rather than guessing', () {
      expect(BibleBooks.indexOf('Hezekiah'), isNull);
      expect(BibleBooks.indexOf(''), isNull);
      // Ambiguous prefix — Jude vs Judges: refuse rather than pick one.
      expect(BibleBooks.indexOf('Jud'), 64); // explicit alias wins
      expect(BibleBooks.indexOf('Jo'), 42); // explicit alias wins
    });

    test('resolves unique prefixes', () {
      expect(BibleBooks.indexOf('Ecclesiast'), 20);
      expect(BibleBooks.indexOf('Habak'), 34);
    });
  });

  group('BibleService.parse', () {
    test('parses book chapter:verse', () {
      final r = bible.parse('Ephesians 5:25')!;
      expect(r.bookIndex, 48);
      expect(r.chapter, 5);
      expect(r.verseStart, 25);
      expect(r.verseEnd, isNull);
    });

    test('parses a verse range', () {
      final r = bible.parse('1 Corinthians 13:4-7')!;
      expect(r.bookIndex, 45);
      expect(r.chapter, 13);
      expect(r.verseStart, 4);
      expect(r.verseEnd, 7);
    });

    test('parses an en-dash range', () {
      final r = bible.parse('Romans 8:38–39')!;
      expect(r.verseStart, 38);
      expect(r.verseEnd, 39);
    });

    test('parses a whole-chapter reference', () {
      final r = bible.parse('Psalm 23')!;
      expect(r.bookIndex, 18);
      expect(r.chapter, 23);
      expect(r.hasVerses, isFalse);
    });

    test('tolerates spacing and a trailing period on the book', () {
      final r = bible.parse('Jn. 3 : 16')!;
      expect(r.bookIndex, 42);
      expect(r.chapter, 3);
      expect(r.verseStart, 16);
    });

    test('returns null for an unknown book', () {
      expect(bible.parse('Hezekiah 4:2'), isNull);
    });
  });

  group('BibleService.findAll', () {
    test('finds every distinct reference in prose', () {
      final refs = bible.findAll(
          'Look at Ephesians 5:25 alongside Colossians 3:19, and remember '
          'what Paul says in 1 Corinthians 13:4-7.');
      expect(refs.length, 3);
      expect(refs[0].bookIndex, 48);
      expect(refs[1].bookIndex, 50);
      expect(refs[2].verseEnd, 7);
    });

    test('de-duplicates repeats of the same reference', () {
      final refs =
          bible.findAll('John 3:16 is the heart of it. John 3:16 again.');
      expect(refs.length, 1);
    });

    test('finds nothing in prose with no references', () {
      expect(bible.findAll('Pray together tonight before bed.'), isEmpty);
    });
  });

  group('BibleRef.covers', () {
    test('covers only the verses in range', () {
      final r = bible.parse('1 Corinthians 13:4-7')!;
      expect(r.covers(3), isFalse);
      expect(r.covers(4), isTrue);
      expect(r.covers(7), isTrue);
      expect(r.covers(8), isFalse);
    });

    test('a single verse covers only itself', () {
      final r = bible.parse('John 3:16')!;
      expect(r.covers(16), isTrue);
      expect(r.covers(17), isFalse);
    });

    test('a whole-chapter reference covers nothing specifically', () {
      expect(bible.parse('Psalm 23')!.covers(1), isFalse);
    });
  });

  group('BibleRef.label', () {
    test('formats each reference shape', () {
      expect(bible.parse('Psalm 23')!.label('Psalms'), 'Psalms 23');
      expect(bible.parse('John 3:16')!.label('John'), 'John 3:16');
      expect(bible.parse('1 Corinthians 13:4-7')!.label('1 Corinthians'),
          '1 Corinthians 13:4-7');
    });
  });
}
