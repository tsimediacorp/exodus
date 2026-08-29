import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/screens/chat_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';

/// The warm light behind the thread used to be drawn into a fixed-height box.
/// A radial gradient fades to transparent in a CIRCLE, but its container still
/// ends in a RECTANGLE — so the fade was cut off mid-way and drew a hard
/// horizontal line across the conversation. An opaque app bar added a second
/// seam above it.
void main() {
  Future<Scaffold> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      home: const ChatScreen(),
    ));
    await tester.pump();
    return tester.widget<Scaffold>(find.byType(Scaffold).first);
  }

  testWidgets('the light fills the stack rather than a fixed box',
      (tester) async {
    await open(tester);

    // Any bounded box holding the brass gradient is the bug coming back.
    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient is RadialGradient)
        .toList();
    expect(gradients, isNotEmpty, reason: 'the warm light is gone');

    for (final decoration in gradients) {
      final radial = decoration.gradient as RadialGradient;
      // It has to actually reach zero alpha, or the screen edge shows a band.
      expect(radial.colors.last.a, 0);
    }
  });

  testWidgets('the body runs behind the bar so the wash is unbroken',
      (tester) async {
    final scaffold = await open(tester);
    expect(scaffold.extendBodyBehindAppBar, isTrue);
  });

  testWidgets('the bar is transparent, not a second edge', (tester) async {
    await open(tester);
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, Colors.transparent);
    // Material 3 tints a bar when content scrolls under it, which would put
    // the hard edge straight back.
    expect(bar.scrolledUnderElevation, 0);
  });

  testWidgets('content still clears the bar it runs behind', (tester) async {
    await open(tester);
    // The welcome heading must not sit underneath the transparent bar.
    final headingTop = tester.getTopLeft(find.text('Walk in His design.')).dy;
    final barBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    expect(headingTop, greaterThan(barBottom),
        reason: 'content is hidden behind the app bar');
  });
}
