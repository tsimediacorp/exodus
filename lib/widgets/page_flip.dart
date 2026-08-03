import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/exodus_theme.dart';

/// Scroll physics for turning pages.
///
/// [PageScrollPhysics] settles almost instantly, which reads as a slide rather
/// than a page with mass. This uses a heavier spring and more damping so a turn
/// carries a little weight and comes to rest instead of snapping.
class PageTurnPhysics extends PageScrollPhysics {
  const PageTurnPhysics({super.parent});

  @override
  PageTurnPhysics applyTo(ScrollPhysics? ancestor) =>
      PageTurnPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 62,
        stiffness: 120,
        damping: 1.1,
      );
}

/// Wraps one page in a [PageView] so it folds about the spine as it turns.
///
/// The page being turned rotates about its inner edge with a perspective
/// transform, dims as it goes edge-on, and casts a lift shadow toward the
/// spine — the three cues that together read as paper rather than a slide.
class PageFlip extends StatelessWidget {
  /// This page's index.
  final int index;

  /// Live scroll position in page units, e.g. 1.4 means 40% into the turn from
  /// page 1 to page 2.
  final double page;

  final Widget child;

  const PageFlip({
    super.key,
    required this.index,
    required this.page,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // -1 fully turned to the left, 0 flat and facing, +1 still stacked right.
    final delta = (index - page).clamp(-1.0, 1.0);

    // The page in front turns away; pages underneath stay put, so the turning
    // sheet appears to lift off a stack rather than both sliding.
    if (delta > 0) {
      // Upcoming page: sits flat, revealed as the one above turns off it.
      return Opacity(
        opacity: (1 - delta * 0.35).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 1 - delta * 0.04,
          child: child,
        ),
      );
    }

    final t = -delta; // 0 → 1 as this page turns away to the left
    final angle = t * math.pi / 2.2; // stop short of edge-on; full 90° goes invisible

    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011) // perspective — the whole illusion lives here
        ..rotateY(-angle),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Paper darkens as it angles away from the reader.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    ExodusTheme.obsidian.withValues(alpha: 0.55 * t),
                    ExodusTheme.obsidian.withValues(alpha: 0.10 * t),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gutter shadow at the spine, so pages look bound rather than loose.
class SpineShadow extends StatelessWidget {
  const SpineShadow({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
