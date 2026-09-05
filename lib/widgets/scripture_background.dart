import 'package:flutter/material.dart';

import '../services/card_backgrounds.dart';
import 'ridge_backdrop.dart';

/// Whatever sits behind a scripture card.
///
/// A photograph from assets/backgrounds/ when any exist, and the painted
/// landscape otherwise. The card itself does not care which it gets.
///
/// The scrim is applied HERE rather than inside either source, because it is
/// what guarantees the verse stays readable — and a photograph is far less
/// predictable than something we painted. Without it, one bright sky in the
/// set would make its card illegible and nothing would catch it.
class ScriptureBackground extends StatelessWidget {
  /// Stable per verse, so a passage always gets the same scene.
  final String seed;

  const ScriptureBackground({super.key, required this.seed});

  @override
  Widget build(BuildContext context) {
    final image = CardBackgrounds.pick(seed);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (image == null)
          RidgeBackdrop(seed: seed)
        else
          Image.asset(
            image,
            fit: BoxFit.cover,
            // A missing or corrupt file must not take the reply down with it.
            errorBuilder: (_, __, ___) => RidgeBackdrop(seed: seed),
          ),
        // The text sits on the left, so that side is darkened whatever the
        // image happens to do there.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                const Color(0xFF060A14).withValues(alpha: 0.90),
                const Color(0xFF060A14).withValues(alpha: 0.55),
                const Color(0xFF060A14).withValues(alpha: 0.12),
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
