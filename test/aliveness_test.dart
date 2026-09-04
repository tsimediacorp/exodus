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
    testWidgets('it is stripped from the rendered reply', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: How do we start?]]'),
        onFollowUp: (_) {},
      )));
      // Not as a whole, and not as fragments either.
      expect(find.textContaining('[[NEXT'), findsNothing);
      expect(find.textContaining(']]'), findsNothing);
    });

    testWidgets('the questions become tappable chips', (tester) async {
      String? asked;
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: How do we start? | What if she refuses?]]'),
        onFollowUp: (q) => asked = q,
      )));
      expect(find.text('How do we start?'), findsOneWidget);
      expect(find.text('What if she refuses?'), findsOneWidget);

      await tester.tap(find.text('How do we start?'));
      expect(asked, 'How do we start?');
    });

    testWidgets('a half-written marker does not flash up mid-stream',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.\n\n[[NEXT: How do we', streaming: true),
      )));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('[[NEXT'), findsNothing);
    });

    testWidgets('no chips when the model offered none', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Sit with that.'),
        onFollowUp: (_) {},
      )));
      expect(find.byType(Wrap), findsNothing);
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
