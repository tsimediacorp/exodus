import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/confession.dart';

void main() {
  group('Confession', () {
    test('carries no author, couple or account identity', () {
      // The confidentiality claim on screen rests on this: the record itself
      // has nothing on it that ties back to a person. If a field is ever added
      // that does, this test should be the thing that objects.
      final json = Confession.now('something').toJson().keys.toSet();
      expect(json, {
        'id',
        'createdAt',
        'text',
        'prayer',
        'scriptureRef',
        'isFallback',
      });
    });

    test('two confessions made in a row get distinct ids', () {
      // Microsecond resolution, because deletion is by id and a collision
      // would delete the wrong one.
      final a = Confession.now('one');
      final b = Confession.now('two');
      expect(a.id, isNot(b.id));
    });

    test('round-trips through json', () {
      final original = Confession.now('what I did')
        ..prayer = 'Father, forgive.'
        ..scriptureRef = '1 John 1:9'
        ..isFallback = true;

      final restored = Confession.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.text, 'what I did');
      expect(restored.prayer, 'Father, forgive.');
      expect(restored.scriptureRef, '1 John 1:9');
      expect(restored.isFallback, isTrue);
      expect(restored.createdAt.toIso8601String(),
          original.createdAt.toIso8601String());
    });

    test('a malformed record does not throw', () {
      // Stored json is only as good as the last write; a corrupt entry must
      // not take the whole confessional down with it.
      final restored = Confession.fromJson(const {});
      expect(restored.text, '');
      expect(restored.prayer, '');
      expect(restored.isFallback, isFalse);
    });

    test('a fresh confession has no prayer yet and is not a fallback', () {
      final c = Confession.now('  spoken  ');
      expect(c.prayer, isEmpty);
      expect(c.isFallback, isFalse);
    });
  });
}
