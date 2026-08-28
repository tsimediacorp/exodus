import 'package:flutter/material.dart';

/// A paragraph opening with an illuminated initial, the way a printed devotional
/// sets one: the first letter dropped two lines deep in brass, with the opening
/// lines set beside it and the rest of the paragraph running full width beneath.
///
/// Flutter has no equivalent of CSS `float`, so text will not wrap around an
/// inline box on its own — a `WidgetSpan` reserves room on the first line only,
/// and every later line starts back at the margin. This measures instead: lay
/// the text out at the narrowed width, ask [TextPainter] where the [capLines]th
/// line ends, and split the string there. What sits beside the capital and what
/// runs beneath are two separate paragraphs.
///
/// Degrades rather than breaks: a paragraph too short to fill the indented
/// column simply has no run-on beneath it, and text that starts with something
/// other than a letter is rendered plainly by [MessageBubble] before it ever
/// reaches here.
class DropCapText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// Style for the initial. Its font size sets the drop depth.
  final TextStyle capStyle;

  /// How many lines deep the initial sits.
  final int capLines;

  /// Space between the initial and the text beside it.
  final double gap;

  const DropCapText({
    super.key,
    required this.text,
    required this.style,
    required this.capStyle,
    this.capLines = 2,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final initial = trimmed.substring(0, 1);
    final remainder = trimmed.substring(1);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Measure the capital, and the height of `capLines` normal lines. The
        // capital is boxed to the latter so the text beside it aligns to the
        // same block rather than to the glyph's own leading.
        final capPainter = TextPainter(
          text: TextSpan(text: initial, style: capStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final capWidth = capPainter.width;

        final linePainter = TextPainter(
          text: TextSpan(text: initial, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final blockHeight = linePainter.height * capLines;

        final besideWidth = maxWidth - capWidth - gap;
        // Nothing sensible to do with a column this narrow; fall back to a
        // plain paragraph rather than laying out one character per line.
        if (besideWidth < 60) {
          return Text(trimmed, style: style);
        }

        // Where does the text beside the capital run out of room?
        final flow = TextPainter(
          text: TextSpan(text: remainder, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: capLines,
        )..layout(maxWidth: besideWidth);

        final split = flow.getPositionForOffset(
          Offset(flow.width, flow.height - 1),
        ).offset;
        // Break on a space so a word is never cut in half across the two
        // paragraphs; if there is no space, take the whole measured run.
        var breakAt = remainder.lastIndexOf(' ', split.clamp(0, remainder.length));
        if (breakAt <= 0 || !flow.didExceedMaxLines) breakAt = remainder.length;

        final beside = remainder.substring(0, breakAt);
        final below = remainder.substring(breakAt).trimLeft();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: capWidth,
                  height: blockHeight,
                  child: Text(initial, style: capStyle),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: besideWidth,
                  child: Text(beside, style: style),
                ),
              ],
            ),
            if (below.isNotEmpty) Text(below, style: style),
          ],
        );
      },
    );
  }
}
