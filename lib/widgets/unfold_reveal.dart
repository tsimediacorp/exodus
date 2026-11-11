import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/exodus_layout.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// The moment the phone opens.
///
/// When the width class goes from compact to expanded, a seam of brass light
/// runs down the centre — where the fold is — and two panels of the night
/// background part from it like the covers of a book, revealing the wider
/// layout already in place underneath. Folding back gets the quiet version:
/// the smaller screen simply settles in.
///
/// Two constraints shape it:
///  * The layout underneath is final from the first frame. This is a veil
///    over the change, not an animation OF the change, so nothing is tapped
///    mid-flight and state never depends on the animation finishing. Apple's
///    guidance is to avoid elements jumping around on a fold; here they do
///    not move at all.
///  * It never blocks input and never runs with Reduce Motion on.
class UnfoldReveal extends StatefulWidget {
  final Widget child;

  const UnfoldReveal({super.key, required this.child});

  @override
  State<UnfoldReveal> createState() => _UnfoldRevealState();
}

enum _Change { none, unfold, fold }

class _UnfoldRevealState extends State<UnfoldReveal>
    with SingleTickerProviderStateMixin {
  // Created eagerly: a lazy controller would first be touched in dispose()
  // on a phone that never folded, building a ticker on a dead element.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _change = _Change.none);
        }
      });
  }

  ExodusWidth? _last;
  _Change _change = _Change.none;

  static const _unfoldDuration = Duration(milliseconds: 1150);
  static const _foldDuration = Duration(milliseconds: 380);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = ExodusLayout.widthOf(context);
    final was = _last;
    _last = now;
    // First build is not a change: opening the app unfolded should not play
    // the unfold.
    if (was == null || was == now) return;
    if (ExodusLayout.reduceMotion(context)) return;

    _change = now == ExodusWidth.expanded ? _Change.unfold : _Change.fold;
    _c
      ..stop()
      ..duration = _change == _Change.unfold ? _unfoldDuration : _foldDuration
      ..value = 0;
    // Start after this frame lays out, so the veil's first frame (fully
    // closed) is what shows while the new layout is built underneath it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _change == _Change.none) return;
      if (_change == _Change.unfold) HapticFeedback.lightImpact();
      _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_change == _Change.none) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        if (_change == _Change.fold) {
          final e = Curves.easeOutCubic.transform(t);
          return ColoredBox(
            color: ExodusTheme.obsidian,
            child: Opacity(
              opacity: 0.35 + 0.65 * e,
              child: Transform.scale(scale: 1.025 - 0.025 * e, child: child),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // Ground under the scaling layout: while it is slightly smaller
            // than the screen, the sliver around it must be the night
            // background, not bare surface with the veil's glow on it.
            const ColoredBox(color: ExodusTheme.obsidian),
            // The layout settles forward slightly as the covers open, so it
            // reads as being revealed rather than painted.
            Transform.scale(
              scale: 0.965 +
                  0.035 *
                      Curves.easeOutCubic.transform(_interval(t, 0.30, 1.0)),
              child: child,
            ),
            IgnorePointer(child: CustomPaint(painter: _VeilPainter(t))),
            IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: _shieldOpacity(t),
                  child: Transform.scale(
                    scale: 0.9 +
                        0.2 * Curves.easeOut.transform(_interval(t, 0.0, 0.5)),
                    child: const ExodusShield(size: 64),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _shieldOpacity(double t) {
    final rise = Curves.easeOut.transform(_interval(t, 0.0, 0.18));
    final fall = Curves.easeIn.transform(_interval(t, 0.26, 0.46));
    return (rise * (1 - fall)).clamp(0.0, 1.0);
  }
}

double _interval(double t, double begin, double end) =>
    ((t - begin) / (end - begin)).clamp(0.0, 1.0);

/// The two covers and the light between them.
class _VeilPainter extends CustomPainter {
  final double t;

  _VeilPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Covers: closed until 0.28, then part on a long ease so they leave
    // quickly and arrive at the edges gently.
    final open = Curves.easeInOutCubic.transform(_interval(t, 0.28, 0.92));
    final half = cx * (1 - open);
    final coverAlpha = 1 - Curves.easeIn.transform(_interval(t, 0.75, 1.0));

    if (half > 0.5 && coverAlpha > 0) {
      final left = Rect.fromLTWH(0, 0, half, h);
      final right = Rect.fromLTWH(w - half, 0, half, h);
      for (final r in [left, right]) {
        final isLeft = r.left == 0;
        canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                ExodusTheme.obsidian.withValues(alpha: coverAlpha),
                Color.lerp(ExodusTheme.obsidian, ExodusTheme.midnight, 0.8)!
                    .withValues(alpha: coverAlpha),
              ],
            ).createShader(r),
        );
        // A warm lip on each cover's inner edge, as if lit from the gap.
        final edgeX = isLeft ? r.right : r.left;
        final lip = Rect.fromLTWH(isLeft ? edgeX - 26 : edgeX, 0, 26, h);
        canvas.drawRect(
          lip,
          Paint()
            ..shader = LinearGradient(
              begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
              end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                ExodusTheme.brass.withValues(alpha: 0.32 * coverAlpha),
                ExodusTheme.brass.withValues(alpha: 0),
              ],
            ).createShader(lip),
        );
      }
    }

    // The seam: grows from the centre outward along the fold, flares as the
    // covers start to move, then fades as the light "fills" the room.
    final grow = Curves.easeOutCubic.transform(_interval(t, 0.0, 0.32));
    final fade = Curves.easeIn.transform(_interval(t, 0.45, 0.85));
    final seamAlpha = (1 - fade).clamp(0.0, 1.0);
    if (seamAlpha <= 0) return;

    final seamH = h * grow;
    final top = (h - seamH) / 2;
    final flare = 1 + 2.2 * math.sin(math.pi * _interval(t, 0.2, 0.6));
    final seam = Rect.fromLTWH(cx - 1.2, top, 2.4, seamH);

    // Wide soft bloom first, then the bright core. A gradient rather than a
    // blur: a blur's halo is clipped flat at the screen edge and shows as a
    // hard block, and a gradient costs the GPU nothing.
    final bloomHalf = 34 * flare;
    final bloom = Rect.fromLTWH(cx - bloomHalf, top, bloomHalf * 2, seamH);
    canvas.drawRect(
      bloom,
      Paint()
        ..shader = LinearGradient(
          colors: [
            ExodusTheme.brass.withValues(alpha: 0),
            ExodusTheme.brass.withValues(alpha: 0.30 * seamAlpha),
            ExodusTheme.brass.withValues(alpha: 0),
          ],
        ).createShader(bloom),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(seam, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ExodusTheme.brassGlow.withValues(alpha: 0),
            ExodusTheme.brassGlow.withValues(alpha: seamAlpha),
            Colors.white.withValues(alpha: 0.9 * seamAlpha),
            ExodusTheme.brassGlow.withValues(alpha: seamAlpha),
            ExodusTheme.brassGlow.withValues(alpha: 0),
          ],
          stops: const [0, 0.25, 0.5, 0.75, 1],
        ).createShader(seam),
    );
  }

  @override
  bool shouldRepaint(_VeilPainter old) => old.t != t;
}
