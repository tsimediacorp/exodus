import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/services/bible_service.dart';
import 'package:exodus/services/daily_verse.dart';

/// The home screen's verse must be the same all day, the same on both
/// partners' phones, and available with no network — which is why it is
/// chosen from a curated list by the calendar date rather than generated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => BibleService.instance.load());

  test('the same day always gives the same verse', () {
    final morning = DateTime(2026, 8, 28, 6, 30);
    final night = DateTime(2026, 8, 28, 23, 45);
    expect(DailyVerse.referenceFor(morning), DailyVerse.referenceFor(night));
  });

  test('consecutive days give different verses', () {
    expect(DailyVerse.referenceFor(DateTime(2026, 8, 28)),
        isNot(DailyVerse.referenceFor(DateTime(2026, 8, 29))));
  });

  test('every curated reference actually resolves', () {
    // A typo in the list would show a card with a reference and no verse.
    for (var i = 0; i < DailyVerse.count; i++) {
      final day = DateTime(2026, 1, 1).add(Duration(days: i));
      final ref = DailyVerse.refFor(day);
      expect(ref, isNotNull,
          reason: '${DailyVerse.referenceFor(day)} does not parse');
      expect(DailyVerse.textFor(day), isNotEmpty,
          reason: '${DailyVerse.referenceFor(day)} resolves to no text');
    }
  });

  test('the whole list is reachable across a year', () {
    final seen = <String>{};
    for (var i = 0; i < 400; i++) {
      seen.add(DailyVerse.referenceFor(DateTime(2026, 1, 1).add(Duration(days: i))));
    }
    expect(seen.length, DailyVerse.count);
  });

  test('dates before the epoch anchor do not throw', () {
    expect(() => DailyVerse.referenceFor(DateTime(1998, 3, 3)), returnsNormally);
  });
}
