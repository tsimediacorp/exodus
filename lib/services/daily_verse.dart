import '../models/bible_ref.dart';
import 'bible_service.dart';

/// The verse on the home screen.
///
/// Chosen from a curated list by the date, not at random and not by the model:
/// it must be the SAME verse all day (so it does not change under someone who
/// reopens the app), the same verse on both partners' phones, and available
/// with no network at all. A generated verse-of-the-day would fail all three.
///
/// The list is deliberately weighted toward comfort, courage and covenant —
/// what a couple opening this app in the morning needs — rather than being a
/// neutral sample of scripture.
class DailyVerse {
  DailyVerse._();

  static const List<String> _references = [
    'Deuteronomy 31:6', 'Joshua 1:9', 'Psalm 23:1', 'Psalm 27:1',
    'Psalm 34:18', 'Psalm 46:1', 'Psalm 55:22', 'Psalm 91:4',
    'Psalm 103:12', 'Psalm 118:24', 'Psalm 119:105', 'Psalm 121:1',
    'Psalm 139:14', 'Proverbs 3:5', 'Proverbs 15:1', 'Proverbs 17:17',
    'Proverbs 18:22', 'Proverbs 31:25', 'Ecclesiastes 4:12',
    'Isaiah 26:3', 'Isaiah 40:31', 'Isaiah 41:10', 'Isaiah 43:2',
    'Jeremiah 29:11', 'Lamentations 3:22', 'Micah 6:8', 'Zephaniah 3:17',
    'Matthew 6:33', 'Matthew 11:28', 'Matthew 19:6', 'Mark 10:9',
    'John 14:27', 'John 15:12', 'John 16:33', 'Romans 5:8',
    'Romans 8:28', 'Romans 12:10', 'Romans 15:13', '1 Corinthians 13:4',
    '1 Corinthians 13:7', '2 Corinthians 12:9', 'Galatians 5:22',
    'Galatians 6:9', 'Ephesians 4:2', 'Ephesians 4:32', 'Ephesians 5:25',
    'Philippians 4:6', 'Philippians 4:13', 'Colossians 3:13',
    'Colossians 3:14', '1 Thessalonians 5:11', '2 Timothy 1:7',
    'Hebrews 10:24', 'Hebrews 11:1', 'Hebrews 13:5', 'James 1:19',
    '1 Peter 4:8', '1 Peter 5:7', '1 John 4:18', '1 John 4:19',
  ];

  /// Days since a fixed epoch, so the choice depends only on the calendar day
  /// and never on the time of day or the device's clock drifting by hours.
  static int _dayIndex(DateTime day) =>
      DateTime(day.year, day.month, day.day).difference(DateTime(2000)).inDays;

  /// The reference for [day] (default today), e.g. "Deuteronomy 31:6".
  static String referenceFor([DateTime? day]) =>
      _references[_dayIndex(day ?? DateTime.now()).abs() % _references.length];

  /// The parsed reference, or null if it does not resolve (a curated typo).
  static BibleRef? refFor([DateTime? day]) =>
      BibleService.instance.parse(referenceFor(day));

  /// The verse text in the reader's current translation, or empty when the
  /// Bible has not finished loading. Callers show the reference alone rather
  /// than an empty card.
  static String textFor([DateTime? day]) {
    final ref = refFor(day);
    if (ref == null) return '';
    return BibleService.instance.textFor(ref);
  }

  static int get count => _references.length;
}
