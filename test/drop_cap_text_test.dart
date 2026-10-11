import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/widgets/drop_cap_text.dart';

/// Flutter has no CSS float, so the illuminated initial is done by measuring:
/// lay the text out at the narrowed width, find where the second line ends,
/// and split. These pin the edges of that, because the failure mode is a
/// RangeError on a substring rather than something merely ugly.
void main() {
  const style = TextStyle(fontSize: 16, height: 1.6);
  const capStyle = TextStyle(fontSize: 48, height: 0.9);

  Future<void> render(WidgetTester tester, String text,
      {double width = 340}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: DropCapText(text: text, style: style, capStyle: capStyle),
        ),
      ),
    ));
  }

  testWidgets('the first letter is lifted out as its own run', (tester) async {
    await render(tester, 'Scripture speaks about marriage as covenant.');
    expect(find.text('S'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long paragraph keeps all of its text', (tester) async {
    const text =
        'Scripture speaks about marriage as covenant before it ever speaks '
        'of it as feeling. Start here, and read them aloud to each other '
        'rather than silently, because the words land differently when they '
        'are said in the room than when they are skimmed on a screen.';
    await render(tester, text);
    expect(tester.takeException(), isNull);

    // Every word survives the split across the two paragraphs.
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    for (final word in ['covenant', 'silently', 'skimmed', 'screen']) {
      expect(rendered, contains(word), reason: '"$word" was lost in the split');
    }
  });

  testWidgets('a one-word paragraph does not crash', (tester) async {
    await render(tester, 'Yes.');
    expect(find.text('Y'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single character does not crash', (tester) async {
    await render(tester, 'A');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty text renders nothing rather than throwing',
      (tester) async {
    await render(tester, '   ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a column too narrow for a drop cap falls back to plain text',
      (tester) async {
    // One character per line is worse than no ornament.
    await render(tester, 'Scripture speaks about marriage.', width: 70);
    expect(tester.takeException(), isNull);
    expect(find.text('Scripture speaks about marriage.'), findsOneWidget);
  });

  testWidgets('words are not cut in half across the split', (tester) async {
    const text =
        'Scripture speaks about marriage as covenant before it ever speaks of '
        'it as feeling and that distinction matters more than it first seems.';
    await render(tester, text);
    final runs = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((d) => d.length > 1)
        .toList();
    for (final run in runs) {
      expect(run.trim(), isNot(endsWith('-')));
      // A run should never begin mid-word with a stray fragment.
      expect(run, isNot(startsWith(' ')));
    }
  });

  testWidgets('the text beside the capital is never deeper than the capital',
      (tester) async {
    // On a phone the opening lines ran to three beside a two-line capital,
    // leaving one word stranded under the indent. The measurement ignored the
    // letter spacing the ambient text style adds when the text is drawn.
    const style = TextStyle(fontSize: 17, height: 1.6);
    for (final width in [300.0, 340.0, 372.0, 416.0, 520.0]) {
      for (final spacing in [0.0, 0.25, 0.5, 1.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DefaultTextStyle.merge(
                  style: TextStyle(letterSpacing: spacing),
                  child: const DropCapText(
                    text: 'Sorry to hear about the pain. That is a heavy weight '
                        'for both of you. Growing closer tonight, especially in '
                        'the middle of this, is a powerful thing to choose.',
                    style: style,
                    capStyle: TextStyle(fontSize: 48, height: 0.92),
                  ),
                ),
              ),
            ),
          ),
        ));
        final cap = tester.getSize(find.text('S'));
        final beside = tester.getSize(find.textContaining('orry to hear'));
        expect(beside.height, lessThanOrEqualTo(cap.height + 0.5),
            reason: 'width $width, letter spacing $spacing');
      }
    }
  });
}
