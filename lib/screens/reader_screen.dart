import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../services/storage_service.dart';
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
  static const double _default = 28;

  /// Restored from prefs — the size used to reset on every open, so reading
  /// together meant re-adjusting it every single time.
  late double _size =
      (StorageService.instance.loadReaderFontSize() ?? _default)
          .clamp(_min, _max);

  void _setSize(double next) {
    setState(() => _size = next.clamp(_min, _max));
    StorageService.instance.saveReaderFontSize(_size);
  }

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
            onPressed: _size <= _min ? null : () => _setSize(_size - 3),
          ),
          IconButton(
            tooltip: 'Larger',
            icon: const Icon(Icons.text_increase_rounded, color: ExodusTheme.ironMist),
            onPressed: _size >= _max ? null : () => _setSize(_size + 3),
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
