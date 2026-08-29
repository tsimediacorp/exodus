import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/screens/chat_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/exodus_shield.dart';

/// The top bar carries the mark now.
///
/// Before this it was a stock Material bar: a hamburger, a centred label and
/// no brand at all once a conversation was open — which is the screen people
/// spend all their time on. The shield does both jobs.
void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      home: const ChatScreen(),
    ));
    await tester.pump();
  }

  testWidgets('the shield sits in the bar and is the menu button',
      (tester) async {
    await open(tester);

    final shield = find.descendant(
        of: find.byType(AppBar), matching: find.byType(ExodusShield));
    expect(shield, findsOneWidget, reason: 'the bar carries no mark');

    // It has to announce itself as a menu; a shield that silently opens a
    // drawer is not discoverable.
    final semantics = tester.getSemantics(shield);
    expect(semantics.label, contains('Menu'));
  });

  testWidgets('there is no stock hamburger any more', (tester) async {
    await open(tester);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.menu)),
      findsNothing,
    );
  });

  testWidgets('new-conversation is the one brass action', (tester) async {
    await open(tester);
    final add = tester.widget<Icon>(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.add_rounded)));
    expect(add.color, ExodusTheme.brass);

    final search = tester.widget<Icon>(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.search_rounded)));
    expect(search.color, ExodusTheme.ironMist);
  });

  testWidgets('with no conversation the wordmark stands in', (tester) async {
    await open(tester);
    expect(find.text('EXODUS'), findsOneWidget);
  });

  testWidgets('search is unavailable when there is nothing to search',
      (tester) async {
    await open(tester);
    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.search_rounded),
        matching: find.byType(IconButton)));
    expect(button.onPressed, isNull);
  });
}
