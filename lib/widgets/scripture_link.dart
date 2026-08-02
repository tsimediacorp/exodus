import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/bible_ref.dart';
import '../screens/bible_screen.dart';
import '../services/bible_service.dart';
import '../theme/exodus_theme.dart';

/// Opens the in-app Bible at [ref], with the passage highlighted.
///
/// The single entry point for scripture deep-linking, so every surface —
/// devotionals, journey days, Counsel replies — lands the couple in the same
/// place with the same behaviour.
Future<void> openScripture(BuildContext context, BibleRef ref,
    {String? note}) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BibleScreen(initialRef: ref, note: note)),
  );
}

/// Parse [reference] and open it. Does nothing if it isn't a real reference —
/// callers can use [BibleService.parse] first if they need to know.
Future<void> openScriptureRef(BuildContext context, String reference,
    {String? note}) async {
  final ref = BibleService.instance.parse(reference);
  if (ref == null) return;
  return openScripture(context, ref, note: note);
}

/// A tappable scripture reference, styled as a link.
class ScriptureLink extends StatelessWidget {
  final String reference;
  final TextStyle? style;

  const ScriptureLink({super.key, required this.reference, this.style});

  @override
  Widget build(BuildContext context) {
    final parsed = BibleService.instance.parse(reference);
    final base = style ??
        const TextStyle(
            color: ExodusTheme.brass,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700);
    // Unparseable references render as plain text rather than a link that
    // goes nowhere.
    if (parsed == null) return Text(reference, style: base);
    return Semantics(
      button: true,
      label: 'Open $reference in the Bible',
      child: InkWell(
        onTap: () => openScripture(context, parsed),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reference, style: base),
              const SizedBox(width: 5),
              Icon(Icons.menu_book_rounded,
                  size: (base.fontSize ?? 12) + 2, color: base.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders [text] with every scripture reference in it turned into a tappable
/// link — used for prose EXODUS wrote, where citations appear mid-sentence.
class ScriptureRichText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const ScriptureRichText({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final refs = BibleService.instance.findAll(text);
    if (refs.isEmpty) return Text(text, style: style);

    // Locate each reference's literal span so the surrounding prose is
    // preserved exactly as written.
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final ref in refs) {
      final label = BibleService.instance.label(ref);
      final at = _findLabel(text, label, cursor);
      if (at == null) continue;
      if (at.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, at.start)));
      }
      spans.add(TextSpan(
        text: text.substring(at.start, at.end),
        style: const TextStyle(
            color: ExodusTheme.brass, fontWeight: FontWeight.w600),
        recognizer: TapGestureRecognizer()
          ..onTap = () => openScripture(context, ref),
      ));
      cursor = at.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }

  /// Find where a reference appears in the prose. The canonical label won't
  /// always match the wording used ("Eph 5:25" vs "Ephesians 5:25"), so this
  /// falls back to matching the book's first word plus the chapter:verse.
  static _Span? _findLabel(String text, String label, int from) {
    final direct = text.indexOf(label, from);
    if (direct >= 0) return _Span(direct, direct + label.length);

    final numbers = RegExp(r'\d+(?::\d+(?:\s*[-–—]\s*\d+)?)?$')
        .firstMatch(label)
        ?.group(0);
    if (numbers == null) return null;
    final at = text.indexOf(numbers, from);
    if (at < 0) return null;
    // Walk back over the book name that precedes the numbers.
    var start = at;
    while (start > 0 && text[start - 1] == ' ') {
      start--;
    }
    while (start > 0 &&
        RegExp(r'[A-Za-z0-9. ]').hasMatch(text[start - 1]) &&
        at - start < 24) {
      start--;
    }
    while (start < at && !RegExp(r'[A-Za-z0-9]').hasMatch(text[start])) {
      start++;
    }
    return start < at ? _Span(start, at + numbers.length) : null;
  }
}

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}
