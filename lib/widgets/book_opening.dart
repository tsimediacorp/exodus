import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bible_cover.dart';
import 'bible_paper.dart';

/// Opening the Bible, as the Duo unfolds.
///
/// The closed book lies on the desk where the right-hand page will be. Its
/// front board swings over on the spine (the fold of the phone), rising
/// toward the reader in perspective, and lands on the left showing the
/// marbled endpaper inside it; under it on the right is the title page. A
/// few leaves riffle over, as a thumb finds the ribbon, and the book is
/// open at the reader's place.
///
/// About two and a half seconds; a tap anywhere skips it.
class BookOpening extends StatefulWidget {
  final String coverStyle;
  final String ownerName;

  /// The open translation's full name, for the title page.
  final String translationName;
  final VoidCallback onDone;

  const BookOpening({
    super.key,
    required this.coverStyle,
    required this.ownerName,
    required this.translationName,
    required this.onDone,
  });

  @override
  State<BookOpening> createState() => _BookOpeningState();
}

class _BookOpeningState extends State<BookOpening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2700),
  );
  bool _done = false;

  static const int _leaves = 5;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _c.addListener(_haptics);
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Everything the scene shows is decoded before the board lifts, so the
    // endpaper is there the moment it comes into view. Never longer than a
    // beat: the book opens regardless.
    Future.wait([
      for (final a in [
        BibleCover.coverAsset(widget.coverStyle),
        'assets/bible_art/book/endpaper.webp',
        'assets/bible_art/book/desk.webp',
      ])
        precacheImage(AssetImage(a), context).catchError((_) {}),
    ])
        .timeout(const Duration(milliseconds: 600), onTimeout: () => const [])
        .whenComplete(() {
      if (mounted) _c.forward();
    });
  }

  double _lastCover = 0;
  void _haptics() {
    // A soft knock as the board lands on the desk.
    final cover = _phase(0.06, 0.46);
    if (_lastCover < 1 && cover >= 1) HapticFeedback.lightImpact();
    _lastCover = cover;
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Progress through [from, to] of the whole, eased.
  double _phase(double from, double to) => Curves.easeInOutCubic
      .transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Opening the Bible. Tap to skip.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, c) => Opacity(
              opacity: 1 - _phase(0.9, 1.0),
              child: _scene(c.biggest),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scene(Size size) {
    final spine = size.width / 2;
    const margin = 14.0;
    final page = Rect.fromLTRB(
        spine, margin + 4, size.width - margin - 6, size.height - margin - 8);
    final board = Rect.fromLTRB(
        spine - 2, margin, size.width - margin, size.height - margin);
    final cover = _phase(0.06, 0.46);
    final title = _TitlePage(
      ownerName: widget.ownerName,
      translationName: widget.translationName,
    );
    return Stack(
      children: [
        const Positioned.fill(child: BibleDesk()),
        // The block of pages, gilt-edged, under the title page.
        Positioned.fromRect(
          rect: page.translate(5, 5),
          child: const CustomPaint(painter: _BlockEdgePainter()),
        ),
        // The title page is the first leaf turned; under it, the text.
        Positioned.fromRect(
          rect: page,
          child: _leafTurn(0) > 0
              ? const PaperPage(
                  side: PageSide.right,
                  child: CustomPaint(
                      painter: _PrintPainter(seed: 99, rightHand: true),
                      size: Size.infinite))
              : title,
        ),
        // Past upright the board lies on the left, under the leaves that
        // will land on it; before that it lies over them.
        if (cover >= 0.5) ...[
          // The front board.
          Positioned.fromRect(
            rect: board,
            child: _Turning(
              angle: -math.pi * cover,
              elevation: 18,
              front: BibleCoverFace(
                ownerName: widget.ownerName,
                style: widget.coverStyle,
                light: Offset(0.35 - cover * 0.3, 0.3),
              ),
              back: const _Endpaper(),
            ),
          ),
        ],
        // The leaves a thumb riffles over to find its place.
        for (var k = _leaves - 1; k >= 0; k--)
          if (_leafTurn(k) > 0)
            Positioned.fromRect(
              rect: page,
              child: _Turning(
                angle: -math.pi * _leafTurn(k),
                shade: 0.12,
                front: k == 0
                    ? title
                    : PaperPage(
                        side: PageSide.right,
                        child: CustomPaint(
                            painter:
                                _PrintPainter(seed: k * 2, rightHand: true),
                            size: Size.infinite)),
                back: PaperPage(
                    side: PageSide.left,
                    child: CustomPaint(
                        painter: _PrintPainter(seed: k * 2 + 1),
                        size: Size.infinite)),
              ),
            ),
        if (cover < 0.5) ...[
          // The front board.
          Positioned.fromRect(
            rect: board,
            child: _Turning(
              angle: -math.pi * cover,
              elevation: 18,
              front: BibleCoverFace(
                ownerName: widget.ownerName,
                style: widget.coverStyle,
                light: Offset(0.35 - cover * 0.3, 0.3),
              ),
              back: const _Endpaper(),
            ),
          ),
        ],
      ],
    );
  }

  /// How far leaf [k] has turned, 0..1. The first leaves go together with
  /// the board's landing; each after it a beat later.
  double _leafTurn(int k) {
    final start = 0.52 + k * 0.055;
    return _phase(start, start + 0.17);
  }
}

/// A flat leaf or board hinged at its left edge, turned by [angle] (0 flat
/// to the right, -pi flat to the left), showing [back] once past upright.
class _Turning extends StatelessWidget {
  final double angle;
  final Widget front;
  final Widget back;
  final double elevation;

  /// How dark the face grows when it stands edge-on to the lamp.
  final double shade;

  const _Turning({
    required this.angle,
    required this.front,
    required this.back,
    this.elevation = 6,
    this.shade = 0.28,
  });

  @override
  Widget build(BuildContext context) {
    final showBack = angle < -math.pi / 2;
    final lift = math.sin(-angle).clamp(0.0, 1.0);
    final face = showBack
        // Seen from behind, the back is the right way round once mirrored.
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: back,
          )
        : front;
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0007)
        ..rotateY(angle),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35 * lift + 0.1),
              blurRadius: 4 + elevation * lift,
              offset: Offset(0, 2 + elevation * 0.3 * lift),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            face,
            // Turned toward or away from the lamp.
            IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: shade * lift),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inside of the front board: leather turned in around the edges, and
/// a marbled paper pasted down within.
class _Endpaper extends StatelessWidget {
  const _Endpaper();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BiblePalette.leatherDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
                color: BiblePalette.gilt.withValues(alpha: 0.6), width: 0.8),
          ),
          child: Image.asset('assets/bible_art/book/endpaper.webp',
              fit: BoxFit.cover, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }
}

/// The title page, facing the endpaper when the book first opens.
class _TitlePage extends StatelessWidget {
  final String ownerName;
  final String translationName;

  const _TitlePage({required this.ownerName, required this.translationName});

  @override
  Widget build(BuildContext context) {
    const kicker = TextStyle(
      fontFamily: 'Spectral',
      fontSize: 10.5,
      letterSpacing: 3.2,
      fontWeight: FontWeight.w600,
      color: BiblePalette.faint,
    );
    return PaperPage(
      side: PageSide.right,
      child: MediaQuery.withNoTextScaling(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const Fleuron(color: BiblePalette.giltRule, size: 12),
              const SizedBox(height: 22),
              const Text('THE', style: kicker),
              const SizedBox(height: 8),
              const Text('HOLY BIBLE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cormorant',
                    fontVariations: [FontVariation('wght', 600)],
                    fontSize: 40,
                    letterSpacing: 6,
                    color: BiblePalette.ink,
                  )),
              const SizedBox(height: 10),
              const Text('Containing the Old and New Testaments',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cormorant',
                    fontStyle: FontStyle.italic,
                    fontVariations: [FontVariation('wght', 500)],
                    fontSize: 17,
                    color: BiblePalette.inkSoft,
                  )),
              const SizedBox(height: 26),
              Text(translationName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: kicker.copyWith(color: BiblePalette.rubric)),
              const Spacer(flex: 4),
              if (ownerName.trim().isNotEmpty) ...[
                const Text('THIS BIBLE BELONGS TO',
                    style: TextStyle(
                      fontFamily: 'Spectral',
                      fontSize: 9,
                      letterSpacing: 2.6,
                      color: BiblePalette.faint,
                    )),
                const SizedBox(height: 6),
                Text(ownerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Cormorant',
                      fontStyle: FontStyle.italic,
                      fontVariations: [FontVariation('wght', 500)],
                      fontSize: 22,
                      color: BiblePalette.ink,
                    )),
                const Spacer(flex: 2),
              ],
              const Text('EXODUS', style: kicker),
            ],
          ),
        ),
      ),
    );
  }
}

/// The fore-edge and foot of the page block: fine leaves, gilt.
class _BlockEdgePainter extends CustomPainter {
  const _BlockEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
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
        ).createShader(r),
    );
    final line = Paint()
      ..color = BiblePalette.giltDeep.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (var y = 2.0; y < size.height; y += 2.2) {
      canvas.drawLine(Offset(size.width - 6, y), Offset(size.width, y), line);
    }
    for (var x = 2.0; x < size.width; x += 2.2) {
      canvas.drawLine(Offset(x, size.height - 6), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_BlockEdgePainter old) => false;
}

/// A page of type seen in passing: lines of grey where the words are, a
/// verse number's red here and there. Nobody reads a page mid-riffle, but
/// a blank one would look like a card.
class _PrintPainter extends CustomPainter {
  final int seed;
  final bool rightHand;

  const _PrintPainter({required this.seed, this.rightHand = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed + 11);
    final left = rightHand ? 34.0 : 40.0;
    final right = size.width - (rightHand ? 40.0 : 34.0);
    final ink = Paint()..color = BiblePalette.ink.withValues(alpha: 0.22);
    final red = Paint()..color = BiblePalette.rubric.withValues(alpha: 0.5);
    for (var y = 62.0; y < size.height - 50; y += 23) {
      var x = left;
      final last = y + 23 >= size.height - 50 || rnd.nextDouble() < 0.06;
      final end =
          last ? left + (right - left) * (0.3 + rnd.nextDouble() * 0.5) : right;
      while (x < end) {
        final word = 10 + rnd.nextDouble() * 38;
        final w = math.min(word, end - x);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, 5), const Radius.circular(2)),
            rnd.nextDouble() < 0.04 ? red : ink);
        x += w + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_PrintPainter old) => old.seed != seed;
}
