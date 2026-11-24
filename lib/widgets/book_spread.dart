import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A book whose pages really turn.
///
/// Unfolded (two pages a view) the Duo is an open book held in two hands,
/// and its fold runs exactly where a book's spine would. Folded (one page a
/// view) the spine is the left edge of the screen.
///
/// A turning page is not a flat card rotating about the spine. It curls:
/// the free edge lifts first, the paper wraps over a cylinder that rolls
/// toward the spine, and past the roll the back of the leaf comes down
/// over the facing page. The leaf is a mesh, textured with a picture of the
/// page taken while it lay flat, so the words curl with the paper. Where
/// the finger took hold tilts the roll, so a page lifted by its bottom
/// corner turns from the corner. Lambert shading on the mesh and a cast
/// shadow on the page underneath do the rest.
///
/// Gestures are owned here: taps fall through to the pages at rest, so
/// verses stay selectable; while a leaf is moving the pages ignore pointers.
class BookSpread extends StatefulWidget {
  /// Number of pages. The view count is ceil(pageCount / pagesPerView).
  final int pageCount;

  /// The view to show (a spread, or with one page a view, a page). Changing
  /// it from outside turns to it (one away) or jumps (further).
  final int spread;

  /// Builds page [index]; past the last page, [blankBuilder] is used.
  final Widget Function(BuildContext context, int index) pageBuilder;
  final WidgetBuilder blankBuilder;

  /// Called when a turn settles on a new view.
  final ValueChanged<int> onSpreadChanged;

  /// Turning forward from the last view (a swipe or a tap at the fore-edge)
  /// calls this, so the book reads on into whatever follows.
  final VoidCallback? onTurnPastEnd;

  /// Turning back from the first view: the book reads back into the one
  /// before it.
  final VoidCallback? onTurnBeforeStart;

  /// True to skip the turning animation (Reduce Motion).
  final bool reduceMotion;

  /// False while the page is being drawn on: a drag is then a pen stroke,
  /// and must not turn the page under it.
  final bool interactive;

  /// 2 for facing pages, 1 for a single page.
  final int pagesPerView;

  /// Changes whenever what is printed on the pages changes (chapter, ink,
  /// selection), so the pictures the curl is textured with are retaken.
  final Object? revision;

  /// The colour of the back of a leaf when there is no facing page to show
  /// through it (one page a view).
  final Color paperColor;

  const BookSpread({
    super.key,
    required this.pageCount,
    required this.spread,
    required this.pageBuilder,
    required this.blankBuilder,
    required this.onSpreadChanged,
    this.reduceMotion = false,
    this.onTurnPastEnd,
    this.onTurnBeforeStart,
    this.interactive = true,
    this.pagesPerView = 2,
    this.revision,
    this.paperColor = const Color(0xFFF3EBDA),
  });

  static int spreadCountFor(int pages, [int perView = 2]) =>
      math.max(1, (pages + perView - 1) ~/ perView);

  @override
  State<BookSpread> createState() => _BookSpreadState();
}

class _BookSpreadState extends State<BookSpread>
    with SingleTickerProviderStateMixin {
  /// Position in views: 2.0 is resting on view 2, 2.4 is 40% through
  /// turning from 2 to 3.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.spread.toDouble(),
  );

  double _pageWidth = 1;
  double _pageHeight = 1;

  /// Where on the page's height the finger took hold, 0 top to 1 bottom.
  double _grab = 0.8;

  int get _per => widget.pagesPerView.clamp(1, 2);
  int get _viewCount => BookSpread.spreadCountFor(widget.pageCount, _per);

  // ---- Pictures of the pages, for the curl ----

  final Map<int, GlobalKey> _slotKeys = {};
  final Map<int, ui.Image> _pictures = {};
  Object? _picturesFor;
  bool _captureQueued = false;

  GlobalKey _slotKey(int index) =>
      _slotKeys.putIfAbsent(index, () => GlobalKey(debugLabel: 'page $index'));

  void _forgetPictures() {
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
  }

  /// Pages whose picture a turn starting from here would need.
  Iterable<int> _wanted(int base, bool turning) sync* {
    if (_per == 2) {
      if (turning) {
        yield base * 2 + 1;
        yield base * 2 + 2;
      } else {
        yield base * 2 - 1;
        yield base * 2;
        yield base * 2 + 1;
        yield base * 2 + 2;
      }
    } else {
      yield base;
      if (!turning) yield base - 1;
    }
  }

  void _queueCapture(Iterable<int> pages) {
    if (_captureQueued) return;
    final missing = pages.where((i) => !_pictures.containsKey(i)).toList();
    if (missing.isEmpty) return;
    _captureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureQueued = false;
      if (!mounted) return;
      final ratio =
          math.min(3.0, MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0);
      for (final i in missing) {
        if (_pictures.containsKey(i)) continue;
        final ro = _slotKeys[i]?.currentContext?.findRenderObject();
        if (ro is! RenderRepaintBoundary || !ro.attached || !ro.hasSize) {
          continue;
        }
        if (kDebugMode && ro.debugNeedsPaint) continue;
        try {
          _pictures[i] = ro.toImageSync(pixelRatio: ratio);
        } catch (_) {/* a missing picture falls back to plain paper */}
      }
    });
  }

  @override
  void didUpdateWidget(BookSpread old) {
    super.didUpdateWidget(old);
    final target = widget.spread.clamp(0, _viewCount - 1);
    if ((_pos.value - target).abs() < 0.001 && !_pos.isAnimating) return;
    if (_pos.isAnimating) return; // a turn in flight will settle itself
    if ((target - _pos.value).abs() <= 1.01 && !widget.reduceMotion) {
      _grab = 0.8;
      _settleTo(target, velocity: 0);
    } else {
      _pos.value = target.toDouble();
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    _forgetPictures();
    super.dispose();
  }

  // ---- Gesture ----

  /// Where the drag began, in views, and how far the finger has gone since.
  double _dragFrom = 0;
  double _dragDx = 0;
  double _spineX = 0;
  double _cameraX = 0;

  void _onDragStart(DragStartDetails d, double height) {
    _pos.stop();
    _grab = height <= 0 ? 0.8 : (d.localPosition.dy / height).clamp(0.0, 1.0);
    _dragFrom = _pos.value;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragDx += d.primaryDelta!;
    _pos.value = _positionForDrag();
  }

  /// The turn that puts the leaf's free edge under the finger.
  ///
  /// The edge does not travel linearly with the turn (it rises toward the
  /// reader, then falls), so a fixed pixels-per-turn ratio would make the
  /// page slide under the finger. Instead the edge's projected position is
  /// inverted: find the t at which it is where the finger is.
  double _positionForDrag() {
    final max = (_viewCount - 1).toDouble();
    final from = _dragFrom.clamp(0.0, max);
    var base = from.floorToDouble();
    var t0 = from - base;
    // From rest, the direction of the drag picks the leaf: leftward lifts
    // the right-hand page, rightward brings the left-hand one back.
    if (t0 < 0.0005 && _dragDx > 0) {
      if (base <= 0) return -_dragDx / (_pageWidth * 8); // the front cover
      base -= 1;
      t0 = 1;
    }
    if (t0 < 0.0005 && _dragDx < 0 && base >= max) {
      return max - _dragDx / (_pageWidth * 8); // the last page
    }
    final page = Size(_pageWidth, _pageHeight);
    double edge(double t) => PageCurlPainter.edgeAt(
        t: t, page: page, spine: _spineX, cameraX: _cameraX, projected: false);
    final target = edge(t0) + _dragDx;
    // The edge moves from the fore-edge to the far side as t goes 0 to 1.
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 28; i++) {
      final mid = (lo + hi) / 2;
      if (edge(mid) > target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return base + (lo + hi) / 2;
  }

  void _onDragEnd(DragEndDetails d) {
    // About two page widths of finger travel make a whole turn.
    final velocity = -(d.primaryVelocity ?? 0) / (_pageWidth * 1.7);
    final last = (_viewCount - 1).toDouble();
    if (_dragFrom >= last - 0.0005 &&
        widget.onTurnPastEnd != null &&
        (_pos.value - last > 0.04 || (velocity > 0.45 && _pos.value > last))) {
      _settleTo(last.round(), velocity: 0);
      widget.onTurnPastEnd!();
      return;
    }
    if (_dragFrom <= 0.0005 &&
        widget.onTurnBeforeStart != null &&
        (_pos.value < -0.04 || (velocity < -0.45 && _pos.value < 0))) {
      _settleTo(0, velocity: 0);
      widget.onTurnBeforeStart!();
      return;
    }
    final base = _pos.value.floorToDouble();
    final frac = _pos.value - base;
    double target;
    if (velocity.abs() > 0.45) {
      target = velocity > 0 ? base + 1 : base;
    } else {
      target = frac > 0.5 ? base + 1 : base;
    }
    target = target.clamp(0, (_viewCount - 1).toDouble());
    _settleTo(target.round(), velocity: velocity);
  }

  /// Turn one view forward or back, as a tap in the margin does.
  void turn(int direction) {
    if (direction > 0 &&
        _pos.value.round() >= _viewCount - 1 &&
        !_pos.isAnimating &&
        widget.onTurnPastEnd != null) {
      widget.onTurnPastEnd!();
      return;
    }
    if (direction < 0 &&
        _pos.value.round() <= 0 &&
        !_pos.isAnimating &&
        widget.onTurnBeforeStart != null) {
      widget.onTurnBeforeStart!();
      return;
    }
    final target = (_pos.value.round() + direction).clamp(0, _viewCount - 1);
    if (target == _pos.value.round() && !_pos.isAnimating) return;
    _grab = 0.72;
    _settleTo(target, velocity: direction * 0.6);
  }

  void _settleTo(int target, {required double velocity}) {
    final from = _pos.value.round();
    if (widget.reduceMotion) {
      _pos.value = target.toDouble();
      if (target != from || target != widget.spread) _commit(target);
      return;
    }
    // A heavy, well-damped spring: paper has mass and settles, it does not
    // bounce.
    final sim = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 110, damping: 21),
      _pos.value,
      target.toDouble(),
      velocity,
    );
    _pos.animateWith(sim).whenCompleteOrCancel(() {
      if (!mounted) return;
      if (_pos.isAnimating) return;
      _pos.value = target.toDouble();
      _commit(target);
    });
  }

  void _commit(int target) {
    if (target != widget.spread) {
      HapticFeedback.selectionClick();
      widget.onSpreadChanged(target);
    }
  }

  // ---- Build ----

  Widget _page(BuildContext context, int index) =>
      index >= 0 && index < widget.pageCount
          ? widget.pageBuilder(context, index)
          : widget.blankBuilder(context);

  /// A page in its own layer, so it can be photographed for the curl.
  Widget _slot(BuildContext context, int index,
      {required int column, bool hidden = false}) {
    Widget child = RepaintBoundary(
      key: _slotKey(index),
      child: _page(context, index),
    );
    if (hidden) {
      child = IgnorePointer(child: ExcludeSemantics(child: child));
    }
    return Positioned(
      key: ValueKey('slot $index'),
      left: column * _pageWidth,
      top: 0,
      bottom: 0,
      width: _pageWidth,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_picturesFor != widget.revision) {
      _picturesFor = widget.revision;
      _forgetPictures();
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth / _per;
      if ((width - _pageWidth).abs() > 0.5) _forgetPictures();
      _pageWidth = width;
      final height = constraints.maxHeight;
      _pageHeight = height;
      _spineX = _per == 2 ? width : 0;
      _cameraX = constraints.maxWidth / 2;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart:
            widget.interactive ? (d) => _onDragStart(d, height) : null,
        onHorizontalDragUpdate: widget.interactive ? _onDragUpdate : null,
        onHorizontalDragEnd: widget.interactive ? _onDragEnd : null,
        // A tap in the outer margins turns the page, as a thumb at the
        // edge of a book does. Taps on the words are the page's own.
        onTapUp: widget.interactive
            ? (d) {
                final x = d.localPosition.dx / constraints.maxWidth;
                if (x > 0.84) turn(1);
                if (x < 0.16) turn(-1);
              }
            : null,
        child: AnimatedBuilder(
          animation: _pos,
          builder: (context, _) =>
              _viewAt(context, _pos.value, Size(width, height)),
        ),
      );
    });
  }

  Widget _viewAt(BuildContext context, double position, Size page) {
    final clamped = position.clamp(0.0, (_viewCount - 1).toDouble());
    final base = clamped.floor();
    final t = clamped - base;
    final turning = t >= 0.0005;
    _queueCapture(_wanted(base, turning));

    if (!turning) {
      // Resting: plain, fully interactive pages, with the neighbours a turn
      // would need laid underneath them (covered, but painted, so their
      // pictures are ready before the finger moves).
      return Stack(
        fit: StackFit.expand,
        children: _per == 2
            ? [
                if (base > 0)
                  _slot(context, base * 2 - 1, column: 1, hidden: true),
                _slot(context, base * 2 + 2, column: 0, hidden: true),
                _slot(context, base * 2, column: 0),
                _slot(context, base * 2 + 1, column: 1),
              ]
            : [
                if (base > 0) _slot(context, base - 1, column: 0, hidden: true),
                _slot(context, base, column: 0),
              ],
      );
    }

    final front = _pictures[_per == 2 ? base * 2 + 1 : base];
    final back = _per == 2 ? _pictures[base * 2 + 2] : null;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The leaf's own pages, kept painted under everything in case
          // their pictures have not been taken yet.
          if (_per == 2) ...[
            _slot(context, base * 2 + 1, column: 1, hidden: true),
            _slot(context, base * 2 + 2, column: 0, hidden: true),
            _slot(context, base * 2, column: 0),
            _slot(context, base * 2 + 3, column: 1),
          ] else ...[
            _slot(context, base, column: 0, hidden: true),
            _slot(context, base + 1, column: 0),
          ],
          Positioned.fill(
            child: CustomPaint(
              painter: PageCurlPainter(
                t: t,
                grab: _grab,
                spine: _per == 2 ? page.width : 0,
                cameraX: _per == 2 ? page.width : page.width / 2,
                page: page,
                front: front,
                back: back,
                paper: widget.paperColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints one leaf part-way through a turn, and what it throws on the pages
/// beneath it.
///
/// The leaf is hinged at [spine] and lies to its right. As [t] runs from 0
/// (flat, unturned) to 1 (flat on the other side), the paper lifts toward
/// the reader and arches over: the free edge leads and the part by the
/// spine follows, so mid-turn the page stands in an arch rather than as a
/// flat card. Each row of the mesh is bent the same way, except that a page
/// taken by a corner turns from that corner first ([grab]).
///
/// The bent sheet is projected through a camera above [cameraX] (the
/// spine when two pages are open), so the leaf grows as it comes up off
/// the book, the way a page does in the hand.
@visibleForTesting
class PageCurlPainter extends CustomPainter {
  final double t;
  final double grab;
  final double spine;
  final double cameraX;
  final Size page;
  final ui.Image? front;
  final ui.Image? back;
  final Color paper;

  PageCurlPainter({
    required this.t,
    required this.grab,
    required this.spine,
    double? cameraX,
    required this.page,
    required this.front,
    required this.back,
    required this.paper,
  }) : cameraX = cameraX ?? spine;

  static const int _cols = 40;
  static const int _rows = 18;

  /// The camera's height above the book, in page widths.
  static const double _focal = 5.0;

  /// How far the free edge leads the spine side, at its most. Large, so the
  /// half by the spine stays low while the outer half curls over: seen from
  /// above, most of the page's face stays readable through the turn,
  /// instead of the leaf standing up edge-on like a card.
  static const double _lead = 1.0 * math.pi;

  /// The paper's angle at fraction [u] of the way from spine to edge, for a
  /// row at turn [t]: 0 lies flat on the right, pi flat on the left.
  static double angleAt(double t, double u) {
    final lift = math.sin(math.pi * t.clamp(0.0, 1.0));
    final lead = _lead * lift;
    final base = math.pi * t - lead / 2;
    final edge = math.pi * t + lead / 2;
    return (base + (edge - base) * math.pow(u, 2.6)).clamp(0.0, math.pi);
  }

  /// Where the free edge is at turn [t] (along the middle row).
  ///
  /// [projected] gives where it appears on screen. For following the finger
  /// the flat position is used instead: it moves steadily from one side to
  /// the other, where the projected one first swells outward as the edge
  /// lifts toward the reader, which would make the leaf stutter under the
  /// finger at the start of a turn.
  static double edgeAt({
    required double t,
    required Size page,
    required double spine,
    required double cameraX,
    bool projected = true,
  }) {
    final w = page.width;
    var x = 0.0, z = 0.0;
    for (var i = 0; i < _cols; i++) {
      final a = angleAt(t, (i + 0.5) / _cols);
      x += w / _cols * math.cos(a);
      z += w / _cols * math.sin(a);
    }
    if (!projected) return spine + x;
    final f = w * _focal;
    return cameraX + (spine + x - cameraX) * f / (f - z);
  }

  /// The turn as the row at fraction [v] of the height feels it: taken by a
  /// corner, the rows nearer that corner are further on.
  double _rowT(double v) {
    final lift = math.sin(math.pi * t);
    return (t + 0.11 * lift * (grab - 0.5) * 2 * (v - 0.5) * 2).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = page.width;
    final h = page.height;
    if (w <= 0 || h <= 0) return;
    final lift = math.sin(math.pi * t);
    final f = w * _focal;

    const n = (_cols + 1) * (_rows + 1);
    final pos = Float32List(n * 2);
    final texFront = Float32List(n * 2);
    final texBack = Float32List(n * 2);
    final colFront = Int32List(n);
    final colBack = Int32List(n);

    // Light from above the reader's shoulder, a little from the left.
    const lx = -0.30, ly = -0.22, lz = 1.0;
    final ll = math.sqrt(lx * lx + ly * ly + lz * lz);

    var minX = double.infinity, maxX = -double.infinity;
    for (var j = 0; j <= _rows; j++) {
      final v = j / _rows;
      final rowT = _rowT(v);
      final y = h * v;
      var x = 0.0, z = 0.0;
      for (var i = 0; i <= _cols; i++) {
        final k = j * (_cols + 1) + i;
        final a = angleAt(rowT, i / _cols);
        final s = f / (f - z);
        final px = cameraX + (spine + x - cameraX) * s;
        pos[k * 2] = px;
        pos[k * 2 + 1] = h / 2 + (y - h / 2) * s;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        final u = w * i / _cols;
        texFront[k * 2] = u;
        texFront[k * 2 + 1] = y;
        texBack[k * 2] = w - u;
        texBack[k * 2 + 1] = y;
        // The face's normal, lit: the front faces the reader at 0 and turns
        // away past a right angle; the back does the opposite.
        final nx = -math.sin(a), nz = math.cos(a);
        final d = (nx * lx + nz * lz) / ll;
        final sheen = math.exp(-math.pow(a - 0.95, 2) / 0.05) * 0.08 * lift;
        colFront[k] = _grey((0.52 + 0.48 * d.clamp(0.0, 1.0) + sheen));
        colBack[k] = _grey(0.80 + 0.20 * (-d).clamp(0.0, 1.0));
        if (i < _cols) {
          final mid = angleAt(rowT, (i + 0.5) / _cols);
          x += w / _cols * math.cos(mid);
          z += w / _cols * math.sin(mid);
        }
      }
    }

    // Split the triangles by the face they show. Along a row the sheet only
    // ever rises, so the triangles nearer the edge are nearer the reader:
    // drawing the front set (nearer the spine) before the back set paints
    // the leaf back to front.
    final frontIdx = <int>[];
    final backIdx = <int>[];
    for (var j = 0; j < _rows; j++) {
      for (var i = 0; i < _cols; i++) {
        final a = j * (_cols + 1) + i;
        final b = a + 1;
        final c = a + _cols + 1;
        final d = c + 1;
        for (final tri in [
          [a, b, c],
          [b, d, c],
        ]) {
          (_area(pos, tri[0], tri[1], tri[2]) >= 0 ? frontIdx : backIdx)
              .addAll(tri);
        }
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 1. The pages beneath dim a little while the leaf is up, and take a
    //    shadow beside it, longest when it stands highest.
    if (lift > 0.01) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = Colors.black.withValues(alpha: 0.05 * lift));
      final reach = w * (0.05 + 0.24 * lift);
      final alpha = 0.22 * lift;
      if (maxX < spine + w - 1) {
        final r = Rect.fromLTWH(maxX, 0, reach, h);
        canvas.drawRect(
            r,
            Paint()
              ..shader = LinearGradient(colors: [
                Colors.black.withValues(alpha: alpha),
                Colors.black.withValues(alpha: 0),
              ]).createShader(r));
      }
      if (minX < spine - 1) {
        final r = Rect.fromLTWH(minX - reach, 0, reach, h);
        canvas.drawRect(
            r,
            Paint()
              ..shader = LinearGradient(colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: alpha),
              ]).createShader(r));
      }
      // The leaf's own shadow, soft and wide as it rises.
      final outline = Path();
      for (var i = 0; i <= _cols; i++) {
        final k = i;
        i == 0
            ? outline.moveTo(pos[k * 2], pos[k * 2 + 1])
            : outline.lineTo(pos[k * 2], pos[k * 2 + 1]);
      }
      for (var j = 1; j <= _rows; j++) {
        final k = j * (_cols + 1) + _cols;
        outline.lineTo(pos[k * 2], pos[k * 2 + 1]);
      }
      for (var i = _cols - 1; i >= 0; i--) {
        final k = _rows * (_cols + 1) + i;
        outline.lineTo(pos[k * 2], pos[k * 2 + 1]);
      }
      outline.close();
      canvas.drawShadow(outline, Colors.black, 6 + 14 * lift, false);
    }

    // 2. The leaf: its front, then its back.
    _drawFace(canvas, pos, texFront, colFront, frontIdx, front, paper);
    if (back != null) {
      _drawFace(canvas, pos, texBack, colBack, backIdx, back, paper);
    } else {
      // One page a view, the leaf's back is the paper itself, and Bible
      // paper is thin: the page's own print shows through it, reversed.
      _drawFace(canvas, pos, texBack, colBack, backIdx, null, paper);
      if (front != null) {
        _drawFace(canvas, pos, texBack, colBack, backIdx, front, paper,
            opacity: 0.13);
      }
    }
    canvas.restore();
  }

  static int _grey(double b) {
    final v = (b.clamp(0.0, 1.0) * 255).round();
    return 0xFF000000 | (v << 16) | (v << 8) | v;
  }

  static double _area(Float32List p, int a, int b, int c) =>
      (p[b * 2] - p[a * 2]) * (p[c * 2 + 1] - p[a * 2 + 1]) -
      (p[c * 2] - p[a * 2]) * (p[b * 2 + 1] - p[a * 2 + 1]);

  void _drawFace(Canvas canvas, Float32List pos, Float32List tex,
      Int32List colors, List<int> idx, ui.Image? image, Color fallback,
      {double opacity = 1}) {
    if (idx.isEmpty) return;
    if (image != null) {
      final vertices = ui.Vertices.raw(
        VertexMode.triangles,
        pos,
        textureCoordinates: tex,
        colors: colors,
        indices: Uint16List.fromList(idx),
      );
      final sx = image.width / page.width;
      final sy = image.height / page.height;
      canvas.drawVertices(
        vertices,
        BlendMode.modulate,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..shader = ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.diagonal3Values(1 / sx, 1 / sy, 1).storage,
            filterQuality: FilterQuality.medium,
          ),
      );
      vertices.dispose();
      return;
    }
    // No picture to wrap: plain paper, its shading baked into the colours.
    final tinted = Int32List(colors.length);
    for (var i = 0; i < colors.length; i++) {
      final b = (colors[i] & 0xFF) / 255;
      tinted[i] = Color.fromARGB(
        255,
        ((fallback.r * 255) * b).round().clamp(0, 255),
        ((fallback.g * 255) * b).round().clamp(0, 255),
        ((fallback.b * 255) * b).round().clamp(0, 255),
      ).toARGB32();
    }
    final plain = ui.Vertices.raw(VertexMode.triangles, pos,
        colors: tinted, indices: Uint16List.fromList(idx));
    canvas.drawVertices(plain, BlendMode.src, Paint());
    plain.dispose();
  }

  @override
  bool shouldRepaint(PageCurlPainter old) =>
      old.t != t ||
      old.grab != grab ||
      old.front != front ||
      old.back != back ||
      old.page != page ||
      old.spine != spine ||
      old.cameraX != cameraX;
}
