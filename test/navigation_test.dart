import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/screens/explore_screen.dart';
import 'package:exodus/screens/library_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';

/// The drawer is gone, so everything it held has to be reachable from the new
/// layout. A mode or a library link that lost its only route would be
/// invisible rather than broken — nothing would fail, it would just be gone.
void main() {
  testWidgets('Explore lists every mode, in the shell\'s stack order',
      (tester) async {
    final opened = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      home: ExploreScreen(onOpenMode: opened.add),
    ));
    // The cards rise into place on open; tapping mid-animation lands where
    // the card is about to be rather than where it is.
    await tester.pumpAndSettle();

    const expected = [
      'Counsel',
      'Coaching',
      'Devotional',
      'Bible Study',
      'Confessional',
      'Together',
    ];
    for (final name in expected) {
      expect(find.text(name), findsOneWidget, reason: '$name lost its route');
    }

    // Index must match HomeShell's stack, or a card opens the wrong mode.
    // The list scrolls, so bring each into view before tapping it.
    for (final name in expected) {
      await tester.ensureVisible(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name), warnIfMissed: true);
      await tester.pump();
    }
    expect(opened, [0, 1, 2, 3, 4, 5]);
  });

  testWidgets('Library keeps everything the drawer used to hold',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
    for (final name in [
      'Bible',
      'Saved verses',
      'Past exercises',
      'Journeys',
      'Weekly letter',
      'Memory',
    ]) {
      expect(find.text(name), findsOneWidget, reason: '$name lost its route');
    }
  });
}
