import 'dart:convert';

import 'package:flutter/services.dart';

/// One illustration plate: a full page of art facing (or heading) the
/// chapter it illustrates.
class BiblePlate {
  final String id;
  final int book;
  final int chapter;

  /// The verse the caption quotes, read from whichever translation is open.
  final int verse;

  /// The chapter's heading in the book.
  final String title;
  final bool isMap;

  /// 1-based, in canonical order through the whole Bible: printed as
  /// "Plate xiv".
  final int number;

  const BiblePlate({
    required this.id,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.title,
    required this.isMap,
    required this.number,
  });

  String get asset => 'assets/bible_art/plates/$id.webp';

  /// "xiv": plates are numbered the way a printed Bible numbers them.
  String get numeral => roman(number).toLowerCase();

  static String roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const glyphs = [
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I'
    ];
    final out = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        out.write(glyphs[i]);
        n -= values[i];
      }
    }
    return out.toString();
  }
}

/// The illustrated Bible's art: about 250 plates for the passages that
/// carry a scene, and small ornaments for every other chapter, so that no
/// chapter opens bare.
///
/// Everything ships in the app (assets/bible_art), catalogued by
/// manifest.json, which tools/bible_art/process.py writes.
class BibleArt {
  BibleArt._();
  static final BibleArt instance = BibleArt._();

  final Map<int, List<BiblePlate>> _byChapter = {};
  List<String> _vignettes = const [];
  Future<void>? _loading;

  bool get isLoaded => _vignettes.isNotEmpty;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final json = jsonDecode(
            await rootBundle.loadString('assets/bible_art/manifest.json'))
        as Map<String, dynamic>;
    final plates = (json['plates'] as List).cast<Map<String, dynamic>>();
    var n = 0;
    for (final p in plates) {
      final plate = BiblePlate(
        id: p['id'] as String,
        book: p['book'] as int,
        chapter: p['chapter'] as int,
        verse: p['verse'] as int,
        title: p['title'] as String,
        isMap: p['map'] as bool? ?? false,
        number: ++n,
      );
      _byChapter
          .putIfAbsent(_key(plate.book, plate.chapter), () => [])
          .add(plate);
    }
    _vignettes = (json['vignettes'] as List).cast<String>();
  }

  static int _key(int book, int chapter) => book * 1000 + chapter;

  /// Plates illustrating [chapter] of [book], in verse order. The first
  /// faces the chapter's opening; any others stand where their verse falls.
  List<BiblePlate> platesFor(int book, int chapter) =>
      _byChapter[_key(book, chapter)] ?? const [];

  /// A small ornament for the head of a chapter, chosen from the motifs that
  /// belong to that part of the Bible and varied chapter by chapter.
  String? vignetteFor(int book, int chapter) {
    if (_vignettes.isEmpty) return null;
    final themed = _themes.entries
        .firstWhere((e) => book <= e.key, orElse: () => _themes.entries.last)
        .value
        .where(_vignettes.contains)
        .toList();
    final pool = themed.isEmpty ? _vignettes : themed;
    final id = pool[(book * 7 + chapter * 3) % pool.length];
    return 'assets/bible_art/vignettes/$id.webp';
  }

  /// Motifs by the last book (0-based) of each part of the Bible.
  static const Map<int, List<String>> _themes = {
    4: ['v-tablets', 'v-tent', 'v-camel', 'v-candlestick', 'v-lamb', 'v-palm'],
    16: ['v-crown', 'v-gate', 'v-temple', 'v-cedar', 'v-palm', 'v-scroll'],
    21: ['v-lily', 'v-dove', 'v-olive', 'v-sheep', 'v-pomegranate', 'v-fig'],
    38: ['v-lamp', 'v-scroll', 'v-lion', 'v-rainbow', 'v-vine', 'v-cedar'],
    42: ['v-fish', 'v-net', 'v-lamb', 'v-vine', 'v-cup', 'v-cross', 'v-tomb'],
    43: ['v-dove', 'v-anchor', 'v-key', 'v-scroll'],
    64: ['v-pen', 'v-anchor', 'v-olive', 'v-vine', 'v-key', 'v-cup'],
    65: ['v-crown', 'v-candlestick', 'v-star', 'v-gate', 'v-lamb'],
  };
}
