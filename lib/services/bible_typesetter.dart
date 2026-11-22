import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/bible_paper.dart';

/// What a run of the chapter's text is.
enum _Kind { text, divine, number, omitted, gap }

class _Run {
  final int start;
  final int end;
  final _Kind kind;
  final int verse;
  const _Run(this.start, this.end, this.kind, this.verse);
}

/// The lines of the chapter that fall on one page.
@immutable
class ProseSlice {
  /// Body lines [startLine, endLine).
  final int startLine;
  final int endLine;

  /// Their extent in the body paragraph's coordinates.
  final double top;
  final double bottom;

  /// True for the chapter's first page, which also carries the drop cap and
  /// the lines set beside it.
  final bool opening;

  const ProseSlice({
    required this.startLine,
    required this.endLine,
    required this.top,
    required this.bottom,
    required this.opening,
  });

  double get height => bottom - top;
}

/// The type of the book: sizes and faces in one place, so what is measured
/// is what is drawn.
@immutable
class BibleType {
  final double fontSize;
  final double lineHeight;
  final TextScaler scaler;

  const BibleType({
    this.fontSize = 15.5,
    this.lineHeight = 1.5,
    this.scaler = TextScaler.noScaling,
  });

  static const String display = 'Cormorant';

  TextStyle get text => TextStyle(
        fontFamily: 'Spectral',
        fontSize: fontSize,
        height: lineHeight,
        color: BiblePalette.ink,
      );

  /// Verse numbers: small superior figures in red, the printer's way.
  TextStyle get number => text.copyWith(
        color: BiblePalette.rubric,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.superscripts()],
      );

  /// LORD and GOD, set as the translators set them: small capitals.
  TextStyle get divine => text.copyWith(
        fontFeatures: const [FontFeature('c2sc')],
        letterSpacing: fontSize * 0.04,
      );

  TextStyle get omitted => text.copyWith(
        color: BiblePalette.faint,
        fontStyle: FontStyle.italic,
        fontSize: fontSize * 0.9,
      );

  /// The drop cap spans this many lines.
  int get capLines => scaler.scale(fontSize) > 24 ? 2 : 3;

  double get linePx => scaler.scale(fontSize) * lineHeight;

  TextStyle get cap => TextStyle(
        fontFamily: display,
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: linePx * capLines * 1.04,
        height: 1,
        color: BiblePalette.capInk,
      );

  @override
  bool operator ==(Object other) =>
      other is BibleType &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.scaler == scaler;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight, scaler);
}

/// A chapter set in type: one justified paragraph, running from page to page.
///
/// The whole chapter is laid out once, at the measure of the page, and each
/// page shows a band of its lines. Breaking it into separate paragraphs per
/// page would rebreak and rejustify the text at every page boundary; slicing
/// one paragraph keeps every line exactly where it was set.
///
/// The chapter opens with a drop cap. The lines beside it are a second,
/// narrower paragraph (the [lead]); the [body] takes up from the first
/// character the lead did not set.
class TypesetChapter {
  final BibleType type;
  final double width;
  final String text;
  final List<_Run> _runs;

  /// Character range of each verse (1-based), number to last word.
  final Map<int, (int, int)> _verses;

  /// The drop cap, or null when the chapter opens on punctuation it cannot
  /// carry well, or on nothing at all.
  final String? capLetter;
  final TextPainter? capPainter;
  final TextPainter? lead;
  final int leadLines;

  /// Where the body starts in [text].
  final int split;
  final TextPainter? body;
  final List<ProseSlice> slices;

  TypesetChapter._({
    required this.type,
    required this.width,
    required this.text,
    required List<_Run> runs,
    required Map<int, (int, int)> verses,
    required this.capLetter,
    required this.capPainter,
    required this.lead,
    required this.leadLines,
    required this.split,
    required this.body,
    required this.slices,
  })  : _runs = runs,
        _verses = verses;

  /// Width the drop cap and its gutter take from the lead lines.
  double get capWidth =>
      capPainter == null ? 0 : capPainter!.width + type.fontSize * 0.45;

  /// Height of the block the cap and lead lines make together.
  double get leadHeight {
    if (lead == null) return 0;
    final lines = lead!.computeLineMetrics();
    var h = 0.0;
    for (var i = 0; i < leadLines && i < lines.length; i++) {
      h += lines[i].height;
    }
    return math.max(h, (capPainter?.height ?? 0) * 0.92);
  }

  static final RegExp _divineWord = RegExp(r"\b(LORD|GOD|JEHOVAH|JAH)\b");

  /// Lay out [verses] (1-based content; empty strings are verses the
  /// translation omits) at [width]. The opening page has [openingHeight]
  /// for the drop-cap block and the lines below it; every later page has
  /// [pageHeight].
  static TypesetChapter layout({
    required List<String> verses,
    required double width,
    required BibleType type,
    required double openingHeight,
    required double pageHeight,
    String omittedLabel = 'Not included in this translation.',
  }) {
    final buf = StringBuffer();
    final runs = <_Run>[];
    final ranges = <int, (int, int)>{};
    String? cap;

    void add(String s, _Kind kind, int verse) {
      if (s.isEmpty) return;
      final start = buf.length;
      buf.write(s);
      runs.add(_Run(start, buf.length, kind, verse));
    }

    for (var v = 1; v <= verses.length; v++) {
      var content = verses[v - 1].trim();
      final omitted = content.isEmpty;
      if (v > 1) add(' ', _Kind.gap, v);
      final start = buf.length;
      if (v == 1 && !omitted) {
        // The drop cap takes the first letter, with any opening quote or
        // bracket that comes before it.
        final m = RegExp(r'^[“"‘(`\-]*[A-Za-z]').firstMatch(content);
        if (m != null) {
          cap = m.group(0);
          content = content.substring(m.end);
        }
      }
      // A narrow no-break space: a verse number never ends a line apart
      // from its verse.
      if (v > 1 || cap == null) add('$v\u202F', _Kind.number, v);
      if (omitted) {
        add(omittedLabel, _Kind.omitted, v);
      } else {
        var at = 0;
        for (final m in _divineWord.allMatches(content)) {
          add(content.substring(at, m.start), _Kind.text, v);
          final word = m.group(0)!;
          // The capital stays a capital; the rest drop to small capitals.
          add(word.substring(0, 1), _Kind.text, v);
          add(word.substring(1), _Kind.divine, v);
          at = m.end;
        }
        add(content.substring(at), _Kind.text, v);
      }
      ranges[v] = (start, buf.length);
    }
    final text = buf.toString();

    TextSpan spanOf(int from, int to) {
      final children = <InlineSpan>[];
      for (final r in runs) {
        if (r.end <= from || r.start >= to) continue;
        final s = math.max(r.start, from), e = math.min(r.end, to);
        children.add(TextSpan(
          text: text.substring(s, e),
          style: switch (r.kind) {
            _Kind.number => type.number,
            _Kind.divine => type.divine,
            _Kind.omitted => type.omitted,
            _ => null,
          },
        ));
      }
      return TextSpan(style: type.text, children: children);
    }

    TextPainter paint(int from, int to, double w) => TextPainter(
          text: spanOf(from, to),
          textAlign: TextAlign.justify,
          textDirection: TextDirection.ltr,
          textScaler: type.scaler,
        )..layout(maxWidth: math.max(1, w));

    TextPainter? capPainter;
    TextPainter? lead;
    var leadLines = 0;
    var split = 0;
    if (cap != null) {
      capPainter = TextPainter(
        text: TextSpan(text: cap, style: type.cap),
        textDirection: TextDirection.ltr,
      )..layout();
      final capW = capPainter.width + type.fontSize * 0.45;
      lead = paint(0, text.length, width - capW);
      final lines = lead.computeLineMetrics();
      leadLines = math.min(type.capLines, lines.length);
      if (lines.length > leadLines) {
        var y = 0.0;
        for (var i = 0; i < leadLines; i++) {
          y += lines[i].height;
        }
        split = lead
            .getPositionForOffset(Offset(0.5, y + lines[leadLines].height / 2))
            .offset;
        // A line starts after the space it broke at.
        while (split < text.length && text[split] == ' ') {
          split++;
        }
      } else {
        split = text.length;
      }
    }

    var leadBlock = 0.0;
    if (lead != null) {
      final lines = lead.computeLineMetrics();
      for (var i = 0; i < leadLines; i++) {
        leadBlock += lines[i].height;
      }
      leadBlock = math.max(leadBlock, capPainter!.height * 0.92);
    }
    final firstHeight = openingHeight - leadBlock;

    final body = split < text.length ? paint(split, text.length, width) : null;
    final tops = <double>[];
    final slices = <ProseSlice>[];
    if (body != null) {
      var y = 0.0;
      final metrics = body.computeLineMetrics();
      for (final m in metrics) {
        tops.add(y);
        y += m.height;
      }
      tops.add(y);
      var start = 0;
      var budget = firstHeight;
      var opening = true;
      for (var i = 0; i < metrics.length; i++) {
        final next = tops[i + 1] - tops[start];
        if (next > budget + 0.5 && (i > start || opening)) {
          slices.add(ProseSlice(
              startLine: start,
              endLine: i,
              top: tops[start],
              bottom: tops[i],
              opening: opening));
          start = i;
          budget = pageHeight;
          opening = false;
        }
      }
      slices.add(ProseSlice(
          startLine: start,
          endLine: metrics.length,
          top: tops[start],
          bottom: tops[metrics.length],
          opening: opening));
    } else {
      slices.add(const ProseSlice(
          startLine: 0, endLine: 0, top: 0, bottom: 0, opening: true));
    }

    return TypesetChapter._(
      type: type,
      width: width,
      text: text,
      runs: runs,
      verses: ranges,
      capLetter: cap,
      capPainter: capPainter,
      lead: lead,
      leadLines: leadLines,
      split: split,
      body: body,
      slices: slices,
    );
  }

  /// The verse at character [offset] of [text].
  int? verseAtOffset(int offset) {
    for (final r in _runs) {
      if (offset >= r.start && offset < r.end) return r.verse;
    }
    return _runs.isEmpty ? null : _runs.last.verse;
  }

  /// The verse under [p] in the lead block (coordinates relative to the
  /// lead paragraph's origin, beside the cap).
  int? verseInLead(Offset p) {
    final l = lead;
    if (l == null) return null;
    return verseAtOffset(l.getPositionForOffset(p).offset);
  }

  /// The verse under [p] on [slice] (coordinates relative to the slice's
  /// top-left).
  int? verseInSlice(ProseSlice slice, Offset p) {
    final b = body;
    if (b == null || p.dy < 0 || p.dy > slice.height) return null;
    final o = b.getPositionForOffset(p.translate(0, slice.top)).offset;
    return verseAtOffset(o + split);
  }

  /// Boxes of verse [v] in the lead block, in lead coordinates.
  List<Rect> leadBoxes(int v) {
    final r = _verses[v], l = lead;
    if (r == null || l == null || r.$1 >= split) return const [];
    return [
      for (final b in l.getBoxesForSelection(
          TextSelection(baseOffset: r.$1, extentOffset: math.min(r.$2, split))))
        b.toRect()
    ];
  }

  /// Boxes of verse [v] on [slice], in slice coordinates.
  List<Rect> sliceBoxes(int v, ProseSlice slice) {
    final r = _verses[v], b = body;
    if (r == null || b == null || r.$2 <= split) return const [];
    final out = <Rect>[];
    for (final box in b.getBoxesForSelection(TextSelection(
        baseOffset: math.max(r.$1, split) - split,
        extentOffset: r.$2 - split))) {
      final rect = box.toRect();
      final mid = rect.center.dy;
      if (mid >= slice.top && mid < slice.bottom) {
        out.add(rect.translate(0, -slice.top));
      }
    }
    return out;
  }

  /// The slice (page of text) where verse [v] begins.
  int sliceOfVerse(int v) {
    final r = _verses[v], b = body;
    if (r == null || b == null || r.$1 < split) return 0;
    final boxes = b.getBoxesForSelection(TextSelection(
        baseOffset: r.$1 - split, extentOffset: r.$1 - split + 1));
    if (boxes.isEmpty) return 0;
    final y = boxes.first.toRect().center.dy;
    for (var i = 0; i < slices.length; i++) {
      if (y >= slices[i].top && y < slices[i].bottom) return i;
    }
    return slices.length - 1;
  }

  /// The last verse with words on [slice].
  int lastVerseOn(int slice) {
    final b = body;
    if (b == null) return _verses.length;
    final s = slices[slice.clamp(0, slices.length - 1)];
    if (s.height <= 0) return firstVerseOn(slice);
    final o = b.getPositionForOffset(Offset(width - 1, s.bottom - 2)).offset;
    return verseAtOffset(math.max(0, o - 1) + split) ?? _verses.length;
  }

  /// Verses in the chapter.
  int get verseCount => _verses.length;

  /// The first verse that starts on [slice], or the verse running onto it.
  int firstVerseOn(int slice) {
    if (slice <= 0 || body == null) return 1;
    final s = slices[slice.clamp(0, slices.length - 1)];
    final o = body!.getPositionForOffset(Offset(0, s.top + 1)).offset;
    return verseAtOffset(o + split) ?? 1;
  }

  void dispose() {
    capPainter?.dispose();
    lead?.dispose();
    body?.dispose();
  }
}

/// Paints a band of a laid-out paragraph, with the reader's highlights
/// under the words.
class ParagraphBandPainter extends CustomPainter {
  final TextPainter painter;
  final double top;
  final double height;
  final List<(Rect, Color)> washes;

  ParagraphBandPainter({
    required this.painter,
    required this.top,
    required this.height,
    required this.washes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(-24, 0, size.width + 48, height));
    for (final (r, c) in washes) {
      // A wash a little proud of the line, softly rounded, like a highlighter
      // pass rather than a selection box.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            r.inflate(1.5).translate(0, 0.5), const Radius.circular(3)),
        Paint()
          ..color = c
          ..blendMode = ui.BlendMode.multiply,
      );
    }
    canvas.translate(0, -top);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ParagraphBandPainter old) =>
      old.painter != painter ||
      old.top != top ||
      old.height != height ||
      !_sameWashes(old.washes, washes);

  static bool _sameWashes(List<(Rect, Color)> a, List<(Rect, Color)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
