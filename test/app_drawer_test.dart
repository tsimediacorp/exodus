import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/conversation.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/app_drawer.dart';

/// The drawer's sections used to render on top of each other.
///
/// The cause was structural: a Column of fixed-height chrome wrapping the chat
/// list in an `Expanded`. Once the fixed part exceeded the drawer height — a
/// short screen, large type, or simply more modes — `Expanded` was handed a
/// negative constraint and the sections collided, which Flutter reports as a
/// vertical RenderFlex overflow.
///
/// These tests assert on VERTICAL overflow only. Horizontal is deliberately
/// ignored: widget tests render with a fallback font whose every glyph is a
/// full-em square, so "New conversation" measures 228px here against roughly
/// 110px in the app's actual Inter. Asserting on that would fail on a font
/// nobody ships rather than on the layout.
void main() {
  List<Conversation> conversations(int n) => [
        for (var i = 0; i < n; i++)
          Conversation(
            id: 'c$i',
            title: 'Conversation $i',
            messages: const [],
            updatedAt: DateTime(2026, 8, 28).subtract(Duration(hours: i)),
          ),
      ];

  /// Overflow errors raised while pumping, split by direction.
  late List<String> overflows;

  Future<void> openDrawer(WidgetTester tester, Size size, int convoCount,
      {double textScale = 1.0}) async {
    overflows = [];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exception.toString();
      if (message.contains('overflowed')) {
        overflows.add(message);
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ExodusTheme.build(),
      // Inside the app, so it actually reaches the drawer.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        drawer: AppDrawer(
          currentMode: 0,
          onSelectMode: (_) {},
          conversations: conversations(convoCount),
          currentConversationId: convoCount == 0 ? null : 'c0',
          onNewConversation: () {},
          onSelectConversation: (_) {},
          onDeleteConversation: (_) {},
          onOpenMemory: () {},
        ),
      ),
    ));
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  Iterable<String> verticalOverflows() =>
      overflows.where((o) => o.contains('bottom') || o.contains('top'));

  group('sections never collide', () {
    // 320x480 is the smallest phone worth supporting; 375x667 an iPhone SE.
    for (final size in [
      const Size(320, 480),
      const Size(375, 667),
      const Size(390, 844),
    ]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$label with a long chat list', (tester) async {
        await openDrawer(tester, size, 30);
        expect(verticalOverflows(), isEmpty);
      });

      testWidgets('$label with no chats at all', (tester) async {
        await openDrawer(tester, size, 0);
        expect(verticalOverflows(), isEmpty);
      });
    }

    testWidgets('with every section open on the smallest screen',
        (tester) async {
      await openDrawer(tester, const Size(320, 480), 30);
      // The section headers sit below thirty conversations, so scroll to the
      // library before opening it — that it needs scrolling at all is the
      // fix working.
      await tester.scrollUntilVisible(
        find.text('LIBRARY'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('LIBRARY'));
      await tester.pumpAndSettle();
      // A long chat list and the library open together is the worst case, and
      // the one the old layout could not survive.
      expect(verticalOverflows(), isEmpty);
      expect(find.text('Bible'), findsOneWidget);
      await tester.tap(find.text('LIBRARY'));
      await tester.pumpAndSettle();
    });

    testWidgets('at the largest accessibility text size', (tester) async {
      // Large type inflates the fixed chrome, which is one of the ways the old
      // layout tipped into a negative constraint.
      await openDrawer(tester, const Size(320, 480), 12, textScale: 2.0);
      expect(verticalOverflows(), isEmpty);
    });
  });

  group('structure', () {
    testWidgets('everything between header and Settings is one scroll view',
        (tester) async {
      // This is the fix itself. The old layout put the modes and the footer
      // links OUTSIDE the chat list's scroll view as fixed-height chrome, and
      // that fixed chrome outgrowing the drawer is what produced the negative
      // constraint. So it is not enough that a scrollable exists — the modes
      // have to be inside it, which is what would have failed before.
      // No conversations, so every section is on screen and instantiated —
      // the list is lazy, and an off-screen header simply would not exist yet.
      await openDrawer(tester, const Size(390, 844), 0);

      final scrollable =
          find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable));
      expect(scrollable, findsOneWidget);

      for (final label in ['Counsel', 'Together', 'CHATS', 'LIBRARY']) {
        expect(
          find.descendant(of: scrollable, matching: find.text(label)),
          findsOneWidget,
          reason: '$label is outside the scroll view — that is the old bug',
        );
      }

      // Settings is the one deliberate exception: pinned below the scroll.
      expect(find.descendant(of: scrollable, matching: find.text('Settings')),
          findsNothing);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('every mode is reachable', (tester) async {
      await openDrawer(tester, const Size(390, 844), 3);
      for (final label in [
        'Counsel',
        'Coaching',
        'Devotional',
        'Bible Study',
        'Confessional',
        'Together',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
    });

    testWidgets('Settings stays put with a long chat list', (tester) async {
      // Pinned deliberately: it is what you reach for when something is
      // broken, and that is the wrong moment to hunt through a scroll view.
      await openDrawer(tester, const Size(320, 480), 30);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('the last conversation is reachable by scrolling',
        (tester) async {
      await openDrawer(tester, const Size(320, 480), 40);
      await tester.dragUntilVisible(
        find.text('Conversation 39'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(find.text('Conversation 39'), findsOneWidget);
      expect(verticalOverflows(), isEmpty);
    });
  });

  group('collapsing', () {
    testWidgets('hides the chats but keeps the count visible', (tester) async {
      await openDrawer(tester, const Size(390, 844), 5);
      expect(find.text('Conversation 0'), findsOneWidget);
      // The count is what makes a collapsed section honest — without it,
      // closing the section reads as "my conversations are gone".
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.text('CHATS'));
      await tester.pumpAndSettle();

      expect(find.text('Conversation 0'), findsNothing);
      expect(find.text('5'), findsOneWidget);
      expect(verticalOverflows(), isEmpty);

      // Section state is static and outlives the widget, so restore it rather
      // than leaking a collapsed drawer into the next test.
      await tester.tap(find.text('CHATS'));
      await tester.pumpAndSettle();
    });

    testWidgets('the library opens and closes', (tester) async {
      await openDrawer(tester, const Size(390, 844), 2);
      expect(find.text('Bible'), findsNothing);

      await tester.tap(find.text('LIBRARY'));
      await tester.pumpAndSettle();
      expect(find.text('Bible'), findsOneWidget);
      expect(find.text('Journeys'), findsOneWidget);

      await tester.tap(find.text('LIBRARY'));
      await tester.pumpAndSettle();
      expect(find.text('Bible'), findsNothing);
    });
  });
}
