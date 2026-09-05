import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/services/card_backgrounds.dart';
import 'package:exodus/widgets/ridge_backdrop.dart';
import 'package:exodus/widgets/scripture_background.dart';

/// The scrim is the only thing standing between a bright photograph and an
/// unreadable verse, and the failure is silent — the card renders, it just
/// cannot be read. These pin the values that measurement established.
///
/// tools/backgrounds/check_contrast.py does the real measurement against the
/// actual artwork; this catches the far more likely regression, which is
/// someone lightening the scrim because the photo looks nicer that way.
void main() {
  tearDown(() => CardBackgrounds.debugSetAvailable(null));

  group('the scrim keeps the verse readable', () {
    test('never lighter than the measured floor', () {
      for (final alpha in ScriptureBackground.scrimAlphas) {
        expect(alpha, greaterThanOrEqualTo(ScriptureBackground.minimumScrimAlpha),
            reason: 'A lighter scrim than this was measured to put real '
                'photographs in assets/backgrounds/ under 4.5:1. Re-run '
                'tools/backgrounds/check_contrast.py before changing it.');
      }
    });

    test('darkest at the left, where the verse begins', () {
      const alphas = ScriptureBackground.scrimAlphas;
      for (var i = 1; i < alphas.length; i++) {
        expect(alphas[i], lessThanOrEqualTo(alphas[i - 1]),
            reason: 'the gradient must not brighten towards the left');
      }
    });

    test('the stops span the full width and match the alphas', () {
      const stops = ScriptureBackground.scrimStops;
      expect(stops.length, ScriptureBackground.scrimAlphas.length);
      expect(stops.first, 0.0);
      expect(stops.last, 1.0);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThan(stops[i - 1]));
      }
    });
  });

  group('what gets drawn', () {
    Widget host() => const MaterialApp(
          home: Scaffold(
            body: SizedBox(
                width: 340,
                height: 215,
                child: ScriptureBackground(seed: '1 Peter 5:7')),
          ),
        );

    testWidgets('the painted landscape when there is no artwork',
        (tester) async {
      CardBackgrounds.debugSetAvailable(const []);
      await tester.pumpWidget(host());
      expect(find.byType(RidgeBackdrop), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a photograph when there is', (tester) async {
      CardBackgrounds.debugSetAvailable(
          const ['assets/backgrounds/canyon-dusk.jpg']);
      await tester.pumpWidget(host());
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the scrim is drawn over whichever source is used',
        (tester) async {
      CardBackgrounds.debugSetAvailable(const []);
      await tester.pumpWidget(host());
      final scrim = tester.widget<DecoratedBox>(find.descendant(
        of: find.byType(ScriptureBackground),
        matching: find.byType(DecoratedBox),
      ));
      final gradient =
          (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.length, ScriptureBackground.scrimAlphas.length);
      expect(gradient.stops, ScriptureBackground.scrimStops);
      // The scrim sits after the backdrop in the stack, or it does nothing.
      final stack = tester.widget<Stack>(find.descendant(
        of: find.byType(ScriptureBackground),
        matching: find.byType(Stack),
      ));
      expect(stack.children.last, isA<DecoratedBox>());
    });
  });
}
