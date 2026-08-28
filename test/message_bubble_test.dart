import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/chat_message.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/message_bubble.dart';

/// The chat redesign and in-conversation search both live here.
///
/// The redesign's one structural move is that EXODUS replies lost their
/// bubble: only the user still gets a filled container, and the speaker is
/// carried by a brass EXODUS label instead of a border. Search then layers on
/// top — while a query is live, replies render as highlighted plain text
/// rather than markdown, because a markdown renderer owns its own spans and
/// leaves nowhere to hang a highlight.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ExodusTheme.build(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  ChatMessage exodus(String text) =>
      ChatMessage(content: text, sender: Sender.exodus, responseTimeMs: 4200);
  ChatMessage user(String text) =>
      ChatMessage(content: text, sender: Sender.user);

  /// Every span the bubble builds, flattened.
  ///
  /// Read off the widgets rather than the render tree: highlighted text goes
  /// through SelectableText.rich, which renders via EditableText and so never
  /// appears as a RichText to look inside.
  List<TextSpan> spansIn(WidgetTester tester) {
    final spans = <TextSpan>[];
    void walk(InlineSpan? span) {
      if (span is! TextSpan) return;
      spans.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }

    for (final selectable
        in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
      walk(selectable.textSpan);
    }
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(rich.text);
    }
    return spans;
  }

  group('speaker treatment', () {
    testWidgets('an EXODUS reply is labelled rather than boxed',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(message: exodus('Sit with that.'))));
      expect(find.text('EXODUS'), findsOneWidget);
    });

    testWidgets('a user message carries no speaker label', (tester) async {
      await tester.pumpWidget(host(MessageBubble(message: user('We fought.'))));
      expect(find.text('EXODUS'), findsNothing);
    });

    testWidgets('how long it took is in the actions, not the thread',
        (tester) async {
      // It used to sit under every reply, which read as debug output left
      // switched on. It is still available, just not shouted.
      await tester.pumpWidget(host(MessageBubble(message: exodus('Answer.'))));
      expect(find.text('4.2s'), findsNothing);

      await tester.tap(find.text('Answer.'));
      await tester.pumpAndSettle();
      expect(find.text('4.2s'), findsOneWidget);
    });

    testWidgets('a user message shows no elapsed time at all', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: user('We fought.'),
        onDelete: () {},
      )));
      await tester.tap(find.text('We fought.'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget); // the row did open
      expect(find.text('4.2s'), findsNothing);
    });

    testWidgets('actions stay hidden until the message is tapped',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('Answer.'),
        onDelete: () {},
      )));
      expect(find.text('Copy'), findsNothing);

      await tester.tap(find.text('Answer.'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Answer.'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('a streaming reply offers no actions to tap', (tester) async {
      final streaming = ChatMessage(
          content: 'Half a th', sender: Sender.exodus, isStreaming: true);
      await tester.pumpWidget(host(MessageBubble(message: streaming)));
      await tester.tap(find.text('Half a th'));
      // pump, not pumpAndSettle: the streaming cursor pulses forever, so
      // settling never completes.
      await tester.pump(const Duration(milliseconds: 50));
      // Copying or regenerating something still being written is meaningless.
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('search highlighting', () {
    const reply = 'Anger is not the sin. Anger nursed is the sin.';

    testWidgets('with no query, nothing is highlighted', (tester) async {
      await tester.pumpWidget(host(MessageBubble(message: exodus(reply))));
      final highlighted =
          spansIn(tester).where((s) => s.style?.backgroundColor != null);
      expect(highlighted, isEmpty);
    });

    testWidgets('every occurrence is tinted', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus(reply),
        searchQuery: 'anger',
      )));
      final highlighted = spansIn(tester)
          .where((s) => s.style?.backgroundColor != null)
          .toList();
      expect(highlighted, hasLength(2));
      expect(highlighted.every((s) => s.text!.toLowerCase() == 'anger'), isTrue);
    });

    testWidgets('matching is case-insensitive but preserves the text',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus('ANGER and anger'),
        searchQuery: 'anger',
      )));
      final texts = spansIn(tester)
          .where((s) => s.style?.backgroundColor != null)
          .map((s) => s.text)
          .toList();
      // The highlight must not rewrite the reply to the query's casing.
      expect(texts, ['ANGER', 'anger']);
    });

    testWidgets('the active occurrence is distinct from the others',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus(reply),
        searchQuery: 'anger',
        activeOccurrence: 1,
      )));
      final highlighted = spansIn(tester)
          .where((s) => s.style?.backgroundColor != null)
          .toList();
      expect(highlighted, hasLength(2));
      // "3 of 12" is only useful if you can see which one you landed on.
      expect(highlighted[0].style!.backgroundColor,
          isNot(highlighted[1].style!.backgroundColor));
      expect(highlighted[1].style!.backgroundColor, ExodusTheme.covenantBlue);
    });

    testWidgets('an active occurrence in another message tints nothing solid',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus(reply),
        searchQuery: 'anger',
        activeOccurrence: null,
      )));
      final solid = spansIn(tester)
          .where((s) => s.style?.backgroundColor == ExodusTheme.covenantBlue);
      expect(solid, isEmpty);
    });

    testWidgets('a query that matches nothing leaves the text alone',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: exodus(reply),
        searchQuery: 'chariot',
      )));
      expect(spansIn(tester).where((s) => s.style?.backgroundColor != null),
          isEmpty);
      expect(find.textContaining('Anger is not the sin'), findsOneWidget);
    });

    testWidgets('user messages highlight too', (tester) async {
      await tester.pumpWidget(host(MessageBubble(
        message: user('So the anger itself is not sin?'),
        searchQuery: 'anger',
        activeOccurrence: 0,
      )));
      final highlighted =
          spansIn(tester).where((s) => s.style?.backgroundColor != null);
      expect(highlighted, hasLength(1));
    });

    testWidgets('markdown is bypassed while searching', (tester) async {
      // A reply full of markdown renders as raw text during a search, so the
      // highlight has somewhere to live. Leaving search restores formatting.
      const md = '**Bold** anger and _more_ anger';
      await tester.pumpWidget(host(MessageBubble(
        message: exodus(md),
        searchQuery: 'anger',
      )));
      // The literal asterisks are on screen, which is what "raw text" means.
      expect(find.textContaining('**Bold**'), findsOneWidget);
    });
  });
}
