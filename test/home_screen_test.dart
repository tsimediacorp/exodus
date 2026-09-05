import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/screens/home_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/exodus_bottom_nav.dart';

void main() {
  Future<void> open(WidgetTester tester,
      {ValueChanged<String>? onOpen, VoidCallback? onNew}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      home: HomeScreen(
        onOpenConversation: onOpen ?? (_) {},
        onNewConversation: onNew ?? () {},
        onSeeAll: () {},
      ),
    ));
    await tester.pump();
  }

  group('home', () {
    testWidgets('greets and shows the day\'s verse', (tester) async {
      await open(tester);
      expect(find.text('Peace be with you.'), findsOneWidget);
      expect(find.text('Real conversations. A higher perspective.'),
          findsOneWidget);
      expect(find.text('TODAY’S VERSE'), findsOneWidget);
      expect(find.text('Conversations'), findsOneWidget);
    });

    testWidgets('an empty list invites a first conversation', (tester) async {
      var started = false;
      await open(tester, onNew: () => started = true);
      // Storage is unavailable in tests, so this is the genuine empty state.
      expect(find.textContaining('Start your first conversation'),
          findsOneWidget);
      await tester.tap(find.textContaining('Start your first conversation'));
      expect(started, isTrue);
    });

    testWidgets('"See all" is hidden when there is nothing to see',
        (tester) async {
      await open(tester);
      expect(find.text('See all'), findsNothing);
    });

    testWidgets('searching an empty list says so in the query\'s words',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'money');
      await tester.pump();
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });
  });

  group('bottom nav', () {
    Future<void> pumpNav(WidgetTester tester,
        {int? selected, ValueChanged<int>? onSelect, VoidCallback? onNew}) {
      return tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(
          bottomNavigationBar: ExodusBottomNav(
            selected: selected,
            onSelect: onSelect ?? (_) {},
            onNewChat: onNew ?? () {},
          ),
        ),
      ));
    }

    testWidgets('carries the five slots from the design', (tester) async {
      await pumpNav(tester, selected: 0);
      for (final label in ['Home', 'Explore', 'New Chat', 'Library', 'Profile']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('the selected tab is brass, the others are not',
        (tester) async {
      await pumpNav(tester, selected: ExodusBottomNav.library);
      final library = tester.widget<Text>(find.text('Library'));
      final home = tester.widget<Text>(find.text('Home'));
      expect(library.style?.color, ExodusTheme.brass);
      expect(home.style?.color, ExodusTheme.ironMist);
    });

    testWidgets('no tab is lit while a mode is open', (tester) async {
      // selected == null means "none of these four is where you are".
      await pumpNav(tester, selected: null);
      for (final label in ['Home', 'Explore', 'Library', 'Profile']) {
        expect(tester.widget<Text>(find.text(label)).style?.color,
            ExodusTheme.ironMist);
      }
    });

    testWidgets('New Chat is an action, never a selected tab', (tester) async {
      var started = false;
      await pumpNav(tester, selected: 0, onNew: () => started = true);
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(started, isTrue);
      // It has no selected styling to give it, whatever tab is active.
      expect(tester.widget<Text>(find.text('New Chat')).style?.color,
          ExodusTheme.ironMist);
    });

    testWidgets('tapping a tab reports its index', (tester) async {
      int? picked;
      await pumpNav(tester, selected: 0, onSelect: (i) => picked = i);
      await tester.tap(find.text('Profile'));
      expect(picked, ExodusBottomNav.profile);
    });
  });
}
