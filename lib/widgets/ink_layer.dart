import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bible_marks.dart';

/// What the pen is doing.
enum InkTool { off, pen, eraser }

/// Pen ink over a run of verses.
///
/// Wraps a page (or a whole scrolling chapter). Off, it is invisible to
/// touch and only paints what is already there. With the pen, a drag draws;
/// with the eraser, a drag removes whatever stroke it passes through.
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
  final int inkColor;
  final Widget child;

  const InkLayer({
    super.key,
    required this.book,
    required this.chapter,
    required this.verses,
    required this.verseKeys,
    required this.tool,
    required this.inkColor,
    required this.child,
  });

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

  RenderBox? get _layer => _box.currentContext?.findRenderObject() as RenderBox?;

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

  List<InkStroke> get _strokes {
    final on = widget.verses.toSet();
    return BibleMarks.instance
        .chapter(widget.book, widget.chapter)
        .ink
        .where((s) => on.contains(s.verse))
        .toList();
  }

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
    final points = _live.value;
    _live.value = const [];
    if (widget.tool != InkTool.pen || points.length < 2) return;

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
    await BibleMarks.instance.addStroke(
      widget.book,
      widget.chapter,
      InkStroke(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        verse: verse,
        color: widget.inkColor,
        points: [
          for (final p in points)
            Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height),
        ],
      ),
    );
  }

  void _erase(Offset p) {
    for (final s in _strokes) {
      final r = _rectOf(s.verse);
      if (r == null) continue;
      for (final q in s.points) {
        final at = Offset(r.left + q.dx * r.width, r.top + q.dy * r.height);
        if ((at - p).distance < 18) {
          HapticFeedback.selectionClick();
          BibleMarks.instance.removeStroke(widget.book, widget.chapter, s.id);
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawing = widget.tool != InkTool.off;
    return Stack(
      key: _box,
      children: [
        Align(alignment: Alignment.topLeft, child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !drawing,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _start(d.localPosition),
              onPanUpdate: (d) => _move(d.localPosition),
              onPanEnd: (_) => _end(),
              onTapUp: widget.tool == InkTool.eraser
                  ? (d) => _erase(d.localPosition)
                  : null,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _InkPainter(
                    strokes: () => _strokes,
                    rectOf: _rectOf,
                    live: _live,
                    liveColor: MarkColors.ink[widget.inkColor],
                    repaint:
                        Listenable.merge([BibleMarks.instance, _live]),
                  ),
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
  final Color liveColor;

  _InkPainter({
    required this.strokes,
    required this.rectOf,
    required this.live,
    required this.liveColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes()) {
      final r = rectOf(s.verse);
      if (r == null) continue;
      _stroke(
        canvas,
        [
          for (final q in s.points)
            Offset(r.left + q.dx * r.width, r.top + q.dy * r.height)
        ],
        MarkColors.ink[s.color.clamp(0, MarkColors.ink.length - 1)],
        s.width,
      );
    }
    final points = live.value;
    if (points.length > 1) _stroke(canvas, points, liveColor, 2.4);
  }

  /// A smooth line through the samples: quadratic curves between midpoints,
  /// so a quick underline does not come out as a row of straight segments.
  static void _stroke(
      Canvas canvas, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset.lerp(pts[i], pts[i + 1], 0.5)!;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    // A soft halo under the line, the way ink sits in paper.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width * 3
        ..color = color.withValues(alpha: 0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = color.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      old.liveColor != liveColor || old.rectOf != rectOf;
}
