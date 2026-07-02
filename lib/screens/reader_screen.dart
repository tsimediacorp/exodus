import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../theme/exodus_theme.dart';

/// A distraction-free, large-text reader for a single message — for reading
/// EXODUS's counsel or scripture together. Adjustable font size.
class ReaderScreen extends StatefulWidget {
  final String text;

  /// Render as markdown (EXODUS replies) vs. plain text (user messages).
  final bool markdown;

  const ReaderScreen({super.key, required this.text, this.markdown = true});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const double _min = 18;
  static const double _max = 48;
  double _size = 28;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: ExodusTheme.porcelain,
      fontSize: _size,
      height: 1.6,
      fontWeight: FontWeight.w400,
    );
    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      appBar: AppBar(
        title: const Text('Reader'),
        actions: [
          IconButton(
            tooltip: 'Smaller',
            icon: const Icon(Icons.text_decrease_rounded, color: ExodusTheme.ironMist),
            onPressed: _size <= _min
                ? null
                : () => setState(() => _size = (_size - 3).clamp(_min, _max)),
          ),
          IconButton(
            tooltip: 'Larger',
            icon: const Icon(Icons.text_increase_rounded, color: ExodusTheme.ironMist),
            onPressed: _size >= _max
                ? null
                : () => setState(() => _size = (_size + 3).clamp(_min, _max)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          child: widget.markdown
              ? GptMarkdown(widget.text, style: style)
              : SelectableText(widget.text, style: style),
        ),
      ),
    );
  }
}
