import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/chat_message.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/arrival.dart';
import 'package:exodus/widgets/message_bubble.dart';
import 'package:exodus/widgets/thinking_presence.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ChatMessage exodus(String text, {bool streaming = false}) => ChatMessage(
      content: text, sender: Sender.exodus, isStreaming: streaming);

  group('the follow-up marker never reaches the reader', () {
    // The model is no longer ASKED for follow-up questions — EXODUS raises
    // things itself, by notification, rather than offering a menu of buttons.
    // The stripping stays as a guard: a model that emits the old marker from
    // habit must never have it land in a reply.
    testWidgets('a stray marker is still stripped', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: How do we start?]]'),
      )));
      expect(find.textContaining('[[NEXT'), findsNothing);
      expect(find.textContaining(']]'), findsNothing);
    });

    testWidgets('no buttons are offered', (tester) async {
      // The whole point of the change: nothing here is user-initiated.
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: a | b]]'),
      )));
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsNothing);
    });

    testWidgets('a half-written marker does not flash up mid-stream',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: How do we', streaming: true),
      )));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('[[NEXT'), findsNothing);
    });
  });

  group('waiting', () {
    testWidgets('an empty reply shows the breathing presence', (tester) async {
      final waiting = ChatMessage(
          content: '', sender: Sender.exodus, isLoading: true);
      await tester.pumpWidget(host(MessageBubble(message: waiting)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ThinkingPresence), findsOneWidget);
    });
  });

  group('arrival', () {
    testWidgets('a settled reply is fully opaque immediately', (tester) async {
      // enabled:false must cost nothing — this is every message in a long
      // conversation, and animating them on scroll would be unbearable.
      await tester.pumpWidget(host(
        const Arrival(enabled: false, children: [Text('settled')]),
      ));
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.where((o) => o.opacity < 1), isEmpty);
      expect(find.text('settled'), findsOneWidget);
    });

    testWidgets('an arriving reply starts hidden and ends visible',
        (tester) async {
      await tester.pumpWidget(host(
        const Arrival(children: [Text('a'), Text('b')]),
      ));
      await tester.pump();
      final start = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(start.every((o) => o < 1), isTrue,
          reason: 'nothing should be fully visible on the first frame');

      await tester.pumpAndSettle();
      final end = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((o) => o.opacity)
          .toList();
      expect(end.every((o) => o == 1), isTrue,
          reason: 'everything must settle fully visible');
    });

    testWidgets('children are staggered, not simultaneous', (tester) async {
      await tester.pumpWidget(host(
        const Arrival(children: [Text('first'), Text('second')]),
      ));
      await tester.pump(const Duration(milliseconds: 90));
      final o = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((x) => x.opacity)
          .toList();
      expect(o.first, greaterThan(o.last),
          reason: 'the first child should be ahead of the second');
    });
  });
}
