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
          math.min(2.0, MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0);
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

  void _onDragStart(DragStartDetails d, double height) {
    _pos.stop();
    _grab = height <= 0 ? 0.8 : (d.localPosition.dy / height).clamp(0.0, 1.0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // A full turn is the width of one page: drag from the outer edge to the
    // spine and the leaf is upright; on to the far edge and it has landed.
    final next = _pos.value - d.primaryDelta! / _pageWidth;
    // Resist past the covers instead of stopping dead, so the end of a
    // chapter feels like the end of a book rather than a wall.
    final max = (_viewCount - 1).toDouble();
    double v = next;
    if (next < 0) v = next * 0.25;
    if (next > max) v = max + (next - max) * 0.25;
    _pos.value = v;
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = -(d.primaryVelocity ?? 0) / _pageWidth; // views/sec
    final base = _pos.value.floorToDouble();
    final frac = _pos.value - base;
    double target;
    if (velocity.abs() > 0.6) {
      target = velocity > 0 ? base + 1 : base;
    } else {
      target = frac > 0.5 ? base + 1 : base;
    }
    target = target.clamp(0, (_viewCount - 1).toDouble());
    _settleTo(target.round(), velocity: velocity);
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
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart:
            widget.interactive ? (d) => _onDragStart(d, height) : null,
        onHorizontalDragUpdate: widget.interactive ? _onDragUpdate : null,
        onHorizontalDragEnd: widget.interactive ? _onDragEnd : null,
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

/// Paints one leaf part-way through a turn, and the shadow it throws.
///
/// The leaf lies to the right of [spine]. [t] runs from 0 (flat, unturned)
/// to 1 (flat on the other side of the spine).
@visibleForTesting
class PageCurlPainter extends CustomPainter {
  final double t;
  final double grab;
  final double spine;
  final Size page;
  final ui.Image? front;
  final ui.Image? back;
  final Color paper;

  PageCurlPainter({
    required this.t,
    required this.grab,
    required this.spine,
    required this.page,
    required this.front,
    required this.back,
    required this.paper,
  });

  static const int _cols = 32;
  static const int _rows = 22;

  /// The leaf's geometry at [t]: radius of the roll, where its axis lies,
  /// and how far it is tilted.
  ({double radius, double axis, double tilt}) get geometry {
    final w = page.width;
    final lift = math.sin(math.pi * t);
    final radius = w * 0.15 * lift + 0.5;
    final axis = w * (1 - t) - math.pi * radius / 2 * t;
    // Taken by a bottom corner, the roll leans so that corner leads.
    final tilt = (grab - 0.5) * 0.55 * lift;
    return (radius: radius, axis: axis, tilt: tilt);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = page.width;
    final h = page.height;
    if (w <= 0 || h <= 0) return;
    final g = geometry;
    final r = g.radius;
    final nx = math.cos(g.tilt), ny = math.sin(g.tilt);
    final focal = w * 3.2;
    final lift = math.sin(math.pi * t);

    const n = (_cols + 1) * (_rows + 1);
    final pos = Float32List(n * 2);
    final texFront = Float32List(n * 2);
    final texBack = Float32List(n * 2);
    final colFront = Int32List(n);
    final colBack = Int32List(n);
    final z = Float32List(n);
    final phi = Float32List(n);

    for (var j = 0; j <= _rows; j++) {
      final v = h * j / _rows;
      for (var i = 0; i <= _cols; i++) {
        final u = w * i / _cols;
        final k = j * (_cols + 1) + i;
        final d = (u - g.axis) * nx + (v - h / 2) * ny;
        double nd = d, zz = 0, a = 0;
        if (d > 0) {
          if (d < math.pi * r) {
            a = d / r;
            nd = r * math.sin(a);
            zz = r * (1 - math.cos(a));
          } else {
            a = math.pi;
            nd = -(d - math.pi * r);
            zz = 2 * r;
          }
        }
        final x = u + (nd - d) * nx;
        final y = v + (nd - d) * ny;
        final s = focal / (focal - zz);
        pos[k * 2] = spine + x * s;
        pos[k * 2 + 1] = h / 2 + (y - h / 2) * s;
        texFront[k * 2] = u;
        texFront[k * 2 + 1] = v;
        texBack[k * 2] = w - u;
        texBack[k * 2 + 1] = v;
        z[k] = zz;
        phi[k] = a;
        // Light from above: the face brightens as it turns toward it, with
        // a sheen along the roll where paper catches the light edge-on.
        final c = math.cos(a);
        final sheen = math.exp(-math.pow(a - 1.15, 2) / 0.05) * 0.10;
        final fb = (0.62 + 0.38 * c.clamp(0.0, 1.0) + sheen).clamp(0.0, 1.0);
        final bb = (0.70 + 0.30 * (-c).clamp(0.0, 1.0)).clamp(0.0, 1.0);
        colFront[k] = _grey(fb);
        colBack[k] = _grey(bb * 0.97);
      }
    }

    // Split the triangles by which face of the paper they show.
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
          final area = _area(pos, tri[0], tri[1], tri[2]);
          (area >= 0 ? frontIdx : backIdx).addAll(tri);
        }
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 1. The shadow the roll throws on the page it is uncovering.
    _castShadow(canvas, g, lift);

    // 2. The face still facing up.
    _drawFace(canvas, pos, texFront, colFront, frontIdx, front, paper);
    // Ambient darkening where the paper starts to bend away from the light.
    _bendShade(canvas, g, lift);

    // 3. The part that has rolled over hovers above it: a soft shadow,
    //    then the back of the leaf.
    if (backIdx.isNotEmpty) {
      final silhouette = Path();
      for (var q = 0; q < backIdx.length; q += 3) {
        silhouette.addPolygon([
          for (var m = 0; m < 3; m++)
            Offset(pos[backIdx[q + m] * 2], pos[backIdx[q + m] * 2 + 1]),
        ], true);
      }
      canvas.drawShadow(
          silhouette, Colors.black, (2 * r * 0.18).clamp(1.0, 9.0), false);
      _drawFace(canvas, pos, texBack, colBack, backIdx, back, paper);
    }
    canvas.restore();
  }

  static int _grey(double b) {
    final v = (b * 255).round().clamp(0, 255);
    return 0xFF000000 | (v << 16) | (v << 8) | v;
  }

  static double _area(Float32List p, int a, int b, int c) =>
      (p[b * 2] - p[a * 2]) * (p[c * 2 + 1] - p[a * 2 + 1]) -
      (p[c * 2] - p[a * 2]) * (p[b * 2 + 1] - p[a * 2 + 1]);

  void _drawFace(Canvas canvas, Float32List pos, Float32List tex,
      Int32List colors, List<int> idx, ui.Image? image, Color fallback) {
    if (idx.isEmpty) return;
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      pos,
      textureCoordinates: image == null ? null : tex,
      colors: colors,
      indices: Uint16List.fromList(idx),
    );
    final paint = Paint();
    if (image != null) {
      final sx = image.width / page.width;
      final sy = image.height / page.height;
      paint.shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.diagonal3Values(1 / sx, 1 / sy, 1).storage,
        filterQuality: FilterQuality.medium,
      );
      canvas.drawVertices(vertices, BlendMode.modulate, paint);
    } else {
      // No picture to wrap: plain paper. Vertex colours win over the paint
      // colour when there is no shader, so the paper is baked into them.
      vertices.dispose();
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
      return;
    }
    vertices.dispose();
  }

  /// Along the line where the roll meets the page below, out toward the
  /// fore-edge, fading. Strongest mid-turn, when the leaf stands highest.
  void _castShadow(Canvas canvas, ({double radius, double axis, double tilt}) g,
      double lift) {
    if (lift <= 0.01) return;
    final w = page.width;
    final h = page.height;
    final crest = g.axis + g.radius;
    final reach = w * (0.08 + 0.16 * lift);
    canvas.save();
    canvas.translate(spine + crest * math.cos(g.tilt), h / 2);
    canvas.rotate(g.tilt);
    final rect = Rect.fromLTWH(0, -h, reach, h * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.black.withValues(alpha: 0.38 * lift),
          Colors.black.withValues(alpha: 0.10 * lift),
          Colors.black.withValues(alpha: 0),
        ], stops: const [
          0,
          0.35,
          1
        ]).createShader(rect),
    );
    canvas.restore();
  }

  /// Just inside the axis the face is starting to bend away from the light.
  void _bendShade(Canvas canvas, ({double radius, double axis, double tilt}) g,
      double lift) {
    if (lift <= 0.01) return;
    final h = page.height;
    final band = g.radius * 0.9 + 6;
    canvas.save();
    canvas.translate(spine + g.axis * math.cos(g.tilt), h / 2);
    canvas.rotate(g.tilt);
    final rect = Rect.fromLTWH(-band, -h, band, h * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          const Color(0xFFB9AC96).withValues(alpha: 0.35 * lift),
        ]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageCurlPainter old) =>
      old.t != t ||
      old.grab != grab ||
      old.front != front ||
      old.back != back ||
      old.page != page ||
      old.spine != spine;
}
