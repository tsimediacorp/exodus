import 'dart:math';

import 'package:flutter/material.dart';

/// A painted landscape behind a scripture card.
///
/// Painted rather than photographed on purpose. Stock photography carries
/// licensing that has to be cleared per image and shipped in the bundle, and a
/// fixed set of photos stops feeling fresh the third time you see one. This
/// draws receding ridges under a low sun, and the composition is seeded from
/// the verse reference — so 1 Peter 5:7 always looks like itself, and the next
/// verse looks like something else.
///
/// If real photography is wanted later, only this widget changes.
class RidgeBackdrop extends StatelessWidget {
  /// Anything stable — the verse reference. The same seed always paints the
  /// same scene, which matters because a card that reshuffled on every rebuild
  /// would shimmer as you scrolled.
  final String seed;

  const RidgeBackdrop({super.key, required this.seed});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RidgePainter(seed: seed),
      isComplex: true,
      willChange: false,
      size: Size.infinite,
    );
  }
}

/// One time of day. Kept deliberately narrow in hue: these sit inside an app
/// built on obsidian and brass, and a green or purple sky would read as a
/// stock photo dropped into someone else's design.
class _Palette {
  final Color skyTop;
  final Color skyBottom;
  final Color sun;
  final Color haze;
  final Color near;

  const _Palette({
    required this.skyTop,
    required this.skyBottom,
    required this.sun,
    required this.haze,
    required this.near,
  });
}

const List<_Palette> _palettes = [
  // Dawn gold — the reference image.
  _Palette(
    skyTop: Color(0xFF0B1426),
    skyBottom: Color(0xFF2A3A52),
    sun: Color(0xFFF3C97A),
    haze: Color(0xFF6E7C93),
    near: Color(0xFF0A0F1C),
  ),
  // Dusk copper.
  _Palette(
    skyTop: Color(0xFF120E22),
    skyBottom: Color(0xFF3D2E3E),
    sun: Color(0xFFE0A26A),
    haze: Color(0xFF7A6A78),
    near: Color(0xFF0C0A16),
  ),
  // Cold morning.
  _Palette(
    skyTop: Color(0xFF0A1420),
    skyBottom: Color(0xFF33465C),
    sun: Color(0xFFDCE4EC),
    haze: Color(0xFF6C8098),
    near: Color(0xFF080E18),
  ),
  // High noon haze.
  _Palette(
    skyTop: Color(0xFF0D1A2C),
    skyBottom: Color(0xFF46587A),
    sun: Color(0xFFF6E2B4),
    haze: Color(0xFF7E8FA8),
    near: Color(0xFF0A1120),
  ),
];

class _RidgePainter extends CustomPainter {
  final String seed;
  const _RidgePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    // Deterministic from the reference: the same verse paints the same scene.
    final random = Random(seed.hashCode);
    final palette = _palettes[seed.hashCode.abs() % _palettes.length];
    final rect = Offset.zero & size;

    // The sun sits on the right, because the text sits on the left. Kept in
    // the upper band so the ridges have somewhere to catch the light.
    final sunX = size.width * (0.72 + random.nextDouble() * 0.2);
    final sunY = size.height * (0.16 + random.nextDouble() * 0.22);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.skyTop, palette.skyBottom],
        ).createShader(rect),
    );

    // Glow first, so every ridge drawn after it sits in front of the light.
    canvas.drawCircle(
      Offset(sunX, sunY),
      size.height * 1.05,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.sun.withValues(alpha: 0.55),
            palette.sun.withValues(alpha: 0.16),
            palette.sun.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.32, 1.0],
        ).createShader(
            Rect.fromCircle(center: Offset(sunX, sunY), radius: size.height * 1.05)),
    );
    canvas.drawCircle(
        Offset(sunX, sunY),
        size.height * 0.07,
        Paint()..color = palette.sun.withValues(alpha: 0.85));

    // Ridges back to front. Each is darker and lower than the one behind it,
    // which is what reads as distance — atmospheric perspective, not scale.
    const layers = 5;
    for (var i = 0; i < layers; i++) {
      final depth = i / (layers - 1); // 0 far … 1 near
      final baseline = size.height * (0.42 + depth * 0.46);
      final amplitude = size.height * (0.10 + random.nextDouble() * 0.13) *
          (0.55 + depth * 0.8);

      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, baseline);

      // Two sine components at different frequencies: one alone reads as a
      // wave, two make a ridgeline.
      final phase1 = random.nextDouble() * pi * 2;
      final phase2 = random.nextDouble() * pi * 2;
      final freq1 = 1.1 + random.nextDouble() * 1.4;
      final freq2 = 2.6 + random.nextDouble() * 2.6;

      for (double x = 0; x <= size.width; x += 3) {
        final t = x / size.width;
        final y = baseline -
            sin(t * pi * freq1 + phase1) * amplitude -
            sin(t * pi * freq2 + phase2) * amplitude * 0.32;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();

      final colour = Color.lerp(palette.haze, palette.near, 0.25 + depth * 0.75)!;
      canvas.drawPath(
        path,
        Paint()
          ..color = colour.withValues(alpha: 0.72 + depth * 0.28)
          ..style = PaintingStyle.fill,
      );
    }

  }

  @override
  bool shouldRepaint(_RidgePainter old) => old.seed != seed;
}
