import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/bible_art.dart';
import '../services/bible_typesetter.dart';
import 'bible_paper.dart';

/// Margins of a printed page. Wider at the spine than at the fore-edge, as
/// a book is set, so no line runs into the fold; deep at the head, where the
/// reader's controls float over the paper.
class PageMargins {
  PageMargins._();

  static const double head = 58;
  static const double foot = 44;

  /// The margins of a page, widened where the page runs under the screen's
  /// own furniture ([screen]: the status column, the home indicator).
  ///
  /// Facing pages widen both outer margins alike, so the two text blocks
  /// stay the same width and the spread stays symmetrical about the spine,
  /// as a printed one is.
  static EdgeInsets of(PageSide side, [EdgeInsets screen = EdgeInsets.zero]) {
    const outer = 40.0;
    final widest = math.max(screen.left, screen.right);
    final out = widest == 0 ? outer : math.max(outer, widest + 14);
    final top = head + screen.top;
    final bottom = foot + screen.bottom;
    return switch (side) {
      PageSide.left => EdgeInsets.fromLTRB(out, top, 34, bottom),
      PageSide.right => EdgeInsets.fromLTRB(34, top, out, bottom),
      PageSide.single =>
        EdgeInsets.fromLTRB(30 + screen.left, top, 26 + screen.right, bottom),
    };
  }

  /// The margins for [side] of a page built under a [PageInsets].
  static EdgeInsets inContext(BuildContext context, PageSide side) =>
      of(side, PageInsets.of(context));
}

/// The parts of the screen the pages run under but must not print on.
///
/// Unfolded, the book is laid edge to edge, so its spine sits on the hinge
/// and its paper reaches the edges of the glass; the status column and the
/// home indicator become margin.
class PageInsets extends InheritedWidget {
  final EdgeInsets insets;

  const PageInsets({super.key, required this.insets, required super.child});

  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageInsets>()?.insets ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(PageInsets old) => old.insets != insets;
}

/// How each verse should look on the page, and what touching it does.
class ProseDecor {
  final Set<int> selected;
  final int? narrated;

  /// A passage someone was sent to: lit until they start selecting.
  final int? highlightStart;
  final int? highlightEnd;

  /// Highlights made before the highlighter existed, by colour.
  final Map<int, Color> legacy;
  final Map<int, String> notes;
  final ValueChanged<int> onVerseTap;
  final ValueChanged<int> onNoteTap;

  /// Lays the reader's ink over a block of text: (verses on it, where each
  /// one sits, the text).
  final Widget Function(
      List<int> verses, Rect? Function(int verse) rectOf, Widget child) ink;

  const ProseDecor({
    required this.selected,
    required this.narrated,
    required this.highlightStart,
    required this.highlightEnd,
    required this.legacy,
    required this.notes,
    required this.onVerseTap,
    required this.onNoteTap,
    required this.ink,
  });

  static const Color _selection = Color(0x3D2F4E86);
  static const Color _reading = Color(0x66E2BE62);
  static const Color _lit = Color(0x4DE2BE62);

  Color? washFor(int v) {
    if (selected.contains(v)) return _selection;
    if (narrated == v) return _reading;
    final s = highlightStart;
    if (s != null && v >= s && v <= (highlightEnd ?? s)) return _lit;
    final l = legacy[v];
    return l?.withValues(alpha: 0.32);
  }
}

/// The run of the chapter that falls on one page: on the opening page the
/// drop cap and the lines beside it, then a band of the chapter's lines.
class ProseView extends StatelessWidget {
  final TypesetChapter chapter;
  final int slice;
  final ProseDecor decor;

  /// The outer margin, for notes: left or right of the text.
  final bool notesOnLeft;

  const ProseView({
    super.key,
    required this.chapter,
    required this.slice,
    required this.decor,
    required this.notesOnLeft,
  });

  ProseSlice get _slice => chapter.slices[slice];
  bool get _opening => slice == 0 && chapter.lead != null;

  double get _leadBlock => _opening ? chapter.leadHeight : 0;

  /// Where verse [v] sits in this block, as boxes.
  List<Rect> boxes(int v) {
    final out = <Rect>[];
    if (_opening) {
      for (final r in chapter.leadBoxes(v)) {
        out.add(r.translate(chapter.capWidth, 0));
      }
    }
    for (final r in chapter.sliceBoxes(v, _slice)) {
      out.add(r.translate(0, _leadBlock));
    }
    return out;
  }

  Rect? _rectOf(int v) {
    final b = boxes(v);
    if (b.isEmpty) return null;
    return b.reduce((a, c) => a.expandToInclude(c));
  }

  List<int> get _verses {
    final first = _opening ? 1 : chapter.firstVerseOn(slice);
    final last = chapter.lastVerseOn(slice);
    return [for (var v = first; v <= math.max(first, last); v++) v];
  }

  int? _verseAt(Offset p) {
    if (_opening && p.dy < _leadBlock) {
      if (p.dx < chapter.capWidth) return 1;
      return chapter.verseInLead(p.translate(-chapter.capWidth, 0));
    }
    return chapter.verseInSlice(_slice, p.translate(0, -_leadBlock));
  }

  @override
  Widget build(BuildContext context) {
    final verses = _verses;
    final washesLead = <(Rect, Color)>[];
    final washesBody = <(Rect, Color)>[];
    final noteMarks = <(int, double)>[];
    for (final v in verses) {
      final c = decor.washFor(v);
      if (c != null) {
        if (_opening) {
          for (final r in chapter.leadBoxes(v)) {
            washesLead.add((r, c));
          }
        }
        for (final r in chapter.sliceBoxes(v, _slice)) {
          washesBody.add((r, c));
        }
      }
      if (decor.notes.containsKey(v)) {
        final b = boxes(v);
        if (b.isNotEmpty) noteMarks.add((v, b.first.top));
      }
    }

    final width = chapter.width;
    final height = _leadBlock + _slice.height;
    final cap = chapter.capPainter;

    final text = SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_opening && cap != null)
            Positioned(
              left: 0,
              top: -cap.height * 0.07,
              child: CustomPaint(
                size: Size(cap.width, cap.height),
                painter: _CapPainter(cap),
              ),
            ),
          if (_opening)
            Positioned(
              left: chapter.capWidth,
              top: 0,
              width: width - chapter.capWidth,
              height: _leadBlock,
              child: CustomPaint(
                painter: ParagraphBandPainter(
                  painter: chapter.lead!,
                  top: 0,
                  height: _leadBlock,
                  washes: washesLead,
                ),
              ),
            ),
          if (chapter.body != null && _slice.height > 0)
            Positioned(
              left: 0,
              top: _leadBlock,
              width: width,
              height: _slice.height,
              child: CustomPaint(
                painter: ParagraphBandPainter(
                  painter: chapter.body!,
                  top: _slice.top,
                  height: _slice.height,
                  washes: washesBody,
                ),
              ),
            ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final v = _verseAt(d.localPosition);
            if (v != null) decor.onVerseTap(v);
          },
          child: Semantics(
            container: true,
            label: [for (final v in verses) 'Verse $v'].join(', '),
            child: decor.ink(verses, _rectOf, text),
          ),
        ),
        // A note in the margin beside its verse: a small red pen.
        for (final (v, y) in noteMarks)
          Positioned(
            top: y - 10,
            left: notesOnLeft ? -34 : null,
            right: notesOnLeft ? null : -34,
            child: Semantics(
              button: true,
              label: 'Your note on verse $v',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => decor.onNoteTap(v),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(Icons.edit_outlined,
                        size: 14, color: BiblePalette.rubric),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CapPainter extends CustomPainter {
  final TextPainter cap;
  _CapPainter(this.cap);

  @override
  void paint(Canvas canvas, Size size) => cap.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_CapPainter old) => old.cap != cap;
}

/// The heading over a chapter's first page: an ornament (or, folded, the
/// chapter's plate let into the head of the page), the book and chapter in
/// spaced capitals, the chapter's title, and a printer's rule.
class ChapterHeading extends StatelessWidget {
  final String kicker;
  final String title;
  final String? vignette;
  final String? headpiece;
  final double headpieceHeight;
  final double titleSize;

  const ChapterHeading({
    super.key,
    required this.kicker,
    required this.title,
    this.vignette,
    this.headpiece,
    this.headpieceHeight = 0,
    this.titleSize = 38,
  });

  static const double vignetteHeight = 58;
  static const double _gapAfter = 20;

  static TextStyle titleStyle(double size) => TextStyle(
        fontFamily: BibleType.display,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: size,
        height: 1.05,
        color: BiblePalette.ink,
      );

  static const TextStyle kickerStyle = TextStyle(
    fontFamily: 'Spectral',
    fontSize: 10.5,
    height: 1.2,
    letterSpacing: 3.2,
    fontWeight: FontWeight.w600,
    color: BiblePalette.faint,
  );

  /// The height the heading takes at [width], so the page can be measured
  /// before it is built.
  static double measure({
    required double width,
    required String title,
    required String kicker,
    required bool hasVignette,
    required double headpieceHeight,
    required double titleSize,
  }) {
    final t = TextPainter(
      text: TextSpan(text: title, style: titleStyle(titleSize)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final k = TextPainter(
      text: TextSpan(text: kicker.toUpperCase(), style: kickerStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final h = (headpieceHeight > 0 ? headpieceHeight + 10 : 0) +
        (hasVignette ? vignetteHeight + 10 : 0) +
        k.height +
        10 +
        t.height +
        12 +
        12 +
        _gapAfter;
    t.dispose();
    k.dispose();
    return h;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (headpiece != null) ...[
          SizedBox(
            height: headpieceHeight,
            width: double.infinity,
            child: PlateImage(asset: headpiece!, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
        ],
        if (vignette != null) ...[
          SizedBox(
            height: vignetteHeight,
            child: PlateImage(asset: vignette!, fit: BoxFit.contain),
          ),
          const SizedBox(height: 10),
        ],
        Text(kicker.toUpperCase(),
            textAlign: TextAlign.center, style: kickerStyle),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: titleStyle(titleSize)),
        const SizedBox(height: 12),
        const Fleuron(color: BiblePalette.giltRule, size: 12),
        const SizedBox(height: _gapAfter),
      ],
    );
  }
}

/// A running head at the outer corner of a page, over a hairline.
class RunningHead extends StatelessWidget {
  final String text;
  final bool alignRight;

  const RunningHead({super.key, required this.text, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ChapterHeading.kickerStyle
                .copyWith(fontSize: 9.5, letterSpacing: 2.6)),
        const SizedBox(height: 6),
        Container(
            height: 0.7, color: BiblePalette.faint.withValues(alpha: 0.32)),
      ],
    );
  }
}

/// A folio: the page number, in old-style figures, at the foot.
class Folio extends StatelessWidget {
  final int number;
  const Folio(this.number, {super.key});

  @override
  Widget build(BuildContext context) => Text('$number',
      style: const TextStyle(
        fontFamily: 'Spectral',
        fontSize: 11,
        color: BiblePalette.faint,
        fontFeatures: [FontFeature.oldstyleFigures()],
      ));
}

/// A full page of art, with its caption: "Plate xiv", the verse it
/// illustrates in the open translation, and the reference.
class PlatePage extends StatelessWidget {
  final BiblePlate plate;
  final PageSide side;
  final String caption;
  final String reference;

  const PlatePage({
    super.key,
    required this.plate,
    required this.side,
    required this.caption,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    final m = PageMargins.inContext(context, side);
    return PaperPage(
      side: side,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.left - 8, 34 + m.top - PageMargins.head,
            m.right - 8, 28 + m.bottom - PageMargins.foot),
        child: Column(
          children: [
            Expanded(
              child: Semantics(
                image: true,
                label: 'Plate ${plate.numeral}: ${plate.title}',
                child: PlateImage(asset: plate.asset, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            Text('PLATE ${plate.numeral.toUpperCase()}',
                style: ChapterHeading.kickerStyle
                    .copyWith(fontSize: 9.5, color: BiblePalette.rubric)),
            const SizedBox(height: 6),
            Text(caption,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: BibleType.display,
                  fontStyle: FontStyle.italic,
                  fontVariations: [FontVariation('wght', 500)],
                  fontSize: 17,
                  height: 1.25,
                  color: Color(0xFF3A2E22),
                )),
            const SizedBox(height: 5),
            Text(reference,
                style: const TextStyle(
                  fontFamily: 'Spectral',
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  color: BiblePalette.faint,
                )),
          ],
        ),
      ),
    );
  }

  /// A caption short enough to sit under a plate: the verse, cut at a
  /// natural pause when it runs long.
  static String captionFor(String verse) {
    var v = verse.trim().replaceAllMapped(RegExp(r'\b(LORD|GOD)\b'),
        (m) => m.group(0)![0] + m.group(0)!.substring(1).toLowerCase());
    if (v.length <= 140) return v;
    final pause = RegExp(r'[;:]|, and ').allMatches(v);
    for (final m in pause) {
      if (m.start >= 40 && m.start <= 140) {
        return '${v.substring(0, m.start).trimRight()}…';
      }
    }
    final cut = v.lastIndexOf(' ', 140);
    return '${v.substring(0, cut < 40 ? 140 : cut).trimRight()}…';
  }
}

/// The page after a chapter's last, set the way a printed book closes one
/// part and points to the next: a tailpiece, a colophon, and at the foot a
/// catchword, the heading of what follows, so the page is a page of the
/// book rather than an empty one. Turning it opens the next chapter.
class ChapterEndPage extends StatelessWidget {
  final PageSide side;

  /// "Genesis · Chapter Four"
  final String kicker;

  /// "Here endeth chapter four." / "Here endeth the Book of Genesis."
  final String closing;
  final String? vignette;

  /// What comes next: its kicker ("Genesis · Chapter Five") and title.
  final String? nextKicker;
  final String? nextTitle;
  final VoidCallback? onNext;
  final int folio;

  const ChapterEndPage({
    super.key,
    required this.side,
    required this.kicker,
    required this.closing,
    required this.folio,
    this.vignette,
    this.nextKicker,
    this.nextTitle,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final m = PageMargins.inContext(context, side);
    final hasNext = onNext != null && nextTitle != null;
    return PaperPage(
      side: side,
      child: Stack(
        children: [
          Positioned(
            left: m.left,
            right: m.right,
            top: m.top,
            bottom: m.bottom,
            child: LayoutBuilder(builder: (context, box) {
              final art = math.min(box.maxHeight * 0.30, 170.0);
              return Column(
                children: [
                  const Spacer(flex: 3),
                  if (vignette != null)
                    SizedBox(
                        height: art,
                        child:
                            PlateImage(asset: vignette!, fit: BoxFit.contain))
                  else
                    const Fleuron(color: BiblePalette.giltRule, size: 18),
                  const SizedBox(height: 22),
                  Text(kicker.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: ChapterHeading.kickerStyle),
                  const SizedBox(height: 10),
                  Text(closing,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: BibleType.display,
                        fontStyle: FontStyle.italic,
                        fontVariations: [FontVariation('wght', 500)],
                        fontSize: 22,
                        height: 1.2,
                        color: BiblePalette.inkSoft,
                      )),
                  const SizedBox(height: 16),
                  const _GiltRule(),
                  const Spacer(flex: 4),
                  if (hasNext)
                    Semantics(
                      button: true,
                      label: 'Turn to $nextKicker, $nextTitle',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onNext,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(nextKicker!.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: ChapterHeading.kickerStyle.copyWith(
                                      fontSize: 9.5,
                                      color: BiblePalette.rubric)),
                              const SizedBox(height: 6),
                              Text(nextTitle!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: ChapterHeading.titleStyle(24)),
                              const SizedBox(height: 8),
                              const Text('Turn the page  ›',
                                  style: TextStyle(
                                    fontFamily: BibleType.display,
                                    fontStyle: FontStyle.italic,
                                    fontVariations: [
                                      FontVariation('wght', 500)
                                    ],
                                    fontSize: 16,
                                    color: BiblePalette.faint,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              );
            }),
          ),
          Positioned(
            bottom: 16 + m.bottom - PageMargins.foot,
            left: side == PageSide.left ? m.left : null,
            right: side == PageSide.left ? null : m.right,
            child: Folio(folio),
          ),
        ],
      ),
    );
  }
}

/// A short gilt rule with a lozenge at its centre.
class _GiltRule extends StatelessWidget {
  const _GiltRule();

  @override
  Widget build(BuildContext context) {
    final line = Container(
        width: 46,
        height: 0.8,
        color: BiblePalette.giltRule.withValues(alpha: 0.7));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        const SizedBox(width: 8),
        const Fleuron(color: BiblePalette.giltRule, size: 9),
        const SizedBox(width: 8),
        line,
      ],
    );
  }
}

/// Art printed on the page: drawn with a multiply blend, so the white of
/// the artwork becomes the paper it lies on and only the ink and wash show.
class PlateImage extends StatefulWidget {
  final String asset;
  final BoxFit fit;

  const PlateImage({super.key, required this.asset, this.fit = BoxFit.contain});

  @override
  State<PlateImage> createState() => _PlateImageState();
}

class _PlateImageState extends State<PlateImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _info?.dispose();
      _info = info;
    });
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PlateImage old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final stream = AssetImage(widget.asset)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _MultiplyPainter(_info?.image, widget.fit),
        size: Size.infinite,
      );
}

class _MultiplyPainter extends CustomPainter {
  final ui.Image? image;
  final BoxFit fit;
  _MultiplyPainter(this.image, this.fit);

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || size.isEmpty) return;
    final src = Size(img.width.toDouble(), img.height.toDouble());
    final fitted = applyBoxFit(fit, src, size);
    final dst =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final from = Alignment.center.inscribe(fitted.source, Offset.zero & src);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      img,
      from,
      dst,
      Paint()
        ..blendMode = BlendMode.multiply
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MultiplyPainter old) =>
      old.image != image || old.fit != fit;
}

/// Decode the plates a chapter will show before its pages are turned to, so
/// the art is on the paper when the leaf lifts.
Future<void> precacheChapterArt(
        BuildContext context, Iterable<String> assets) =>
    Future.wait([
      for (final a in assets)
        precacheImage(AssetImage(a), context).catchError((_) {}),
    ]);

/// Sizes of the reader's type and headings for a page [width] wide.
BibleType bibleTypeFor(double width, TextScaler scaler) => BibleType(
      fontSize: width < 380 ? 15.0 : 15.5,
      lineHeight: 1.5,
      scaler: scaler,
    );
