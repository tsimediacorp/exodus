import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/screens/chat_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';

/// The empty state is the FIRST thing anyone sees on a fresh install, and it
/// was the one artboard of the chat redesign that never got implemented — so
/// the app shipped looking identical to the previous build even though the
/// thread, composer and app bar had all changed. Nothing caught it, because
/// the bubble redesign only appears once a conversation exists.
void main() {
  testWidgets('the welcome state uses the redesigned starters',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      home: const ChatScreen(),
    ));
    await tester.pump();

    expect(find.text('Walk in His design.'), findsOneWidget);
    expect(
        find.text('How do we lead our marriage spiritually as newlyweds?'),
        findsOneWidget);

    // The outline came off: four bordered cards in a column read as a form to
    // fill in. Fill alone separates a starter from the ground.
    final cards = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(InkWell), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration as BoxDecoration)
        .where((d) => d.color == ExodusTheme.midnight)
        .toList();

    expect(cards, isNotEmpty, reason: 'no starter cards found');
    for (final card in cards) {
      expect(card.border, isNull,
          reason: 'starters should have no outline');
      expect(card.borderRadius, BorderRadius.circular(14));
    }
  });
}
