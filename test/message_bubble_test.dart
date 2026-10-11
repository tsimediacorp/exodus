import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:exodus/models/chat_message.dart';
import 'package:exodus/theme/exodus_theme.dart';
import 'package:exodus/widgets/drop_cap_text.dart';
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

  /// Tap the body of an EXODUS reply.
  ///
  /// A long reply opens with an illuminated initial, so its first paragraph
  /// is split across a capital and the run beside it; a short one goes
  /// straight to the markdown renderer. Either way find.text on the whole
  /// sentence matches nothing.
  Future<void> tapReply(WidgetTester tester) {
    final cap = find.byType(DropCapText);
    return tester
        .tap(cap.evaluate().isNotEmpty ? cap : find.byType(GptMarkdown).first);
  }

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

    testWidgets('a reply opens with an illuminated initial', (tester) async {
      await tester.pumpWidget(
          host(MessageBubble(
              message: exodus('Sit with that a while, and do not rush to fix '
                  'it tonight. Some things are meant to be carried together '
                  'before they are solved.'))));
      expect(find.byType(DropCapText), findsOneWidget);
      // The capital is its own text run, in brass.
      final cap = tester.widget<Text>(find.text('S'));
      expect(cap.style?.color, ExodusTheme.brass);
    });

    testWidgets('a reply opening with a heading gets no capital',
        (tester) async {
      // Dropping a capital onto "**Next Step:**" would read as a mistake.
      await tester.pumpWidget(host(MessageBubble(
          message: exodus('**Next Step for This Week:**\n\nSit down together.'))));
      expect(find.byType(DropCapText), findsNothing);
    });

    testWidgets('the question sits in a quiet bubble, not a saturated slab',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(message: user('We fought.'))));
      // The caps label went with the bubble: its shape says who is speaking.
      expect(find.text('YOU ASKED'), findsNothing);

      final bubble = tester
          .widgetList<Container>(find.ancestor(
              of: find.text('We fought.'), matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(bubble.color, isNotNull);
      expect(bubble.gradient, isNull, reason: 'a fill, never a gradient slab');
      // The tight corner points at the speaker.
      expect((bubble.borderRadius as BorderRadius).bottomRight,
          const Radius.circular(6));
    });

    testWidgets('a one-line reply gets no capital', (tester) async {
      // Two lines deep in front of four words is an ornament on nothing.
      await tester.pumpWidget(
          host(MessageBubble(message: exodus('Good. Start tonight.'))));
      expect(find.byType(DropCapText), findsNothing);
    });

    testWidgets('the couple\'s bubble sits against the right edge',
        (tester) async {
      // A phone. On anything wider the reading column is centred.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MessageBubble(message: user('We fought.'))));
      final bubble = tester.getRect(find
          .ancestor(of: find.text('We fought.'), matching: find.byType(Container))
          .first);
      expect(400 - bubble.right, lessThan(24));
      expect(bubble.left, greaterThan(100));
    });

    testWidgets('a reply that opens on a one-letter word gets no capital',
        (tester) async {
      // "I'm sorry" with its I dropped leaves "'m sorry" beside it.
      for (final opening in ["I'm sorry to hear that.", 'A week is not long.']) {
        await tester.pumpWidget(host(MessageBubble(message: exodus(opening))));
        expect(find.byType(DropCapText), findsNothing, reason: opening);
      }
    });

    testWidgets('only the newest reply keeps its actions in view',
        (tester) async {
      await tester.pumpWidget(host(MessageBubble(message: exodus('Answer.'))));
      expect(find.byTooltip('Read aloud'), findsNothing);

      await tester.pumpWidget(
          host(MessageBubble(message: exodus('Answer.'), latest: true)));
      expect(find.byTooltip('Copy'), findsOneWidget);
      expect(find.byTooltip('Read aloud'), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
      // Icons only. The labelled bar is still behind a tap.
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('a reply still being written offers nothing yet',
        (tester) async {
      final streaming = ChatMessage(
          content: 'Half a th', sender: Sender.exodus, isStreaming: true);
      await tester.pumpWidget(
          host(MessageBubble(message: streaming, latest: true)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byTooltip('Copy'), findsNothing);
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

      await tapReply(tester);
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

      await tapReply(tester);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tapReply(tester);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('a streaming reply offers no actions to tap', (tester) async {
      final streaming = ChatMessage(
          content: 'Half a th', sender: Sender.exodus, isStreaming: true);
      await tester.pumpWidget(host(MessageBubble(message: streaming)));
      await tapReply(tester);
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
