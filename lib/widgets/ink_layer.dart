import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bible_marks.dart';

/// What the hand is holding.
enum InkTool { off, pen, marker, eraser }

/// Pen and highlighter over a run of verses.
///
/// Wraps a page (or a whole scrolling chapter). Off, it is invisible to
/// touch and only paints what is already there. With the pen or the
/// highlighter a drag draws; with the eraser, a drag removes whatever
/// stroke it passes through.
///
/// Highlighter goes under the words and pen over them, as on paper: a
/// marker never dims the text it marks.
///
/// Every stroke belongs to the verse it was started on and is stored in
/// that verse's own coordinates (see [InkStroke]), so drawing happens in
/// page space but is converted the moment the pen lifts.
class InkLayer extends StatefulWidget {
  final int book;
  final int chapter;

  /// The verses laid out under this layer.
  final List<int> verses;

  /// Keys on the verse rows, to find where each one sits.
  final Map<int, GlobalKey> verseKeys;

  final InkTool tool;

  /// Index into [MarkColors.ink] for the pen, [MarkColors.markers] for the
  /// highlighter.
  final int inkColor;
  final int markerColor;
  final Widget child;

  const InkLayer({
    super.key,
    required this.book,
    required this.chapter,
    required this.verses,
    required this.verseKeys,
    required this.tool,
    required this.inkColor,
    this.markerColor = 0,
    required this.child,
  });

  /// Width of the highlighter's tip: about one line of text.
  static const double markerWidth = 21;

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  final GlobalKey _box = GlobalKey();
  final ValueNotifier<List<Offset>> _live = ValueNotifier(const []);

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  RenderBox? get _layer =>
      _box.currentContext?.findRenderObject() as RenderBox?;

  /// Where verse [v] sits in this layer, or null if it is not laid out here.
  Rect? _rectOf(int v) {
    final layer = _layer;
    final ro = widget.verseKeys[v]?.currentContext?.findRenderObject();
    if (layer == null || ro is! RenderBox || !ro.attached || !ro.hasSize) {
      return null;
    }
    try {
      return ro.localToGlobal(Offset.zero, ancestor: layer) & ro.size;
    } catch (_) {
      return null;
    }
  }

  List<InkStroke> _strokes({required bool markers}) {
    final on = widget.verses.toSet();
    return BibleMarks.instance
        .chapter(widget.book, widget.chapter)
        .ink
        .where((s) => on.contains(s.verse) && s.marker == markers)
        .toList();
  }

  bool get _drawing =>
      widget.tool == InkTool.pen || widget.tool == InkTool.marker;

  // ---- Drawing ----

  void _start(Offset p) {
    if (widget.tool == InkTool.eraser) return _erase(p);
    _live.value = [p];
  }

  void _move(Offset p) {
    if (widget.tool == InkTool.eraser) return _erase(p);
    _live.value = [..._live.value, p];
  }

  Future<void> _end() async {
    var points = _live.value;
    _live.value = const [];
    if (!_drawing || points.length < 2) return;
    final marker = widget.tool == InkTool.marker;
    if (marker) points = steady(points);

    // The verse the stroke began on, or failing that the nearest one: a
    // margin mark beside a verse belongs to that verse.
    int? verse;
    Rect? rect;
    var best = double.infinity;
    for (final v in widget.verses) {
      final r = _rectOf(v);
      if (r == null) continue;
      if (r.contains(points.first)) {
        verse = v;
        rect = r;
        break;
      }
      final d = (r.center.dy - points.first.dy).abs();
      if (d < best) {
        best = d;
        verse = v;
        rect = r;
      }
    }
    if (verse == null || rect == null || rect.width == 0 || rect.height == 0) {
      return;
    }
    final r = rect;
    HapticFeedback.lightImpact();
    await BibleMarks.instance.addStroke(
      widget.book,
      widget.chapter,
      InkStroke(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        verse: verse,
        color: marker ? widget.markerColor : widget.inkColor,
        marker: marker,
        width: marker ? InkLayer.markerWidth : 2.0,
        points: [
          for (final p in points)
            Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height),
        ],
      ),
    );
  }

  /// A hand drawing a highlighter along a line wobbles; the ink should not.
  /// A stroke that stays within a line's height is laid flat at its median
  /// height, the way the chisel tip rides the line. One that moves further
  /// (marking down a margin, circling) is left as drawn.
  static List<Offset> steady(List<Offset> pts) => steadyMarkerLine(pts);

  void _erase(Offset p) {
    for (final markers in [false, true]) {
      for (final s in _strokes(markers: markers)) {
        final r = _rectOf(s.verse);
        if (r == null) continue;
        final pts = [
          for (final q in s.points)
            Offset(r.left + q.dx * r.width, r.top + q.dy * r.height)
        ];
        if (_near(pts, p, s.marker ? s.width / 2 + 8 : 18)) {
          HapticFeedback.selectionClick();
          BibleMarks.instance.removeStroke(widget.book, widget.chapter, s.id);
          return;
        }
      }
    }
  }

  /// Whether [p] is within [reach] of the polyline [pts], segments included:
  /// a straightened highlighter is only two points, a whole line apart.
  static bool _near(List<Offset> pts, Offset p, double reach) {
    if (pts.length == 1) return (pts.first - p).distance < reach;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0
          ? 0.0
          : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      if ((a + ab * t - p).distance < reach) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.tool != InkTool.off;
    final repaint = Listenable.merge([BibleMarks.instance, _live]);
    return Stack(
      key: _box,
      children: [
        // Under the words: highlighter.
        Positioned.fill(
          child: CustomPaint(
            painter: _InkPainter(
              strokes: () => _strokes(markers: true),
              rectOf: _rectOf,
              live: _live,
              showLive: widget.tool == InkTool.marker,
              liveIsMarker: true,
              liveColor: MarkColors
                  .markers[widget.markerColor % MarkColors.markers.length],
              repaint: repaint,
            ),
          ),
        ),
        Align(alignment: Alignment.topLeft, child: widget.child),
        // Over the words: pen, and the hand that draws both.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !active,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _start(d.localPosition),
              onPanUpdate: (d) => _move(d.localPosition),
              onPanEnd: (_) => _end(),
              onTapUp: widget.tool == InkTool.eraser
                  ? (d) => _erase(d.localPosition)
                  : null,
              child: CustomPaint(
                painter: _InkPainter(
                  strokes: () => _strokes(markers: false),
                  rectOf: _rectOf,
                  live: _live,
                  showLive: widget.tool == InkTool.pen,
                  liveIsMarker: false,
                  liveColor:
                      MarkColors.ink[widget.inkColor % MarkColors.ink.length],
                  repaint: repaint,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InkPainter extends CustomPainter {
  final List<InkStroke> Function() strokes;
  final Rect? Function(int verse) rectOf;
  final ValueNotifier<List<Offset>> live;
  final bool showLive;
  final bool liveIsMarker;
  final Color liveColor;

  _InkPainter({
    required this.strokes,
    required this.rectOf,
    required this.live,
    required this.showLive,
    required this.liveIsMarker,
    required this.liveColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes()) {
      final r = rectOf(s.verse);
      if (r == null) continue;
      final pts = [
        for (final q in s.points)
          Offset(r.left + q.dx * r.width, r.top + q.dy * r.height)
      ];
      if (s.marker) {
        marker(canvas, pts,
            MarkColors.markers[s.color % MarkColors.markers.length], s.width);
      } else {
        pen(canvas, pts, MarkColors.ink[s.color % MarkColors.ink.length],
            s.width);
      }
    }
    final points = live.value;
    if (showLive && points.length > 1) {
      if (liveIsMarker) {
        marker(canvas, points, liveColor, InkLayer.markerWidth);
      } else {
        pen(canvas, points, liveColor, 2.0);
      }
    }
  }

  static Path _smooth(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset.lerp(pts[i], pts[i + 1], 0.5)!;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  /// A smooth line through the samples: quadratic curves between midpoints,
  /// so a quick underline does not come out as a row of straight segments.
  static void pen(Canvas canvas, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final path = _smooth(pts);
    // Ink spreads a little into the fibres either side of the nib.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width * 1.9
        ..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.9),
    );
  }

  /// A chisel-tip highlighter: flat ends, translucent, a little denser
  /// along its edges where the felt presses hardest.
  static void marker(
      Canvas canvas, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final path = _smooth(pts);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.42),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width * 0.72
        ..color = color.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      old.liveColor != liveColor ||
      old.rectOf != rectOf ||
      old.showLive != showLive;
}

/// A hand drawing a highlighter along a line wobbles; the ink should not.
/// A stroke that stays within a line's height is laid flat at its median
/// height, the way the chisel tip rides the line. One that moves further
/// (marking down a margin, circling) is left as drawn.
List<Offset> steadyMarkerLine(List<Offset> pts) {
  var top = double.infinity, bottom = -double.infinity;
  for (final p in pts) {
    if (p.dy < top) top = p.dy;
    if (p.dy > bottom) bottom = p.dy;
  }
  if (bottom - top > InkLayer.markerWidth * 0.9) return pts;
  final ys = [for (final p in pts) p.dy]..sort();
  final y = ys[ys.length ~/ 2];
  var left = double.infinity, right = -double.infinity;
  for (final p in pts) {
    if (p.dx < left) left = p.dx;
    if (p.dx > right) right = p.dx;
  }
  // Keep the direction it was drawn in; only its height is evened out.
  return pts.first.dx <= pts.last.dx
      ? [Offset(left, y), Offset(right, y)]
      : [Offset(right, y), Offset(left, y)];
}
