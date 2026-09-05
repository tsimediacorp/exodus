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

  /// How hard the scrim presses at the left edge, the middle, and the right.
  ///
  /// These are measured, not chosen by eye. The verse sits in an Expanded and
  /// so runs to roughly four fifths of the card — NOT just the left third —
  /// while every photograph in the set puts its sun in the upper right. The
  /// first version of this gradient faded to 0.12 at the right edge, which
  /// left the end of each line sitting on lit sky: three of eleven images fell
  /// under 4.5:1 for the verse, and eight of eleven under 3:1 for the brass
  /// citation, which is the smaller and more fragile text of the two.
  ///
  /// At these values every image in the set clears both, with a blown
  /// highlight still arriving at roughly 137/250 — a warm glow rather than a
  /// grey slab. tools/backgrounds/check_contrast.py re-measures the whole
  /// folder; run it after adding artwork.
  static const List<double> scrimAlphas = [0.91, 0.68, 0.44];
  static const List<double> scrimStops = [0.0, 0.46, 1.0];

  /// The floor the measurement established. A lighter scrim than this has been
  /// shown to make real photographs in this set unreadable.
  static const double minimumScrimAlpha = 0.44;

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
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                for (final a in scrimAlphas)
                  const Color(0xFF060A14).withValues(alpha: a),
              ],
              stops: scrimStops,
            ),
          ),
        ),
      ],
    );
  }
}
