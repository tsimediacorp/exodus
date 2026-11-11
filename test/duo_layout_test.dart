import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/layout/exodus_layout.dart';
import 'package:exodus/screens/explore_screen.dart';
import 'package:exodus/screens/home_screen.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/book_spread.dart';
import 'package:exodus/widgets/exodus_nav_rail.dart';
import 'package:exodus/widgets/unfold_reveal.dart';

import 'support/real_fonts.dart';

/// iPhone Duo, from the simulator's own device profile (pixels / 3).
const outer = Size(466, 678);
const inner = Size(669, 951);
const innerSideways = Size(951, 669);

void setScreen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadRealFonts);

  group('width classes', () {
    test('folded is compact, unfolded is expanded, either way up', () {
      expect(ExodusLayout.classify(outer.width), ExodusWidth.compact);
      expect(ExodusLayout.classify(outer.height), ExodusWidth.expanded,
          reason: 'outer screen sideways is 678pt — wide enough for a rail');
      expect(ExodusLayout.classify(inner.width), ExodusWidth.expanded);
      expect(ExodusLayout.classify(innerSideways.width), ExodusWidth.expanded);
      // The largest ordinary phone in portrait must stay compact.
      expect(ExodusLayout.classify(440), ExodusWidth.compact);
    });

    test('only the sideways inner screen has room for list and thread', () {
      expect(inner.width >= ExodusLayout.twoPaneMinWidth, isFalse);
      expect(innerSideways.width >= ExodusLayout.twoPaneMinWidth, isTrue);
    });
  });

  group('rail', () {
    testWidgets('modes open in the same order Explore lists them',
        (tester) async {
      setScreen(tester, inner);
      final modes = <int>[];
      final tabs = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(
          body: Row(children: [
            ExodusNavRail(
              selectedTab: 0,
              selectedMode: null,
              onSelectTab: tabs.add,
              onSelectMode: modes.add,
              onNewChat: () {},
            ),
          ]),
        ),
      ));
      for (final label in ['Counsel', 'Coaching', 'Devotional', 'Study',
          'Confess', 'Together']) {
        await tester.tap(find.bySemanticsLabel(label));
      }
      expect(modes, [0, 1, 2, 3, 4, 5]);
      for (final label in ['Home', 'Explore', 'Library', 'Profile']) {
        await tester.tap(find.bySemanticsLabel(label));
      }
      expect(tabs, [0, 1, 2, 3]);
      // Let the breathing New Chat glow stop cleanly.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('home', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: HomeScreen(
          onOpenConversation: (_) {},
          onNewConversation: () {},
          onSeeAll: () {},
        ),
      ));
      await tester.pump();
    }

    // The community strip is itself a horizontal list; count only the
    // vertical ones, which are the page's columns.
    Finder columns() => find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical);

    testWidgets('folded: one column', (tester) async {
      setScreen(tester, outer);
      await open(tester);
      expect(columns(), findsOneWidget);
    });

    testWidgets('unfolded upright, beside the rail: still one column',
        (tester) async {
      // 669pt less the 92pt rail. Two columns here would each be narrower
      // than the folded phone.
      setScreen(tester, const Size(669 - 92, 951));
      await open(tester);
      expect(columns(), findsOneWidget);
    });

    testWidgets('unfolded sideways: greeting and conversations side by side',
        (tester) async {
      setScreen(tester, const Size(951 - 92, 669));
      await open(tester);
      expect(columns(), findsNWidgets(2));
      final greeting = tester.getCenter(find.text('Peace be with you.'));
      final threads = tester.getCenter(find.text('Conversations'));
      expect(greeting.dx < threads.dx, isTrue,
          reason: 'conversations belong in the right-hand column');
    });
  });

  group('explore', () {
    testWidgets('unfolded grid still opens every mode in stack order',
        (tester) async {
      setScreen(tester, inner);
      final opened = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: ExploreScreen(onOpenMode: opened.add),
      ));
      await tester.pumpAndSettle();
      for (final name in ['Counsel', 'Coaching', 'Devotional', 'Bible Study',
          'Confessional', 'Together']) {
        await tester.ensureVisible(find.text(name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(opened, [0, 1, 2, 3, 4, 5]);
      // Two cards share a row.
      final counsel = tester.getCenter(find.text('Counsel'));
      final coaching = tester.getCenter(find.text('Coaching'));
      expect((counsel.dy - coaching.dy).abs() < 1, isTrue);
    });
  });

  group('book spread', () {
    Widget book({
      required int pages,
      required int spread,
      required ValueChanged<int> onChanged,
      ValueChanged<int>? onTapPage,
      bool reduceMotion = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: BookSpread(
            pageCount: pages,
            spread: spread,
            reduceMotion: reduceMotion,
            onSpreadChanged: onChanged,
            pageBuilder: (_, i) => GestureDetector(
              onTap: () => onTapPage?.call(i),
              child: ColoredBox(
                color: Colors.black,
                child: Center(child: Text('page $i')),
              ),
            ),
            blankBuilder: (_) => const Center(child: Text('end')),
          ),
        ),
      );
    }

    testWidgets('rests on two facing pages', (tester) async {
      setScreen(tester, inner);
      await tester.pumpWidget(book(pages: 5, spread: 0, onChanged: (_) {}));
      expect(find.text('page 0'), findsOneWidget);
      expect(find.text('page 1'), findsOneWidget);
      expect(find.text('page 2'), findsNothing);
      expect(tester.getCenter(find.text('page 0')).dx < inner.width / 2,
          isTrue);
    });

    testWidgets('a leftward swipe turns the leaf to the next spread',
        (tester) async {
      setScreen(tester, inner);
      var spread = 0;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => book(
          pages: 5,
          spread: spread,
          onChanged: (s) => setState(() => spread = s),
        ),
      ));
      await tester.fling(
          find.byType(BookSpread), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(spread, 1);
      expect(find.text('page 2'), findsOneWidget);
      expect(find.text('page 3'), findsOneWidget);
    });

    testWidgets('the last spread of an odd chapter closes on an end page',
        (tester) async {
      setScreen(tester, inner);
      await tester.pumpWidget(book(pages: 5, spread: 2, onChanged: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('page 4'), findsOneWidget);
      expect(find.text('end'), findsOneWidget);
    });

    testWidgets('cannot turn past the last page', (tester) async {
      setScreen(tester, inner);
      final changes = <int>[];
      await tester.pumpWidget(
          book(pages: 4, spread: 1, onChanged: changes.add));
      await tester.pumpAndSettle();
      await tester.fling(
          find.byType(BookSpread), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('taps reach the page at rest, so verses stay selectable',
        (tester) async {
      setScreen(tester, inner);
      final tapped = <int>[];
      await tester.pumpWidget(book(
          pages: 4, spread: 0, onChanged: (_) {}, onTapPage: tapped.add));
      await tester.tap(find.text('page 1'));
      expect(tapped, [1]);
    });

    testWidgets('with Reduce Motion a turn lands without animating',
        (tester) async {
      setScreen(tester, inner);
      var spread = 0;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => book(
          pages: 6,
          spread: spread,
          reduceMotion: true,
          onChanged: (s) => setState(() => spread = s),
        ),
      ));
      await tester.fling(
          find.byType(BookSpread), const Offset(-300, 0), 1200);
      await tester.pump();
      expect(spread, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('unfold reveal', () {
    // The veil's painter is the only CustomPaint the reveal adds; count
    // CustomPaints inside UnfoldReveal before and during.
    int paints(WidgetTester tester) => find
        .descendant(
            of: find.byType(UnfoldReveal), matching: find.byType(CustomPaint))
        .evaluate()
        .length;

    Widget app({bool reduce = false}) => MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: const UnfoldReveal(child: SizedBox.expand()),
            ),
          ),
        );

    testWidgets('opening the app unfolded does not play the unfold',
        (tester) async {
      setScreen(tester, inner);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 100));
      expect(paints(tester), 0);
    });

    testWidgets('unfolding plays once, then gets out of the way',
        (tester) async {
      setScreen(tester, outer);
      await tester.pumpWidget(app());
      final before = paints(tester);

      tester.view.physicalSize = inner * 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(paints(tester), greaterThan(before),
          reason: 'the veil should be over the new layout');

      await tester.pumpAndSettle();
      expect(paints(tester), before);
    });

    testWidgets('Reduce Motion skips it entirely', (tester) async {
      setScreen(tester, outer);
      await tester.pumpWidget(app(reduce: true));
      final before = paints(tester);
      tester.view.physicalSize = inner * 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(paints(tester), before);
    });
  });
}
