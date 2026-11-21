import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// Highlight colours. Muted, because they sit under light text on a dark
/// page: a saturated marker yellow would swallow the words it marks.
class MarkColors {
  MarkColors._();

  static const highlights = <Color>[
    Color(0xFFC9A961), // brass
    Color(0xFFC77D8A), // rose
    Color(0xFF7FA88B), // sage
    Color(0xFF6E9BD8), // sky
    Color(0xFF9D87C9), // lavender
  ];

  static const names = ['Brass', 'Rose', 'Sage', 'Sky', 'Lavender'];

  static const ink = <Color>[
    Color(0xFFE5C880), // brass glow
    Color(0xFFE6ECF5), // porcelain
    Color(0xFFE59AA6), // rose
    Color(0xFF8FB8F0), // sky
  ];
}

/// One pen stroke, pinned to a verse.
///
/// Points are stored relative to that verse's box: x as a fraction of its
/// width, y as a fraction of its height. A page reflows whenever the font
/// size, translation or screen changes (unfolding the Duo reflows every
/// page), and ink stored in page coordinates would end up circling the
/// wrong words. Pinned to the verse, an underline stays under its verse.
class InkStroke {
  final String id;
  final int verse;
  final int color;
  final double width;
  final List<Offset> points;

  InkStroke({
    required this.id,
    required this.verse,
    required this.color,
    required this.points,
    this.width = 2.4,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'v': verse,
        'c': color,
        'w': width,
        // Three decimals of a verse box is well under a pixel.
        'p': [
          for (final p in points) ...[
            (p.dx * 1000).round() / 1000,
            (p.dy * 1000).round() / 1000,
          ]
        ],
      };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List<dynamic>).cast<num>();
    return InkStroke(
      id: j['id'] as String,
      verse: (j['v'] as num).toInt(),
      color: (j['c'] as num).toInt(),
      width: (j['w'] as num?)?.toDouble() ?? 2.4,
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }
}

/// What one chapter carries: highlights, notes and ink.
class ChapterMarks {
  final Map<int, int> highlights;
  final Map<int, String> notes;
  final List<InkStroke> ink;

  ChapterMarks({
    Map<int, int>? highlights,
    Map<int, String>? notes,
    List<InkStroke>? ink,
  })  : highlights = highlights ?? {},
        notes = notes ?? {},
        ink = ink ?? [];

  bool get isEmpty => highlights.isEmpty && notes.isEmpty && ink.isEmpty;

  Map<String, dynamic> toJson() => {
        if (highlights.isNotEmpty)
          'h': {for (final e in highlights.entries) '${e.key}': e.value},
        if (notes.isNotEmpty)
          'n': {for (final e in notes.entries) '${e.key}': e.value},
        if (ink.isNotEmpty) 'i': ink.map((s) => s.toJson()).toList(),
      };

  factory ChapterMarks.fromJson(Map<String, dynamic> j) => ChapterMarks(
        highlights: {
          for (final e in ((j['h'] as Map?) ?? const {}).entries)
            int.parse('${e.key}'): (e.value as num).toInt(),
        },
        notes: {
          for (final e in ((j['n'] as Map?) ?? const {}).entries)
            int.parse('${e.key}'): '${e.value}',
        },
        ink: [
          for (final s in (j['i'] as List<dynamic>?) ?? const [])
            InkStroke.fromJson(s as Map<String, dynamic>),
        ],
      );
}

/// Every highlight, note and stroke the couple has put in their Bible.
///
/// Keyed by book and chapter, not translation: verse numbering is shared,
/// so a note written in the KJV is still there in the WEB.
class BibleMarks extends ChangeNotifier {
  BibleMarks._();
  static final BibleMarks instance = BibleMarks._();

  final StorageService _storage = StorageService.instance;
  Map<String, ChapterMarks>? _cache;

  Map<String, ChapterMarks> get _all {
    if (_cache != null) return _cache!;
    final raw = _storage.loadBibleMarksRaw();
    if (raw == null || raw.isEmpty) return _cache = {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _cache = {
        for (final e in json.entries)
          e.key: ChapterMarks.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return _cache = {};
    }
  }

  @visibleForTesting
  void reset() => _cache = null;

  static String _key(int book, int chapter) => '$book:$chapter';

  ChapterMarks chapter(int book, int chapter) =>
      _all[_key(book, chapter)] ?? ChapterMarks();

  ChapterMarks _edit(int book, int chapter) =>
      _all.putIfAbsent(_key(book, chapter), ChapterMarks.new);

  Future<void> _save() async {
    _all.removeWhere((_, m) => m.isEmpty);
    await _storage.saveBibleMarksRaw(jsonEncode(
        {for (final e in _all.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  /// Highlight [verses] in colour [color], or clear them with null.
  Future<void> highlight(
      int book, int chapter, Iterable<int> verses, int? color) async {
    final marks = _edit(book, chapter);
    for (final v in verses) {
      if (color == null) {
        marks.highlights.remove(v);
      } else {
        marks.highlights[v] = color;
      }
    }
    await _save();
  }

  /// Set the note on [verse]; an empty note removes it.
  Future<void> setNote(int book, int chapter, int verse, String text) async {
    final marks = _edit(book, chapter);
    if (text.trim().isEmpty) {
      marks.notes.remove(verse);
    } else {
      marks.notes[verse] = text.trim();
    }
    await _save();
  }

  Future<void> addStroke(int book, int chapter, InkStroke stroke) async {
    _edit(book, chapter).ink.add(stroke);
    await _save();
  }

  Future<void> removeStroke(int book, int chapter, String id) async {
    _edit(book, chapter).ink.removeWhere((s) => s.id == id);
    await _save();
  }

  /// Every chapter with a note, for the notes list, in Bible order.
  List<({int book, int chapter, int verse, String text})> allNotes() {
    final out = <({int book, int chapter, int verse, String text})>[];
    for (final e in _all.entries) {
      final parts = e.key.split(':');
      final book = int.parse(parts[0]);
      final ch = int.parse(parts[1]);
      for (final n in e.value.notes.entries) {
        out.add((book: book, chapter: ch, verse: n.key, text: n.value));
      }
    }
    out.sort((a, b) => a.book != b.book
        ? a.book.compareTo(b.book)
        : a.chapter != b.chapter
            ? a.chapter.compareTo(b.chapter)
            : a.verse.compareTo(b.verse));
    return out;
  }
}
