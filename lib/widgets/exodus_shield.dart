import 'package:flutter/material.dart';
import '../theme/exodus_theme.dart';

/// EXODUS shield mark — a heater shield with an embedded cross.
/// Drawn entirely with CustomPainter so it scales cleanly to any size.
class ExodusShield extends StatelessWidget {
  final double size;
  final bool glow;

  const ExodusShield({super.key, this.size = 96, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(painter: _ShieldPainter(glow: glow)),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  final bool glow;
  _ShieldPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Shield path — classic heater shape
    final path = Path()
      ..moveTo(w * 0.08, h * 0.08)
      ..lineTo(w * 0.92, h * 0.08)
      ..lineTo(w * 0.92, h * 0.50)
      ..quadraticBezierTo(w * 0.92, h * 0.85, w * 0.50, h * 0.98)
      ..quadraticBezierTo(w * 0.08, h * 0.85, w * 0.08, h * 0.50)
      ..close();

    // Outer glow halo
    if (glow) {
      final haloPaint = Paint()
        ..color = ExodusTheme.covenantBlue.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawPath(path, haloPaint);
    }

    // Shield body gradient (deep navy → midnight)
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A3066), Color(0xFF0E1A33)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, bodyPaint);

    // Inner highlight band (subtle inner bevel)
    final highlight = Paint()
      ..color = ExodusTheme.covenantGlow.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012;
    canvas.save();
    canvas.translate(w * 0.02, h * 0.02);
    canvas.scale(0.96, 0.96);
    canvas.drawPath(path, highlight);
    canvas.restore();

    // Brass border
    final border = Paint()
      ..color = ExodusTheme.brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025;
    canvas.drawPath(path, border);

    // Cross — vertical bar
    final crossPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ExodusTheme.brassGlow, ExodusTheme.brass],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final verticalBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.46, h * 0.22, w * 0.08, h * 0.55),
      Radius.circular(w * 0.01),
    );
    canvas.drawRRect(verticalBar, crossPaint);

    // Cross — horizontal bar
    final horizontalBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.30, h * 0.36, w * 0.40, h * 0.08),
      Radius.circular(w * 0.01),
    );
    canvas.drawRRect(horizontalBar, crossPaint);

    // Cross glow
    if (glow) {
      final crossGlow = Paint()
        ..color = ExodusTheme.brass.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(verticalBar, crossGlow);
      canvas.drawRRect(horizontalBar, crossGlow);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
