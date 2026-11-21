import 'package:flutter/material.dart';

/// The warm light behind a page, plus the noise that makes it drawable.
///
/// Two layers, and the second is the point.
///
/// The wash is a brass radial spread across the WHOLE surface. An earlier
/// version drew it into a fixed-height box, which cut the fade off mid-run and
/// left a hard line across the page — a radial gradient fades in a circle, but
/// its container still ends in a rectangle. Filling the surface means the only
/// edges are the screen's own.
///
/// That alone is not enough. A large, low-alpha wash over near-black cannot be
/// drawn smoothly at 8 bits per channel: the steps between one shade of
/// near-black and the next are wide enough to see, so the gradient resolves
/// into visible bands rather than a smooth fall of light. [_grain] fixes that
/// the way it has always been fixed — a tile of noise centred on mid grey,
/// composited at a few percent, perturbs each pixel by about one level so the
/// boundary between two bands stops being a straight line and becomes a ragged
/// mix of both. It is dithering, not decoration; if it ever reads as texture
/// it is too strong.
class PageBackdrop extends StatefulWidget {
  final Widget child;

  /// Where the light falls from. Above the top edge by default, so it reads as
  /// light landing on the page rather than a glow sitting on it.
  final Alignment origin;

  const PageBackdrop({
    super.key,
    required this.child,
    this.origin = const Alignment(-0.56, -1.28),
  });

  static const _grain = DecorationImage(
    image: AssetImage('assets/textures/grain.png'),
    repeat: ImageRepeat.repeat,
    opacity: 0.045,
    // The tile is deliberately hard-edged noise; smoothing it would blur away
    // the per-pixel variation that does the dithering.
    filterQuality: FilterQuality.none,
  );

  /// The light itself. Public so tests can hold it to its promises: it
  /// reaches zero alpha, so the screen edge never shows a band.
  static RadialGradient wash(Alignment origin) => RadialGradient(
        center: origin,
        radius: 1.15,
        colors: const [
          Color(0x1CC9A961), // brass at 0.11
          Color(0x0AC9A961), // brass at 0.04
          Color(0x00C9A961),
        ],
        stops: const [0.0, 0.38, 0.72],
      );

  @override
  State<PageBackdrop> createState() => _PageBackdropState();
}

/// Marks the surface the light is measured against.
///
/// Without one, each [PageBackdrop] lights its own box, which is right for a
/// page that fills the screen. Unfolded, a screen is split into rail, list
/// and thread, and three boxes lit separately are three suns with a hard
/// seam between each. Inside a frame every backdrop paints its slice of ONE
/// wash laid across the whole frame, so the panes read as a single surface
/// and the only edges are the screen's own.
class BackdropFrame extends StatefulWidget {
  final Widget child;
  final Alignment origin;

  const BackdropFrame({
    super.key,
    required this.child,
    this.origin = const Alignment(-0.56, -1.28),
  });

  static _BackdropFrameState? _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FrameScope>()
      ?.state;

  @override
  State<BackdropFrame> createState() => _BackdropFrameState();
}

class _BackdropFrameState extends State<BackdropFrame> {
  final GlobalKey _key = GlobalKey();

  RenderBox? get box => _key.currentContext?.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    return _FrameScope(
      state: this,
      origin: widget.origin,
      child: KeyedSubtree(
        key: _key,
        // The frame paints the wash itself, so anything transparent laid
        // over it (the rail, the list) is lit along with the panes.
        child: _Wash(
          origin: widget.origin,
          frame: null,
          child: widget.child,
        ),
      ),
    );
  }
}

class _FrameScope extends InheritedWidget {
  final _BackdropFrameState state;
  final Alignment origin;

  const _FrameScope({
    required this.state,
    required this.origin,
    required super.child,
  });

  @override
  bool updateShouldNotify(_FrameScope old) =>
      old.state != state || old.origin != origin;
}

class _PageBackdropState extends State<PageBackdrop> {
  @override
  Widget build(BuildContext context) {
    final frame = BackdropFrame._of(context);
    return _Wash(
      origin: frame?.widget.origin ?? widget.origin,
      frame: frame,
      child: widget.child,
    );
  }
}

/// The light and the grain under [child], measured against [frame] when
/// there is one.
class _Wash extends StatelessWidget {
  final Alignment origin;
  final _BackdropFrameState? frame;
  final Widget child;

  const _Wash({required this.origin, required this.frame, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropLight._(origin: origin, frame: frame),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(image: PageBackdrop._grain),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The wash itself, as a render object so it knows where it sits in the
/// frame at paint time.
@visibleForTesting
class BackdropLight extends LeafRenderObjectWidget {
  final Alignment origin;
  // ignore: library_private_types_in_public_api
  final _BackdropFrameState? frame;

  const BackdropLight._({required this.origin, required this.frame});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLight(origin, frame);

  @override
  void updateRenderObject(
      BuildContext context,
      // ignore: library_private_types_in_public_api
      _RenderLight renderObject) {
    renderObject
      ..origin = origin
      ..frame = frame
      ..markNeedsPaint();
  }
}

class _RenderLight extends RenderBox {
  Alignment origin;
  _BackdropFrameState? frame;

  _RenderLight(this.origin, this.frame);

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performResize() {
    super.performResize();
    // A pane can be moved without being resized (the list sliding in), and
    // the light has to follow, so every layout pass repaints.
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var lit = Offset.zero & size;
    final frameBox = frame?.box;
    if (frameBox != null && frameBox.hasSize && frameBox != this) {
      try {
        // Relative to the frame, not the screen, so a transform over the
        // whole frame (the unfold) carries the light with it.
        final at = localToGlobal(Offset.zero, ancestor: frameBox);
        lit = Rect.fromLTWH(
            -at.dx, -at.dy, frameBox.size.width, frameBox.size.height);
      } catch (_) {/* not under the frame this pass: light our own box */}
    }
    final paint = Paint()
      ..shader = PageBackdrop.wash(origin).createShader(lit.shift(offset));
    context.canvas.drawRect(offset & size, paint);
  }
}
