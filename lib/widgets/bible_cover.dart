import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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

  /// The binding: 'navy', 'oxblood' or 'black'.
  final String style;

  /// The photograph of the front board in [style].
  static String coverAsset(String style) =>
      'assets/bible_art/book/cover-${styles.contains(style) ? style : 'navy'}.webp';

  static const List<String> styles = ['navy', 'oxblood', 'black'];

  /// The cover has swung fully open.
  final VoidCallback onOpened;

  /// Long-press or tap on the nameplate.
  final VoidCallback onEditName;

  const BibleCover({
    super.key,
    required this.ownerName,
    this.style = 'navy',
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
              child: const BibleDesk(),
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
                child: BibleCoverFace(
                  ownerName: widget.ownerName,
                  style: widget.style,
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

/// The walnut desk the book lies on, lit by a lamp from the upper left.
class BibleDesk extends StatelessWidget {
  const BibleDesk({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/bible_art/book/desk.webp',
            fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.3, -0.4),
              radius: 1.3,
              colors: [Color(0x00000000), Color(0x99000000)],
            ),
          ),
        ),
      ],
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

/// The front board: a hand-bound leather cover, gilt-tooled, with the title
/// and the owner's name stamped into it in gold.
///
/// The board itself is a photograph; the lettering is set as type over its
/// empty centre panel, so it is crisp at any size and the name can be the
/// reader's own. Each letter is pressed in: a dark edge above where the
/// tool bit into the leather, a catch of light below, and gilt that moves
/// with [light].
class BibleCoverFace extends StatelessWidget {
  final String ownerName;
  final String style;

  /// Where the light falls, in fractions of the cover.
  final Offset light;
  final VoidCallback? onEditName;

  const BibleCoverFace({
    super.key,
    required this.ownerName,
    required this.style,
    this.light = const Offset(0.35, 0.3),
    this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final scale = (w / 300).clamp(0.5, 1.8);
      final named = ownerName.trim().isNotEmpty;

      Widget stamped(String text, TextStyle style) {
        final d = 0.9 * scale;
        return Stack(
          children: [
            // The pressed edge and catch-light are decoration: read once.
            ExcludeSemantics(
              child: Transform.translate(
                offset: Offset(-d * 0.6, -d),
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                        color: Colors.black.withValues(alpha: 0.55))),
              ),
            ),
            ExcludeSemantics(
              child: Transform.translate(
                offset: Offset(d * 0.4, d * 0.7),
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                        color: Colors.white.withValues(alpha: 0.10))),
              ),
            ),
            ShaderMask(
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
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: style.copyWith(color: Colors.white)),
            ),
          ],
        );
      }

      final title = TextStyle(
        fontFamily: 'Cormorant',
        fontVariations: const [FontVariation('wght', 600)],
        fontSize: 34 * scale,
        letterSpacing: 8 * scale,
        height: 1.05,
      );

      return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(BibleCover.coverAsset(style),
                fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            // The sheen of the leather where the light falls on it.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(light.dx * 2 - 1, light.dy * 2 - 1),
                  radius: 0.9,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            // The lettering, in the empty panel inside the tooled border
            // (the board's spine is at the left, so the panel sits right of
            // centre).
            Positioned(
              left: w * 0.25,
              right: w * 0.16,
              top: h * 0.13,
              bottom: h * 0.11,
              child: Column(
                children: [
                  const Spacer(flex: 4),
                  Container(
                    padding: EdgeInsets.all(9 * scale),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: BiblePalette.gilt.withValues(alpha: 0.7),
                          width: 1.1),
                    ),
                    child: ExodusShield(size: 40 * scale, glow: false),
                  ),
                  const Spacer(flex: 3),
                  stamped('HOLY', title),
                  stamped('BIBLE', title),
                  SizedBox(height: 12 * scale),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 26 * scale,
                          height: 1,
                          color: BiblePalette.gilt.withValues(alpha: 0.8)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                        child:
                            Fleuron(color: BiblePalette.gilt, size: 9 * scale),
                      ),
                      Container(
                          width: 26 * scale,
                          height: 1,
                          color: BiblePalette.gilt.withValues(alpha: 0.8)),
                    ],
                  ),
                  const Spacer(flex: 6),
                  Semantics(
                    button: onEditName != null,
                    label: named
                        ? 'Name on the cover: $ownerName. Change it'
                        : 'Put your name on the cover',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onEditName,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: named
                            ? stamped(
                                ownerName,
                                TextStyle(
                                  fontFamily: 'Cormorant',
                                  fontStyle: FontStyle.italic,
                                  fontVariations: const [
                                    FontVariation('wght', 600)
                                  ],
                                  fontSize: 21 * scale,
                                  letterSpacing: 0.6,
                                ),
                              )
                            : Text(
                                onEditName == null ? '' : 'Add your name',
                                style: TextStyle(
                                  fontFamily: 'Cormorant',
                                  fontStyle: FontStyle.italic,
                                  color:
                                      BiblePalette.gilt.withValues(alpha: 0.5),
                                  fontSize: 15 * scale,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  stamped(
                    'EXODUS',
                    TextStyle(
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 5 * scale,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
