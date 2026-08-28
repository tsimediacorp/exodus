import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/devotional.dart';

Devotional _make({
  required String goal,
  bool isFallback = false,
  DateTime? day,
}) =>
    Devotional(
      day: day ?? DateTime(2026, 8, 2),
      title: 'Title',
      scriptureRef: 'Ephesians 5:25',
      scriptureText: 'Husbands, love your wives…',
      reflection: 'Reflection body.',
      prayer: 'Prayer body.',
      action: 'Do this together.',
      goalSnapshot: goal,
      isFallback: isFallback,
    );

void main() {
  group('Devotional.needsGeneration', () {
    test('regenerates when nothing is stored', () {
      expect(Devotional.needsGeneration(null, 'patience'), isTrue);
    });

    test('does not regenerate a real devotional for the current goal', () {
      final d = _make(goal: 'patience');
      expect(Devotional.needsGeneration(d, 'patience'), isFalse);
    });

    test('regenerates when the goal has changed', () {
      // The bug this guards: storage is keyed by day alone, so without the
      // goal comparison a goal change kept serving the old goal's devotional.
      final d = _make(goal: 'patience');
      expect(Devotional.needsGeneration(d, 'generosity'), isTrue);
    });

    test('regenerates a stored fallback even when the goal matches', () {
      // Fallbacks used to be persisted and then treated as done for the day,
      // so a network blip meant canned content until midnight.
      final d = _make(goal: 'patience', isFallback: true);
      expect(Devotional.needsGeneration(d, 'patience'), isTrue);
    });
  });

  group('Devotional JSON', () {
    test('round-trips isFallback', () {
      final original = _make(goal: 'patience', isFallback: true);
      final restored = Devotional.fromJson(original.toJson());
      expect(restored.isFallback, isTrue);
      expect(restored.goalSnapshot, 'patience');
      expect(restored.dayKey, original.dayKey);
      expect(restored.scriptureRef, 'Ephesians 5:25');
    });

    test('round-trips a real devotional', () {
      final restored = Devotional.fromJson(_make(goal: 'patience').toJson());
      expect(restored.isFallback, isFalse);
    });

    test('treats records written before isFallback existed as real', () {
      // Upgrade path: existing stored devotionals have no isFallback key and
      // must not all be regenerated on first launch after the update.
      final legacy = {
        'day': DateTime(2026, 8, 2).toIso8601String(),
        'title': 'Title',
        'scriptureRef': 'Ephesians 5:25',
        'scriptureText': 'Husbands, love your wives…',
        'reflection': 'Reflection body.',
        'prayer': 'Prayer body.',
        'action': 'Do this together.',
        'goalSnapshot': 'patience',
      };
      final restored = Devotional.fromJson(legacy);
      expect(restored.isFallback, isFalse);
      expect(Devotional.needsGeneration(restored, 'patience'), isFalse);
    });
  });

  group('Devotional.keyFor', () {
    test('pads month and day', () {
      expect(Devotional.keyFor(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('same day at different times shares a key', () {
      expect(
        Devotional.keyFor(DateTime(2026, 8, 2, 6, 30)),
        Devotional.keyFor(DateTime(2026, 8, 2, 23, 59)),
      );
    });
  });
}
