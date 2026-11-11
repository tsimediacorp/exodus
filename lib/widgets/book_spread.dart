import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/exodus_theme.dart';

/// Two facing pages and a leaf that turns between them.
///
/// Unfolded, the Duo is an open book held in two hands, and its fold runs
/// exactly where a book's spine would. This puts the spine there.
///
/// Turning forward, the right-hand page lifts about the spine, rises to
/// edge-on, and comes down on the left as the back of that leaf, which is
/// the next spread's left page. Underneath it the next right page is
/// already waiting. Turning back is the same motion reversed. The leaf is
/// shaded as it angles away and throws a shadow across the page it is about
/// to cover, which is most of what makes it read as paper.
///
/// Gestures are owned here rather than by a PageView, because a PageView
/// slides its children sideways and a book page does not move sideways at
/// all. Taps fall through to the pages, so verses stay selectable; while a
/// leaf is in motion the pages ignore pointers, so a turn can never select
/// a verse by accident.
class BookSpread extends StatefulWidget {
  /// Number of single pages. The spread count is ceil(pageCount / 2).
  final int pageCount;

  /// The spread to show. Changing it from outside turns to it (one spread
  /// away) or jumps (further).
  final int spread;

  /// Builds page [index]; past the last page, [blankBuilder] is used.
  final Widget Function(BuildContext context, int index) pageBuilder;
  final WidgetBuilder blankBuilder;

  /// Called when a turn settles on a new spread.
  final ValueChanged<int> onSpreadChanged;

  /// True to skip the turning animation (Reduce Motion).
  final bool reduceMotion;

  const BookSpread({
    super.key,
    required this.pageCount,
    required this.spread,
    required this.pageBuilder,
    required this.blankBuilder,
    required this.onSpreadChanged,
    this.reduceMotion = false,
  });

  static int spreadCountFor(int pages) => math.max(1, (pages + 1) ~/ 2);

  @override
  State<BookSpread> createState() => _BookSpreadState();
}

class _BookSpreadState extends State<BookSpread>
    with SingleTickerProviderStateMixin {
  /// Position in spreads: 2.0 is resting on spread 2, 2.4 is 40% through
  /// turning from 2 to 3.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.spread.toDouble(),
  );

  double _width = 1;

  int get _spreadCount => BookSpread.spreadCountFor(widget.pageCount);

  @override
  void didUpdateWidget(BookSpread old) {
    super.didUpdateWidget(old);
    final target = widget.spread.clamp(0, _spreadCount - 1);
    if ((_pos.value - target).abs() < 0.001 && !_pos.isAnimating) return;
    if (_pos.isAnimating) return; // a turn in flight will settle itself
    if ((target - _pos.value).abs() <= 1.01 && !widget.reduceMotion) {
      _settleTo(target, velocity: 0);
    } else {
      _pos.value = target.toDouble();
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  // ---- Gesture ----

  void _onDragUpdate(DragUpdateDetails d) {
    // A full turn is the width of one page: drag from the outer edge to the
    // spine and the leaf is upright; on to the far edge and it has landed.
    final perSpread = _width;
    final next = _pos.value - d.primaryDelta! / perSpread;
    // Resist past the covers instead of stopping dead, so the end of a
    // chapter feels like the end of a book rather than a wall.
    final max = (_spreadCount - 1).toDouble();
    double v = next;
    if (next < 0) v = next * 0.25;
    if (next > max) v = max + (next - max) * 0.25;
    _pos.value = v;
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = -(d.primaryVelocity ?? 0) / _width; // spreads/sec
    final base = _pos.value.floorToDouble();
    final frac = _pos.value - base;
    double target;
    if (velocity.abs() > 0.6) {
      target = velocity > 0 ? base + 1 : base;
    } else {
      target = frac > 0.5 ? base + 1 : base;
    }
    target = target.clamp(0, (_spreadCount - 1).toDouble());
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
      const SpringDescription(mass: 1, stiffness: 120, damping: 21),
      _pos.value,
      target.toDouble(),
      velocity,
    );
    _pos.animateWith(sim).whenCompleteOrCancel(() {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth / 2;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _pos,
          builder: (context, _) => _spreadAt(context, _pos.value),
        ),
      );
    });
  }

  Widget _spreadAt(BuildContext context, double position) {
    final clamped = position.clamp(0.0, (_spreadCount - 1).toDouble());
    final base = clamped.floor();
    final t = clamped - base;

    // Resting: a plain, fully interactive spread.
    if (t < 0.0005) {
      return _Spread(
        left: _page(context, base * 2),
        right: _page(context, base * 2 + 1),
      );
    }

    final leftNow = _page(context, base * 2);
    final rightNext = _page(context, base * 2 + 3);
    final turning = t <= 0.5
        // Front of the leaf: this spread's right page, lifting.
        ? _page(context, base * 2 + 1)
        // Back of the leaf: next spread's left page, coming down.
        : _page(context, base * 2 + 2);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Spread(left: leftNow, right: rightNext),
          _Leaf(t: t, child: turning),
        ],
      ),
    );
  }
}

/// Two pages either side of a spine.
class _Spread extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _Spread({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            Expanded(child: right),
          ],
        ),
        const IgnorePointer(child: _Spine()),
      ],
    );
  }
}

/// The turning leaf, drawn over whichever half it is currently above.
class _Leaf extends StatelessWidget {
  /// 0 flat on the right, 0.5 upright at the spine, 1 flat on the left.
  final double t;
  final Widget child;

  const _Leaf({required this.t, required this.child});

  @override
  Widget build(BuildContext context) {
    final onRight = t <= 0.5;
    // 0 → π/2 on the way up, π/2 → 0 on the way down.
    final lift = onRight ? t * 2 : (1 - t) * 2; // 0 flat .. 1 upright
    final angle = lift * math.pi / 2;
    // Stop just short of edge-on so the leaf never vanishes to a hairline.
    final shown = math.min(angle, math.pi / 2 * 0.985);

    // Shadow the leaf throws on the page it is about to cover: strongest
    // as it comes down, nothing while it is still flat on its own side.
    final cast = math.sin(lift * math.pi / 2) * 0.55;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: onRight
              ? _CastShadow(strength: cast * 0.5, fromRight: true)
              : _turned(shown, lift, alignment: Alignment.centerRight,
                  sign: -1),
        ),
        Expanded(
          child: onRight
              ? _turned(shown, lift, alignment: Alignment.centerLeft, sign: 1)
              : _CastShadow(strength: cast * 0.5, fromRight: false),
        ),
      ],
    );
  }

  Widget _turned(double angle, double lift,
      {required Alignment alignment, required double sign}) {
    return Transform(
      alignment: alignment,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(sign * -angle),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Paper darkens toward the spine as it angles away from the light,
          // with a faint brass sheen along the curl.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: sign > 0 ? Alignment.centerLeft : Alignment.centerRight,
                end: sign > 0 ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  Colors.black.withValues(alpha: 0.55 * lift),
                  ExodusTheme.brass.withValues(alpha: 0.06 * lift),
                  Colors.black.withValues(alpha: 0.18 * lift),
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CastShadow extends StatelessWidget {
  final double strength;
  final bool fromRight;

  const _CastShadow({required this.strength, required this.fromRight});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromRight ? Alignment.centerRight : Alignment.centerLeft,
          end: fromRight ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            Colors.black.withValues(alpha: strength),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.7],
        ),
      ),
    );
  }
}

/// The gutter: shadow falling into the binding from both pages, and a
/// hairline of brass where they meet.
class _Spine extends StatelessWidget {
  const _Spine();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 44,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ExodusTheme.brass.withValues(alpha: 0),
                      ExodusTheme.brass.withValues(alpha: 0.35),
                      ExodusTheme.brass.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
