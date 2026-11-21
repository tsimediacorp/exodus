import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/exodus_theme.dart';
import 'bible_paper.dart';
import 'exodus_shield.dart';

/// The closed Bible: what the folded Duo's front screen shows.
///
/// A leather-bound book lying on a dark desk, stamped in gilt with the
/// EXODUS shield, HOLY BIBLE, and the owner's name. It is a thing to hold:
/// drag and it tilts in your hand, the light sliding across the grain and
/// catching the gilt; let go and it settles back. Swipe it open (or tap)
/// and the cover swings back on its hinge to the first page.
class BibleCover extends StatefulWidget {
  /// The name stamped under the title. Empty shows an invitation to add it.
  final String ownerName;

  /// The cover has swung fully open.
  final VoidCallback onOpened;

  /// Long-press or tap on the nameplate.
  final VoidCallback onEditName;

  const BibleCover({
    super.key,
    required this.ownerName,
    required this.onOpened,
    required this.onEditName,
  });

  @override
  State<BibleCover> createState() => _BibleCoverState();
}

class _BibleCoverState extends State<BibleCover> with TickerProviderStateMixin {
  /// Tilt in radians about each axis: x leans the top away, y turns the
  /// fore-edge away.
  Offset _tilt = Offset.zero;
  late final AnimationController _settle = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onSettle);
  Offset _settleFrom = Offset.zero;

  /// 0 closed .. 1 swung open.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// A slow breath of movement while it lies there, so it reads as an
  /// object rather than a picture.
  late final Ticker _idle = createTicker(_onIdle);
  double _clock = 0;

  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _open.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _idle.stop();
        widget.onOpened();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.of(context).disableAnimations) _idle.start();
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    _settle.dispose();
    _open.dispose();
    super.dispose();
  }

  void _onIdle(Duration elapsed) {
    if (_dragging || _settle.isAnimating || _open.isAnimating) return;
    setState(() => _clock = elapsed.inMilliseconds / 1000);
  }

  void _onSettle() {
    setState(() => _tilt = _settleFrom * _settle.value);
  }

  Offset get _breath => Offset(
        math.sin(_clock * 0.55) * 0.025,
        math.sin(_clock * 0.37 + 1) * 0.035,
      );

  void _dragStart(DragStartDetails _) {
    _dragging = true;
    _settle.stop();
  }

  void _dragUpdate(DragUpdateDetails d) {
    setState(() {
      _tilt = Offset(
        (_tilt.dx - d.delta.dy * 0.0065).clamp(-0.32, 0.32),
        (_tilt.dy + d.delta.dx * 0.0065).clamp(-0.42, 0.32),
      );
    });
  }

  void _dragEnd(DragEndDetails d) {
    _dragging = false;
    // A decisive leftward swipe opens the book, the way you would open it.
    if ((d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx) < -500 ||
        d.velocity.pixelsPerSecond.dx < -500) {
      _openBook();
      return;
    }
    _settleFrom = _tilt;
    _settle.value = 1;
    _settle.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 140, damping: 12),
      1,
      0,
      0,
    ));
  }

  void _openBook() {
    if (_open.isAnimating || _open.value > 0) return;
    HapticFeedback.mediumImpact();
    if (MediaQuery.of(context).disableAnimations) {
      widget.onOpened();
      return;
    }
    _settle.stop();
    _open.forward();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final o = Curves.easeInOutCubic.transform(_open.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            // The desk fades as the book opens onto the page beneath.
            Opacity(
              opacity: (1 - o * 1.4).clamp(0.0, 1.0),
              child: const _Desk(),
            ),
            SafeArea(
              child: LayoutBuilder(builder: (context, c) {
                // A Bible's proportions: about 2:3, with room for its depth.
                final h = math.min(c.maxHeight - 64, (c.maxWidth - 48) * 1.5);
                final w = h / 1.5;
                final tilt = _tilt + (reduce ? Offset.zero : _breath);
                return Center(
                  child: GestureDetector(
                    onTap: _openBook,
                    onPanStart: _dragStart,
                    onPanUpdate: _dragUpdate,
                    onPanEnd: _dragEnd,
                    child: Semantics(
                      button: true,
                      label: 'Open the Bible',
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: _book(w, h, tilt, o),
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (o == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Swipe to open',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: BiblePalette.gilt.withValues(alpha: 0.55),
                        fontSize: 12,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _book(double w, double h, Offset tilt, double open) {
    // The block of pages behind the cover shows at the fore-edge and foot
    // as the book turns, moving against the cover: parallax standing in
    // for depth.
    final depth = Offset(
      5 + (-tilt.dy * 22).clamp(-4.0, 10.0),
      5 + (tilt.dx * 22).clamp(-4.0, 10.0),
    );
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..rotateX(tilt.dx)
      ..rotateY(tilt.dy);
    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Shadow on the desk.
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(10 - tilt.dy * 30, 16 + tilt.dx * 30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 30,
                      spreadRadius: -4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The page block, gilt-edged.
          Positioned(
            left: 8 + depth.dx,
            top: 4 + depth.dy * 0.3,
            width: w - 10,
            height: h - 6,
            child: CustomPaint(painter: _BlockPainter()),
          ),
          // The first page, revealed as the cover swings open.
          if (open > 0)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.fromLTRB(6, 4, 2, 4),
                child: const PaperPage(
                  side: PageSide.single,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          // The cover itself, swinging on the spine.
          Positioned.fill(
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0009)
                ..rotateY(-open * math.pi * 0.62),
              child: Opacity(
                opacity: open > 0.85
                    ? (1 - (open - 0.85) / 0.15).clamp(0.0, 1.0)
                    : 1,
                child: _Cover(
                  ownerName: widget.ownerName,
                  light: Offset(0.5 - tilt.dy * 1.6, 0.35 + tilt.dx * 1.6),
                  onEditName: widget.onEditName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Desk extends StatelessWidget {
  const _Desk();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [Color(0xFF1E2333), Color(0xFF07090F)],
        ),
      ),
    );
  }
}

class _BlockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BiblePalette.giltDeep,
            BiblePalette.giltLight,
            BiblePalette.gilt,
            BiblePalette.giltDeep,
          ],
        ).createShader(Offset.zero & size),
    );
    // Leaves: fine lines along the gilt.
    final line = Paint()
      ..color = BiblePalette.giltDeep.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (var y = 3.0; y < size.height; y += 2.2) {
      canvas.drawLine(Offset(size.width - 10, y), Offset(size.width, y), line);
    }
    for (var x = 3.0; x < size.width; x += 2.2) {
      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_BlockPainter old) => false;
}

/// The front board: leather, tooling, gilt, and the owner's name.
class _Cover extends StatelessWidget {
  final String ownerName;

  /// Where the light falls, in fractions of the cover.
  final Offset light;
  final VoidCallback onEditName;

  const _Cover({
    required this.ownerName,
    required this.light,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final scale = (w / 300).clamp(0.6, 1.6);
      Widget gilt(Widget child) => ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment(light.dx * 2 - 2, light.dy * 2 - 2),
              end: Alignment(light.dx * 2, light.dy * 2),
              colors: const [
                BiblePalette.giltDeep,
                BiblePalette.gilt,
                BiblePalette.giltLight,
                BiblePalette.gilt,
                BiblePalette.giltDeep,
              ],
              stops: const [0, 0.35, 0.5, 0.65, 1],
            ).createShader(r),
            child: child,
          );
      final named = ownerName.trim().isNotEmpty;
      return CustomPaint(
        painter: _LeatherPainter(light),
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * 0.16, 0, w * 0.08, 0),
          child: Column(
            children: [
              const Spacer(flex: 5),
              // The shield, set in a gilt roundel as if stamped.
              Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: BiblePalette.gilt.withValues(alpha: 0.75),
                      width: 1.2),
                ),
                child: ExodusShield(size: 46 * scale, glow: false),
              ),
              const Spacer(flex: 3),
              gilt(Text(
                'HOLY',
                style: TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: Colors.white,
                  fontSize: 30 * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 9 * scale,
                  height: 1.1,
                ),
              )),
              gilt(Text(
                'BIBLE',
                style: TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: Colors.white,
                  fontSize: 30 * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 9 * scale,
                  height: 1.1,
                ),
              )),
              SizedBox(height: 14 * scale),
              gilt(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 28 * scale, height: 1, color: Colors.white),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                    child: Fleuron(color: Colors.white, size: 9 * scale),
                  ),
                  Container(width: 28 * scale, height: 1, color: Colors.white),
                ],
              )),
              const Spacer(flex: 6),
              Semantics(
                button: true,
                label: named
                    ? 'Name on the cover: $ownerName. Change it'
                    : 'Put your name on the cover',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEditName,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: named
                        ? gilt(Text(
                            ownerName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                              fontFamily: ExodusTheme.serif,
                              color: Colors.white,
                              fontSize: 19 * scale,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.6,
                            ),
                          ))
                        : Text(
                            'Add your name',
                            style: TextStyle(
                              fontFamily: ExodusTheme.serif,
                              color: BiblePalette.gilt.withValues(alpha: 0.45),
                              fontSize: 14 * scale,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              gilt(Text(
                'EXODUS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 5 * scale,
                ),
              )),
              SizedBox(height: 26 * scale),
            ],
          ),
        ),
      );
    });
  }
}

class _LeatherPainter extends CustomPainter {
  final Offset light;

  _LeatherPainter(this.light);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final board = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(5),
      bottomLeft: const Radius.circular(5),
      topRight: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    );
    canvas.save();
    canvas.clipRRect(board);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF222B44), BiblePalette.leather, Color(0xFF0E1322)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
        Offset.zero & size, BibleTextures.tiled(BibleTextures.leather));

    // The spine: a rounder, darker band with raised bands across it.
    final spine = w * 0.11;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, spine, h),
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.black.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.25),
        ], stops: const [
          0,
          0.55,
          1
        ]).createShader(Rect.fromLTWH(0, 0, spine, h)),
    );
    for (final f in [0.16, 0.34, 0.66, 0.84]) {
      final y = h * f;
      final band = Rect.fromLTWH(0, y - 4, spine, 8);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.black.withValues(alpha: 0.35),
            ],
          ).createShader(band),
      );
      canvas.drawLine(
          Offset(0, y - 4.5),
          Offset(spine, y - 4.5),
          Paint()
            ..color = BiblePalette.gilt.withValues(alpha: 0.5)
            ..strokeWidth = 0.7);
    }
    // The hinge: a groove where the board flexes.
    canvas.drawLine(
        Offset(spine + 1, 0),
        Offset(spine + 1, h),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..strokeWidth = 2.2);
    canvas.drawLine(
        Offset(spine + 3, 0),
        Offset(spine + 3, h),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 1);

    // Blind tooling: a pressed frame, dark below its edge, light above.
    final panel = Rect.fromLTRB(spine + 14, 14, w - 14, h - 14);
    final tooled = RRect.fromRectAndRadius(panel, const Radius.circular(6));
    canvas.drawRRect(
        tooled.shift(const Offset(0, 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.07));
    canvas.drawRRect(
        tooled,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.black.withValues(alpha: 0.5));

    // Gilt rules inside it, double, with corner ornaments.
    final giltPaint = Paint()
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment(light.dx * 2 - 2, light.dy * 2 - 2),
        end: Alignment(light.dx * 2, light.dy * 2),
        colors: const [
          BiblePalette.giltDeep,
          BiblePalette.gilt,
          BiblePalette.giltLight,
          BiblePalette.gilt,
          BiblePalette.giltDeep,
        ],
        stops: const [0, 0.35, 0.5, 0.65, 1],
      ).createShader(Offset.zero & size);
    final outer = panel.deflate(8);
    final inner = panel.deflate(12);
    canvas.drawRect(outer, giltPaint..strokeWidth = 1.3);
    canvas.drawRect(inner, giltPaint..strokeWidth = 0.6);
    for (final corner in [
      inner.topLeft,
      inner.topRight,
      inner.bottomLeft,
      inner.bottomRight,
    ]) {
      final sx = corner.dx < w / 2 ? 1.0 : -1.0;
      final sy = corner.dy < h / 2 ? 1.0 : -1.0;
      final c = corner + Offset(sx * 10, sy * 10);
      final leaf = Path()
        ..moveTo(c.dx, c.dy - sy * 7)
        ..quadraticBezierTo(c.dx + sx * 5, c.dy, c.dx, c.dy + sy * 7)
        ..quadraticBezierTo(c.dx - sx * 5, c.dy, c.dx, c.dy - sy * 7)
        ..moveTo(c.dx - sx * 7, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + sy * 5, c.dx + sx * 7, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - sy * 5, c.dx - sx * 7, c.dy);
      canvas.drawPath(leaf, giltPaint..strokeWidth = 0.9);
      canvas.drawCircle(c, 1.6, Paint()..shader = giltPaint.shader);
    }

    // Stitching around the fore-edges.
    final stitch = Paint()
      ..color = const Color(0xFF8C93A8).withValues(alpha: 0.35)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var x = spine + 10; x < w - 8; x += 7) {
      canvas.drawLine(Offset(x, 6), Offset(x + 3.5, 6), stitch);
      canvas.drawLine(Offset(x, h - 6), Offset(x + 3.5, h - 6), stitch);
    }
    for (var y = 10.0; y < h - 8; y += 7) {
      canvas.drawLine(Offset(w - 6, y), Offset(w - 6, y + 3.5), stitch);
    }

    // The sheen: where the light lies across the grain.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(light.dx * 2 - 1, light.dy * 2 - 1),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.13),
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // Board edge.
    canvas.drawRRect(
        board,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_LeatherPainter old) => old.light != light;
}
