import 'package:flutter/material.dart';
import '../theme/exodus_theme.dart';

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
class PageBackdrop extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: origin,
                  radius: 1.15,
                  colors: [
                    ExodusTheme.brass.withValues(alpha: 0.11),
                    ExodusTheme.brass.withValues(alpha: 0.04),
                    ExodusTheme.brass.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.38, 0.72],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(image: _grain),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
