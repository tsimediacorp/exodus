import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/bible_service.dart';

void main() {
  group('translation registry', () {
    test('ships at least one translation, and it is the default', () {
      expect(BibleService.translations, isNotEmpty);
      expect(BibleService.byId(null).id, BibleService.translations.first.id);
    });

    test('every entry is fully described', () {
      // The picker renders all four fields; a blank one is a blank row.
      for (final t in BibleService.translations) {
        expect(t.id, isNotEmpty);
        expect(t.abbrev, isNotEmpty);
        expect(t.name, isNotEmpty);
        expect(t.note, isNotEmpty);
        expect(t.assetPath, startsWith('assets/bible/'));
        expect(t.assetPath, endsWith('.json'));
      }
    });

    test('ids are unique', () {
      // The id is the storage value and the pagination cache key; a duplicate
      // would make one translation unreachable and the other mis-paginated.
      final ids = BibleService.translations.map((t) => t.id).toSet();
      expect(ids, hasLength(BibleService.translations.length));
    });

    test('asset paths are unique', () {
      final paths = BibleService.translations.map((t) => t.assetPath).toSet();
      expect(paths, hasLength(BibleService.translations.length));
    });

    test('an unknown stored id falls back rather than throwing', () {
      // A translation removed from a later build must not strand the device
      // that had selected it.
      expect(BibleService.byId('not-a-translation').id,
          BibleService.translations.first.id);
    });

    test('hasChoice reflects whether there is anything to switch to', () {
      expect(BibleService.hasChoice, BibleService.translations.length > 1);
    });

    test('the default resolves with no storage initialised', () {
      // Tests and first launch both run before SharedPreferences exists.
      expect(BibleService.instance.currentTranslation.abbrev,
          BibleService.translation);
    });
  });
}
