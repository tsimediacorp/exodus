import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The colours of a printed Bible: cream India paper, near-black ink, red
/// rubrics, gilt edges, and the dark leather around it all.
class BiblePalette {
  BiblePalette._();

  static const paper = Color(0xFFF3EBDA);
  static const paperShade = Color(0xFFE6D9BF);
  static const ink = Color(0xFF2A211A);
  static const inkSoft = Color(0xFF5B4D3F);
  static const rubric = Color(0xFF9B2C22);
  static const faint = Color(0xFF9A8A72);
  static const gilt = Color(0xFFC9A961);
  static const giltLight = Color(0xFFF1DB9A);
  static const giltDeep = Color(0xFF8C6D2C);
  static const leather = Color(0xFF1A2135);
  static const leatherDeep = Color(0xFF0D1220);
  static const ribbon = Color(0xFF7A1F2B);

  static const LinearGradient giltGradient = LinearGradient(
    colors: [giltDeep, gilt, giltLight, gilt, giltDeep],
    stops: [0, 0.3, 0.5, 0.7, 1],
  );
}

/// Procedural textures, made once and tiled.
class BibleTextures {
  BibleTextures._();

  static ui.Image? _paper;
  static ui.Image? _leather;

  /// Paper: a scatter of fibres and flecks, too faint to read as a
  /// pattern, enough that the page is no longer a flat fill.
  static ui.Image get paper => _paper ??= _make(256, (canvas, rnd) {
        for (var i = 0; i < 2600; i++) {
          final dark = rnd.nextBool();
          canvas.drawCircle(
            Offset(rnd.nextDouble() * 256, rnd.nextDouble() * 256),
            rnd.nextDouble() * 0.9 + 0.2,
            Paint()
              ..color = (dark ? const Color(0xFF6B5638) : Colors.white)
                  .withValues(alpha: rnd.nextDouble() * 0.07 + 0.015),
          );
        }
        final fibre = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 140; i++) {
          final p = Offset(rnd.nextDouble() * 256, rnd.nextDouble() * 256);
          final a = rnd.nextDouble() * math.pi;
          final len = rnd.nextDouble() * 9 + 3;
          final q = p + Offset(math.cos(a), math.sin(a)) * len;
          final c = Offset.lerp(p, q, 0.5)! +
              Offset(rnd.nextDouble() * 4 - 2, rnd.nextDouble() * 4 - 2);
          fibre.color = const Color(0xFF7A6342)
              .withValues(alpha: rnd.nextDouble() * 0.06 + 0.02);
          canvas.drawPath(
              Path()
                ..moveTo(p.dx, p.dy)
                ..quadraticBezierTo(c.dx, c.dy, q.dx, q.dy),
              fibre);
        }
      });

  /// Leather: a pebbled grain, light on the tops of the pebbles and dark
  /// in the creases between them.
  static ui.Image get leather => _leather ??= _make(192, (canvas, rnd) {
        for (var i = 0; i < 2200; i++) {
          final c = Offset(rnd.nextDouble() * 192, rnd.nextDouble() * 192);
          final r = rnd.nextDouble() * 2.2 + 0.8;
          canvas.drawCircle(
              c + const Offset(0.5, 0.7),
              r,
              Paint()
                ..color = Colors.black
                    .withValues(alpha: rnd.nextDouble() * 0.18 + 0.05));
          canvas.drawCircle(
              c,
              r * 0.8,
              Paint()
                ..color = Colors.white
                    .withValues(alpha: rnd.nextDouble() * 0.045 + 0.01));
        }
        final crease = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        for (var i = 0; i < 90; i++) {
          final p = Offset(rnd.nextDouble() * 192, rnd.nextDouble() * 192);
          final a = rnd.nextDouble() * math.pi * 2;
          final q = p +
              Offset(math.cos(a), math.sin(a)) * (rnd.nextDouble() * 14 + 4);
          crease.color = Colors.black.withValues(alpha: 0.12);
          canvas.drawLine(p, q, crease);
        }
      });

  static ui.Image _make(int size, void Function(Canvas, math.Random) draw) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas, math.Random(7));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  /// A paint that tiles [image] at [opacity].
  static Paint tiled(ui.Image image, {double opacity = 1}) => Paint()
    ..color = Colors.white.withValues(alpha: opacity)
    ..shader = ImageShader(image, TileMode.repeated, TileMode.repeated,
        Matrix4.identity().storage);
}

/// A printer's ornament, drawn: the type has no dingbats, and a missing
/// glyph would print as an empty box.
class Fleuron extends StatelessWidget {
  final Color color;
  final double size;

  const Fleuron({super.key, required this.color, this.size = 10});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 2.6,
        height: size,
        child: CustomPaint(painter: _FleuronPainter(color)),
      );
}

class _FleuronPainter extends CustomPainter {
  final Color color;
  _FleuronPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.height / 2;
    final paint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.62, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.62, c.dy)
        ..close(),
      paint,
    );
    for (final s in [-1.0, 1.0]) {
      canvas.drawCircle(Offset(c.dx + s * r * 1.5, c.dy), r * 0.22, paint);
      canvas.drawCircle(Offset(c.dx + s * r * 2.3, c.dy), r * 0.14, paint);
    }
  }

  @override
  bool shouldRepaint(_FleuronPainter old) => old.color != color;
}

/// Which side of the spine a page lies on.
enum PageSide { left, right, single }

/// A sheet of Bible paper: texture, the darkening where it curves into the
/// binding, and a little shade at the fore-edge.
class PaperPage extends StatelessWidget {
  final PageSide side;
  final Widget child;

  const PaperPage({super.key, required this.side, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PaperPainter(side),
      child: child,
    );
  }
}

class PaperPainter extends CustomPainter {
  final PageSide side;

  PaperPainter(this.side);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = BiblePalette.paper);
    canvas.drawRect(rect, BibleTextures.tiled(BibleTextures.paper));

    // Paper curving down into the gutter turns away from the light.
    final spineOnLeft = side != PageSide.left;
    final gutter = size.width * (side == PageSide.single ? 0.07 : 0.13);
    final g = spineOnLeft
        ? Rect.fromLTWH(0, 0, gutter, size.height)
        : Rect.fromLTWH(size.width - gutter, 0, gutter, size.height);
    canvas.drawRect(
      g,
      Paint()
        ..shader = LinearGradient(
          begin: spineOnLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: spineOnLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            const Color(0xFF3B2A14).withValues(alpha: 0.34),
            const Color(0xFF3B2A14).withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 0.7, 1],
        ).createShader(g),
    );

    // The fore-edge: a breath of shade where the sheet meets the block.
    final edge = size.width * 0.035;
    final e = spineOnLeft
        ? Rect.fromLTWH(size.width - edge, 0, edge, size.height)
        : Rect.fromLTWH(0, 0, edge, size.height);
    canvas.drawRect(
      e,
      Paint()
        ..shader = LinearGradient(
          begin: spineOnLeft ? Alignment.centerRight : Alignment.centerLeft,
          end: spineOnLeft ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            const Color(0xFF5A4424).withValues(alpha: 0.12),
            const Color(0xFF5A4424).withValues(alpha: 0),
          ],
        ).createShader(e),
    );

    // Top and foot, very faintly, so the sheet has edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF5A4424).withValues(alpha: 0.06),
            Colors.transparent,
            Colors.transparent,
            const Color(0xFF5A4424).withValues(alpha: 0.07),
          ],
          stops: const [0, 0.04, 0.96, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.side != side;
}

/// The book around the pages: leather boards just proud of the paper, the
/// block of pages showing at the fore-edges and foot, gilt on its edges,
/// and a ribbon marker in the gutter.
class BookBinding extends StatelessWidget {
  /// 2 for an open book, 1 for a single page with the spine at the left.
  final int pagesPerView;
  final Widget child;

  const BookBinding(
      {super.key, required this.pagesPerView, required this.child});

  /// Space the binding takes around the pages.
  static EdgeInsets insetsFor(int perView) => perView == 2
      ? const EdgeInsets.fromLTRB(14, 10, 14, 18)
      : const EdgeInsets.fromLTRB(6, 8, 14, 16);

  @override
  Widget build(BuildContext context) {
    final inset = insetsFor(pagesPerView);
    return CustomPaint(
      painter: _BindingPainter(pagesPerView, inset),
      foregroundPainter: _RibbonPainter(pagesPerView, inset),
      child: Padding(padding: inset, child: child),
    );
  }
}

class _BindingPainter extends CustomPainter {
  final int per;
  final EdgeInsets inset;

  _BindingPainter(this.per, this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    final board =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(
      board,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BiblePalette.leather, BiblePalette.leatherDeep],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRRect(board);
    canvas.drawRect(Offset.zero & size,
        BibleTextures.tiled(BibleTextures.leather, opacity: 0.9));
    canvas.restore();

    final pages = inset.deflateRect(Offset.zero & size);

    // The block of pages under the open sheet: a few hairlines stepping out
    // at the fore-edge and foot, the outermost gilt.
    for (var i = 4; i >= 1; i--) {
      final grow = i * 1.6;
      final r = Rect.fromLTRB(
        pages.left - (per == 2 ? grow : 0),
        pages.top,
        pages.right + grow,
        pages.bottom + grow * 1.2,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = i == 4
              ? BiblePalette.giltDeep
              : Color.lerp(
                  BiblePalette.paperShade, BiblePalette.giltDeep, i / 5)!,
      );
    }
    // Shadow of the open sheets on the block and boards.
    canvas.drawRect(
      pages.inflate(1),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_BindingPainter old) => old.per != per;
}

class _RibbonPainter extends CustomPainter {
  final int per;
  final EdgeInsets inset;

  _RibbonPainter(this.per, this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    final pages = inset.deflateRect(Offset.zero & size);
    // A ribbon from the head of the gutter, out past the foot.
    final x = per == 2 ? pages.center.dx + 10 : pages.left + 22;
    const w = 9.0;
    final top = pages.bottom - 26;
    final bottom = size.height - 1;
    final path = Path()
      ..moveTo(x, top)
      ..lineTo(x + w, top)
      ..lineTo(x + w, bottom)
      ..lineTo(x + w / 2, bottom - 5)
      ..lineTo(x, bottom)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [
          BiblePalette.ribbon,
          Color.lerp(BiblePalette.ribbon, Colors.white, 0.18)!,
          BiblePalette.ribbon,
        ]).createShader(Rect.fromLTWH(x, top, w, bottom - top)),
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.per != per;
}
