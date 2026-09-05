import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/services/card_backgrounds.dart';

/// A handful of plausible filenames, plus the README that really is in the
/// folder.
const _folder = 'assets/backgrounds/';
const _manifest = [
  '${_folder}README.md',
  '${_folder}dawn-ridges.jpg',
  '${_folder}cloud-sea.JPEG',
  '${_folder}desert-dusk.png',
  '${_folder}storm.webp',
  'assets/textures/grain.png', // right type, wrong folder
];

void main() {
  tearDown(() => CardBackgrounds.debugSetAvailable(null));

  group('what counts as a background', () {
    test('only images, only from the backgrounds folder', () {
      expect(CardBackgrounds.imagesIn(_manifest), [
        '${_folder}cloud-sea.JPEG',
        '${_folder}dawn-ridges.jpg',
        '${_folder}desert-dusk.png',
        '${_folder}storm.webp',
      ]);
    });

    test('the README is never a card background', () {
      expect(CardBackgrounds.imagesIn(_manifest),
          isNot(contains('${_folder}README.md')));
    });

    test('the order does not depend on the manifest order', () {
      expect(CardBackgrounds.imagesIn(_manifest),
          CardBackgrounds.imagesIn(_manifest.reversed));
    });
  });

  group('an empty folder is a valid state', () {
    test('nothing loaded yet means the painted landscape', () {
      expect(CardBackgrounds.hasAny, isFalse);
      expect(CardBackgrounds.pick('1 Peter 5:7'), isNull);
    });

    test('a folder holding only the README also means the painted landscape',
        () {
      CardBackgrounds.debugSetAvailable(['${_folder}README.md']);
      expect(CardBackgrounds.hasAny, isFalse);
      expect(CardBackgrounds.pick('1 Peter 5:7'), isNull);
    });
  });

  group('a verse always gets the same scene', () {
    setUp(() => CardBackgrounds.debugSetAvailable(_manifest));

    test('the same reference picks the same image, every time', () {
      final first = CardBackgrounds.pick('1 Peter 5:7');
      expect(first, isNotNull);
      for (var i = 0; i < 50; i++) {
        expect(CardBackgrounds.pick('1 Peter 5:7'), first);
      }
    });

    test('reloading the same set does not reshuffle it', () {
      final before = CardBackgrounds.pick('Romans 8:28');
      CardBackgrounds.debugSetAvailable(_manifest.reversed.toList());
      expect(CardBackgrounds.pick('Romans 8:28'), before);
    });

    test('different verses do not all land on one image', () {
      const refs = [
        '1 Peter 5:7',
        'Romans 8:28',
        'Psalm 23:1',
        'John 3:16',
        'Ephesians 4:32',
        'James 1:19',
        'Proverbs 3:5',
        'Isaiah 41:10',
      ];
      final chosen = refs.map(CardBackgrounds.pick).toSet();
      expect(chosen.length, greaterThan(1));
    });

    test('every pick is one of the files we were given', () {
      final files = CardBackgrounds.imagesIn(_manifest);
      for (final ref in ['Psalm 1:1', 'Job 19:25', 'Micah 6:8', 'Luke 6:31']) {
        expect(files, contains(CardBackgrounds.pick(ref)));
      }
    });
  });
}
