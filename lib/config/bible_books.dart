/// Canon order plus every spelling of a book name we expect to see in model
/// output or a devotional's scriptureRef, so references parse without the
/// user having to type them a particular way.
class BibleBooks {
  /// 66 books in canon order — the same order as the bundled translation, so
  /// the index here IS the index into the text.
  static const List<String> names = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
    'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
    '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
    'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
    'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
    'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
    'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John', 'Acts',
    'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James',
    '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation',
  ];

  /// Index of the first New Testament book, for grouping in the book picker.
  static const int firstNewTestament = 39;

  /// Extra spellings mapped to canon index. The canonical names above are
  /// matched automatically; this covers abbreviations and common variants.
  static const Map<String, int> _aliases = {
    'gen': 0, 'ge': 0, 'gn': 0,
    'exo': 1, 'ex': 1, 'exod': 1,
    'lev': 2, 'lv': 2,
    'num': 3, 'nm': 3, 'nu': 3,
    'deut': 4, 'dt': 4, 'deu': 4,
    'josh': 5, 'jos': 5, 'js': 5,
    'judg': 6, 'jdg': 6, 'jg': 6,
    'ruth': 7, 'rt': 7, 'ru': 7,
    '1sam': 8, '1sa': 8, '1sm': 8, 'firstsamuel': 8,
    '2sam': 9, '2sa': 9, '2sm': 9, 'secondsamuel': 9,
    '1kings': 10, '1ki': 10, '1kgs': 10, '1kg': 10,
    '2kings': 11, '2ki': 11, '2kgs': 11, '2kg': 11,
    '1chron': 12, '1chr': 12, '1ch': 12, '1chronicles': 12,
    '2chron': 13, '2chr': 13, '2ch': 13, '2chronicles': 13,
    'ezr': 14,
    'neh': 15, 'ne': 15,
    'esth': 16, 'est': 16,
    'jb': 17,
    'psalm': 18, 'ps': 18, 'psa': 18, 'psalms': 18, 'pss': 18,
    'prov': 19, 'pro': 19, 'pr': 19, 'prv': 19,
    'eccl': 20, 'ecc': 20, 'ec': 20, 'qoh': 20,
    'song': 21, 'sos': 21, 'songofsongs': 21, 'canticles': 21, 'ss': 21,
    'isa': 22, 'is': 22,
    'jer': 23, 'je': 23,
    'lam': 24, 'la': 24,
    'ezek': 25, 'eze': 25, 'ezk': 25,
    'dan': 26, 'dn': 26, 'da': 26,
    'hos': 27, 'ho': 27,
    'joe': 28, 'jl': 28,
    'am': 29, 'amo': 29,
    'obad': 30, 'oba': 30, 'ob': 30,
    'jon': 31, 'jnh': 31,
    'mic': 32, 'mi': 32,
    'nah': 33, 'na': 33,
    'hab': 34, 'hb': 34,
    'zeph': 35, 'zep': 35, 'zp': 35,
    'hag': 36, 'hg': 36,
    'zech': 37, 'zec': 37, 'zc': 37,
    'mal': 38, 'ml': 38,
    'matt': 39, 'mat': 39, 'mt': 39,
    'mrk': 40, 'mk': 40, 'mr': 40,
    'luk': 41, 'lk': 41, 'lu': 41,
    'jhn': 42, 'jn': 42, 'joh': 42, 'jo': 42,
    'act': 43, 'ac': 43,
    'rom': 44, 'ro': 44, 'rm': 44,
    '1cor': 45, '1co': 45, '1corinthians': 45,
    '2cor': 46, '2co': 46, '2corinthians': 46,
    'gal': 47, 'ga': 47,
    'eph': 48, 'ep': 48,
    'phil': 49, 'php': 49, 'philippians': 49,
    'col': 50, 'co': 50,
    '1thess': 51, '1th': 51, '1thes': 51, '1thessalonians': 51,
    '2thess': 52, '2th': 52, '2thes': 52, '2thessalonians': 52,
    '1tim': 53, '1ti': 53, '1tm': 53,
    '2tim': 54, '2ti': 54, '2tm': 54,
    'tit': 55, 'ti': 55,
    'phlm': 56, 'phm': 56, 'philem': 56,
    'heb': 57, 'hb2': 57,
    'jas': 58, 'jam': 58, 'jm': 58,
    '1pet': 59, '1pe': 59, '1pt': 59, '1peter': 59,
    '2pet': 60, '2pe': 60, '2pt': 60, '2peter': 60,
    '1jn': 61, '1jo': 61, '1joh': 61, '1john': 61,
    '2jn': 62, '2jo': 62, '2joh': 62, '2john': 62,
    '3jn': 63, '3jo': 63, '3joh': 63, '3john': 63,
    'jud': 64, 'jde': 64,
    'rev': 65, 'rv': 65, 'apocalypse': 65, 'revelations': 65,
  };

  /// Normalise for matching: lowercase, strip punctuation and whitespace, and
  /// fold written ordinals ("First John", "I John") to digits.
  static String normalise(String s) {
    var t = s.toLowerCase().trim();
    t = t
        .replaceAll(RegExp(r'^(1st|first|i)\s+'), '1')
        .replaceAll(RegExp(r'^(2nd|second|ii)\s+'), '2')
        .replaceAll(RegExp(r'^(3rd|third|iii)\s+'), '3');
    return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Canon index for a book name or abbreviation, or null if unrecognised.
  static int? indexOf(String book) {
    final key = normalise(book);
    if (key.isEmpty) return null;
    for (var i = 0; i < names.length; i++) {
      if (normalise(names[i]) == key) return i;
    }
    final alias = _aliases[key];
    if (alias != null) return alias;
    // Last resort: a unique prefix match, so "Ecclesiast" or "Thessalon"
    // still resolve. Ambiguous prefixes are rejected rather than guessed.
    final hits = <int>[];
    for (var i = 0; i < names.length; i++) {
      if (normalise(names[i]).startsWith(key)) hits.add(i);
    }
    return hits.length == 1 ? hits.first : null;
  }
}
