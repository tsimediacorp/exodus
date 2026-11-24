import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:exodus/config/action_plan_prompt.dart';
import 'package:exodus/layout/exodus_layout.dart';
import 'package:exodus/models/action_plan.dart';
import 'package:exodus/models/chat_message.dart';
import 'package:exodus/models/check_in.dart';
import 'package:exodus/models/conversation.dart';
import 'package:exodus/screens/conversations_screen.dart';
import 'package:exodus/services/action_plan_service.dart';
import 'package:exodus/services/check_in_service.dart';
import 'package:exodus/services/storage_service.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/conversation_tile.dart';
import 'package:exodus/widgets/exodus_nav_rail.dart';

import 'support/real_fonts.dart';

void main() {
  setUpAll(loadRealFonts);

  group('folded Duo status column', () {
    Future<double> widthFor(WidgetTester tester,
        {required Size size, required EdgeInsets pad}) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      tester.view.padding = FakeViewPadding(
          left: pad.left * 3,
          top: pad.top * 3,
          right: pad.right * 3,
          bottom: pad.bottom * 3);
      tester.view.viewPadding = tester.view.padding;
      addTearDown(tester.view.reset);
      late double width;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        width = ExodusLayout.sideColumnWidth(context);
        return const SizedBox();
      })));
      return width;
    }

    testWidgets('the outer screen hands its right column to navigation',
        (tester) async {
      expect(
          await widthFor(tester,
              size: const Size(466, 678),
              pad: const EdgeInsets.only(right: 84, bottom: 20)),
          84);
    });

    testWidgets('an ordinary iPhone keeps its bottom bar', (tester) async {
      expect(
          await widthFor(tester,
              size: const Size(440, 956),
              pad: const EdgeInsets.only(top: 62, bottom: 34)),
          0);
    });

    testWidgets('a notched phone sideways is not mistaken for it',
        (tester) async {
      expect(
          await widthFor(tester,
              size: const Size(956, 440),
              pad: const EdgeInsets.only(left: 62, right: 62, bottom: 21)),
          0);
    });

    testWidgets('the side rail opens every tab and starts a chat',
        (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(466, 678) * 3;
      addTearDown(tester.view.reset);
      final tabs = <int>[];
      var newChats = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: ExodusSideRail(
              width: 84,
              selected: 0,
              onSelect: tabs.add,
              onNewChat: () => newChats++,
            ),
          ),
        ),
      ));
      for (final label in ['Home', 'Explore', 'Library', 'Profile']) {
        await tester.tap(find.bySemanticsLabel(label));
      }
      await tester.tap(find.bySemanticsLabel('New conversation'));
      expect(tabs, [0, 1, 2, 3]);
      expect(newChats, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the keyboard squeezes a screen beside the rail only once',
        (tester) async {
      // Folded Duo: status column on the right, keyboard up.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(466, 678) * 3;
      tester.view.padding = const FakeViewPadding(right: 84 * 3);
      tester.view.viewPadding = tester.view.padding;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.reset);
      final body = GlobalKey();
      // The shell's Scaffold around a screen with its own, as Counsel has.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BesideSideRail(
            columnWidth: 84,
            child: Scaffold(body: SizedBox.expand(key: body)),
          ),
        ),
      ));
      // Room above the keyboard, not the keyboard's height taken twice.
      expect(tester.getSize(find.byKey(body)).height, 678 - 300);
      expect(MediaQuery.paddingOf(body.currentContext!).right,
          84 - BesideSideRail.railOverlap);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('swipe to delete', () {
    Conversation conv(String id, String title) => Conversation(
          id: id,
          title: title,
          messages: [ChatMessage(content: 'hello', sender: Sender.user)],
        );

    testWidgets('a full swipe deletes at once, with no dialog',
        (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListView(children: [
              for (final c in [conv('a', 'First'), conv('b', 'Second')])
                if (!deleted.contains(c.id))
                  ConversationTile(
                    key: ValueKey(c.id),
                    conversation: c,
                    onOpen: () {},
                    onDelete: () => setState(() => deleted.add(c.id)),
                  ),
            ]),
          ),
        ),
      ));
      await tester.fling(find.text('First'), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();
      expect(deleted, ['a']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('a short drag springs back and deletes nothing',
        (tester) async {
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            ConversationTile(
              conversation: conv('a', 'First'),
              onOpen: () {},
              onDelete: () => deleted.add('a'),
            ),
          ]),
        ),
      ));
      await tester.drag(find.text('First'), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('the full list deletes through its callback', (tester) async {
      SharedPreferences.setMockInitialValues({
        'exodus.conversations': jsonEncode([
          conv('a', 'First').toJson(),
          conv('b', 'Second').toJson(),
        ]),
      });
      await tester.runAsync(() => StorageService.instance.init());
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: ExodusTheme.build(),
        home: ConversationsScreen(
          onOpen: (_) {},
          onNew: () {},
          onDelete: (id) {
            deleted.add(id);
            final left = StorageService.instance
                .loadConversations()
                .where((c) => c.id != id)
                .toList();
            StorageService.instance.saveConversations(left);
          },
        ),
      ));
      await tester.fling(find.text('Second'), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();
      expect(deleted, ['b']);
      expect(find.text('Second'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('follow-ups stay on topic', () {
    final checkIn = CheckIn(
      id: 'k1',
      question: 'How did the budget conversation go on Sunday?',
      because: 'They planned to sit down and go through the budget together.',
      topic: 'money',
      dueAt: DateTime(2026),
    );

    test('the context outlives the opening line', () {
      final c = Conversation.empty()
        ..followUp = CheckInService.instance.threadContext(checkIn);
      final back = Conversation.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.followUp, contains(checkIn.question));
      expect(back.followUp, contains(checkIn.because));
      expect(back.followUp, contains('FOLLOW-UP'));
    });

    test('the thread is named for what was asked', () {
      expect(CheckInService.titleFor(checkIn), startsWith('How did the budget'));
      expect(CheckInService.titleFor(checkIn).length, lessThanOrEqualTo(48));
    });

    test('an ordinary conversation carries no follow-up', () {
      final back = Conversation.fromJson(
          jsonDecode(jsonEncode(Conversation.empty().toJson()))
              as Map<String, dynamic>);
      expect(back.followUp, isNull);
    });
  });

  group('active steps', () {
    String planJson(int n) => jsonEncode({
          'title': 'Stop the money argument',
          'goal': 'Have one calm budget conversation start to finish.',
          'steps': [
            for (var i = 1; i <= n; i++)
              {
                'title': 'Step $i',
                'action': 'Do thing $i.',
                'scripture': i == 1 ? 'Ephesians 4:26' : '',
              }
          ],
        });

    test('the offer marker is found and never shown', () {
      const reply = 'Would a plan help you two work on this?\n\n[[PLAN]]';
      expect(ActionPlanService.offers(reply), isTrue);
      expect(ActionPlanService.strip(reply),
          'Would a plan help you two work on this?');
      expect(ActionPlanService.strip('Cut off mid-marker [[PL'),
          'Cut off mid-marker');
    });

    test('a plan parses from fenced JSON, one step per day', () {
      final plan = ActionPlanService.parse('```json\n${planJson(5)}\n```',
          length: PlanLength.fiveDays, conversationId: 'c1');
      expect(plan, isNotNull);
      expect(plan!.steps.map((s) => s.day), [1, 2, 3, 4, 5]);
      expect(plan.steps.first.scripture, 'Ephesians 4:26');
      expect(plan.conversationId, 'c1');
    });

    test('a week that comes back four days long is rejected', () {
      expect(
          ActionPlanService.parse(planJson(4), length: PlanLength.week), isNull);
    });

    test('extra steps are trimmed to the length asked for', () {
      final plan =
          ActionPlanService.parse(planJson(9), length: PlanLength.week);
      expect(plan!.length, 7);
    });

    test('the next step waits for you rather than skipping ahead', () {
      final plan =
          ActionPlanService.parse(planJson(3), length: PlanLength.threeDays)!;
      plan.steps[0].doneAt = DateTime.now();
      expect(plan.currentStep(DateTime.now().add(const Duration(days: 2)))!.day,
          2);
      expect(plan.isActive, isTrue);
      for (final s in plan.steps) {
        s.doneAt = DateTime.now();
      }
      expect(plan.isComplete, isTrue);
      expect(plan.isActive, isFalse);
    });

    test('plans survive a round trip through storage', () {
      final plan =
          ActionPlanService.parse(planJson(3), length: PlanLength.threeDays)!;
      plan.steps[1].doneAt = DateTime(2026, 11, 20);
      final back = ActionPlan.fromJson(
          jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>);
      expect(back.title, plan.title);
      expect(back.steps[1].done, isTrue);
      expect(back.steps[0].done, isFalse);
    });

    test('Counsel is told about the running plan', () {
      final plan =
          ActionPlanService.parse(planJson(5), length: PlanLength.fiveDays)!;
      final layer = ActionPlanPrompt.activeLayer(plan, DateTime.now());
      expect(layer, contains(plan.goal));
      expect(layer, contains('Step 1'));
    });

    test('the offer is made once per conversation', () {
      expect(ActionPlanPrompt.offerLayer(alreadyOffered: false),
          contains('[[PLAN]]'));
      expect(ActionPlanPrompt.offerLayer(alreadyOffered: true), isEmpty);
    });

    test('creating a plan saves it against its conversation', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
      final service = ActionPlanService.instance..reset();
      service.askOverride = (_, __) async => planJson(3);
      final conv = Conversation.empty()
        ..messages.add(
            ChatMessage(content: 'We keep fighting about money', sender: Sender.user));
      final plan = await service.create(
          conversation: conv, length: PlanLength.threeDays);
      expect(plan, isNotNull);
      expect(service.forConversation(conv.id)?.id, plan!.id);
      expect(service.active.single.id, plan.id);

      // Reloaded from storage, not just held in memory.
      service.reset();
      expect(service.byId(plan.id)?.length, 3);
      service.reset();
    });
  });
}
