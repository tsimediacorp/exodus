import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/chat_message.dart';
import '../screens/reader_screen.dart';
import '../services/bible_service.dart';
import '../services/conversation_search.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';
import 'scripture_link.dart';

Uint8List? _decodeDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma == -1) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

String _formatElapsed(int ms) {
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000.0;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final mins = (seconds / 60).floor();
  final remSec = (seconds % 60).round();
  return '${mins}m ${remSec}s';
}

class MessageBubble extends StatefulWidget {
  final ChatMessage message;

  /// Called when the user taps "Regenerate" on an assistant message.
  final VoidCallback? onRegenerate;

  /// Called when the user taps "Edit" on their own message.
  final VoidCallback? onEdit;

  /// Called when the user taps "Delete" on any message.
  final VoidCallback? onDelete;

  /// The live in-conversation search term, or empty when not searching.
  /// Non-empty switches assistant replies from markdown to highlighted plain
  /// text — see [_content].
  final String searchQuery;

  /// Which occurrence *within this message* is the one currently selected in
  /// the search bar, or null if the selected match is in another message.
  final int? activeOccurrence;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRegenerate,
    this.onEdit,
    this.onDelete,
    this.searchQuery = '',
    this.activeOccurrence,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showActions = false;

  String get _ttsKey => widget.message.timestamp.toIso8601String();

  bool get _isUser => widget.message.sender == Sender.user;
  bool get _canShowActions =>
      !widget.message.isLoading && !widget.message.isStreaming;

  void _toggleActions() {
    if (!_canShowActions) return;
    setState(() => _showActions = !_showActions);
  }

  /// Tappable chips for every passage cited in this reply.
  Widget _scriptureChips() {
    final refs = BibleService.instance.findAll(widget.message.content);
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final ref in refs.take(6))
            Semantics(
              button: true,
              label: 'Open ${BibleService.instance.label(ref)} in the Bible',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => openScripture(context, ref),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: ExodusTheme.brass.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu_book_rounded,
                          size: 13, color: ExodusTheme.brass),
                      const SizedBox(width: 6),
                      Text(BibleService.instance.label(ref),
                          style: const TextStyle(
                              color: ExodusTheme.brass,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied'),
      duration: Duration(seconds: 1),
    ));
  }

  /// Base style for reply prose. Assistant text is lighter than the user's so
  /// the two turns read differently even without a box around each.
  static const TextStyle _exodusText = TextStyle(
    color: ExodusTheme.porcelain,
    fontSize: 15,
    height: 1.62,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _userText = TextStyle(
    color: ExodusTheme.porcelain,
    fontSize: 15,
    height: 1.55,
    fontWeight: FontWeight.w500,
  );

  /// Split [text] into spans, tinting every occurrence of the search term.
  /// The active occurrence gets a solid fill rather than a wash, so "match 3
  /// of 12" is something you can actually see rather than infer.
  List<TextSpan> _highlighted(String text, TextStyle base) {
    final needle = widget.searchQuery.trim();
    final hits = ConversationSearch.occurrences(text, needle);
    if (hits.isEmpty) return [TextSpan(text: text, style: base)];

    final spans = <TextSpan>[];
    var start = 0;
    for (var occurrence = 0; occurrence < hits.length; occurrence++) {
      final at = hits[occurrence];
      if (at > start) {
        spans.add(TextSpan(text: text.substring(start, at), style: base));
      }
      final isActive = occurrence == widget.activeOccurrence;
      spans.add(TextSpan(
        text: text.substring(at, at + needle.length),
        style: base.copyWith(
          color: isActive ? Colors.white : base.color,
          backgroundColor: isActive
              ? ExodusTheme.covenantBlue
              : ExodusTheme.brass.withValues(alpha: 0.24),
          fontWeight: isActive ? FontWeight.w600 : base.fontWeight,
        ),
      ));
      start = at + needle.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    return spans;
  }

  /// The message body.
  ///
  /// While a search is running this renders the raw text with highlights
  /// instead of markdown: a markdown renderer owns its own spans, so there is
  /// nowhere to hang a highlight without rewriting its output. Leaving search
  /// restores the formatted reply.
  Widget _content(TextStyle style) {
    final message = widget.message;
    if (widget.searchQuery.isNotEmpty) {
      return SelectableText.rich(
        TextSpan(children: _highlighted(message.content, style)),
      );
    }
    if (_isUser) return SelectableText(message.content, style: style);
    return GptMarkdown(message.content, style: style);
  }

  @override
  Widget build(BuildContext context) {
    // 30pt between turns, which is where the breathing room comes from now
    // that neither speaker is padded inside a box.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      child: _isUser ? _userTurn(context) : _exodusTurn(context),
    );
  }

  /// The user still gets a bubble — it is the shorter turn, and the fill is
  /// what tells you at a glance who is speaking.
  Widget _userTurn(BuildContext context) {
    final message = widget.message;
    final hasText = message.content.trim().isNotEmpty;
    // Capped so a reply never spans the full width; a full-width blue slab is
    // most of what made the old thread read as a stack of containers.
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            button: true,
            label: 'Your message. Tap for options.',
            child: GestureDetector(
              onTap: _toggleActions,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [ExodusTheme.covenantBlue, Color(0xFF2D5BC8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    // The one clipped corner points at the sender.
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.images.isNotEmpty)
                      _AttachedImages(
                          images: message.images, hasText: hasText),
                    if (hasText) _content(_userText),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showActions && _canShowActions) _actionBar(),
      ],
    );
  }

  /// EXODUS speaks on the page rather than inside a box. The label below is
  /// what separates the turn — a border around 300 words of counsel reads as
  /// a form field, not as someone talking.
  Widget _exodusTurn(BuildContext context) {
    final message = widget.message;
    final hasText = message.content.trim().isNotEmpty;
    final waiting = !hasText && (message.isLoading || message.isStreaming);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            ExodusShield(size: 17, glow: false),
            SizedBox(width: 8),
            Text('EXODUS',
                style: TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                )),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: 'EXODUS reply. Tap for options.',
          child: GestureDetector(
            onTap: _toggleActions,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waiting)
                  _TypingIndicator(startTime: message.timestamp)
                else ...[
                  if (message.images.isNotEmpty)
                    _AttachedImages(
                        images: message.images, hasText: hasText),
                  if (hasText) _content(_exodusText),
                ],
                if (message.isStreaming && hasText)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: _StreamingCursor(),
                  ),
              ],
            ),
          ),
        ),
        // Scripture EXODUS cited, as chips that open the in-app Bible at the
        // passage. Chips rather than inline links because the reply is
        // rendered as markdown, and rewriting its spans would fight the
        // renderer.
        if (!message.isStreaming) _scriptureChips(),
        if (_showActions && _canShowActions) _actionBar(),
        if (!message.isStreaming && message.responseTimeMs != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _formatElapsed(message.responseTimeMs!),
              style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _ActionBar(
        isAssistant: !_isUser,
        ttsKey: _ttsKey,
        onCopy: _copy,
        onPlay: () =>
            TtsService.instance.toggle(_ttsKey, widget.message.content),
        onRegenerate: widget.onRegenerate,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onReader: widget.message.content.trim().isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(
                      text: widget.message.content,
                      markdown: !_isUser,
                    ),
                  ),
                ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool isAssistant;
  final String ttsKey;
  final VoidCallback onCopy;
  final VoidCallback onPlay;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReader;

  const _ActionBar({
    required this.isAssistant,
    required this.ttsKey,
    required this.onCopy,
    required this.onPlay,
    required this.onRegenerate,
    required this.onEdit,
    required this.onDelete,
    required this.onReader,
  });

  @override
  Widget build(BuildContext context) {
    // A raised, bordered row rather than bare icons on the background. With
    // the reply itself no longer boxed, the actions need their own surface to
    // read as a control strip instead of as more of the message.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: ExodusTheme.slate,
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(icon: Icons.copy_rounded, label: 'Copy', onTap: onCopy),
        if (!isAssistant && onEdit != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.edit_rounded, label: 'Edit', onTap: onEdit!),
        ],
        if (isAssistant) ...[
          const SizedBox(width: 4),
          ValueListenableBuilder<String?>(
            valueListenable: TtsService.instance.speakingKey,
            builder: (_, speakingKey, __) {
              final isSpeaking = speakingKey == ttsKey;
              return _ActionButton(
                icon: isSpeaking
                    ? Icons.stop_rounded
                    : Icons.volume_up_rounded,
                label: isSpeaking ? 'Stop' : 'Play',
                onTap: onPlay,
                highlight: isSpeaking,
              );
            },
          ),
          if (onRegenerate != null) ...[
            const SizedBox(width: 4),
            _ActionButton(
              icon: Icons.refresh_rounded,
              label: 'Regenerate',
              onTap: onRegenerate!,
            ),
          ],
        ],
        if (onReader != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
              icon: Icons.menu_book_rounded, label: 'Reader', onTap: onReader!),
        ],
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: onDelete!),
        ],
      ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? ExodusTheme.brass : ExodusTheme.ironMist;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        // 44pt minimum. These were ~27pt tall and sat 4pt apart, so Delete
        // was one mis-tap away from Copy.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pulsing block shown at the end of an assistant bubble while it's
/// still streaming. Differs from _TypingIndicator (three dots) which only
/// shows BEFORE any content arrives.
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();
  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 14,
        decoration: BoxDecoration(
          color: ExodusTheme.brass.withValues(alpha: 0.3 + _ctrl.value * 0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final DateTime startTime;
  const _TypingIndicator({required this.startTime});
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final elapsedMs =
            DateTime.now().difference(widget.startTime).inMilliseconds;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(3, (i) {
              final phase = (_ctrl.value + i * 0.2) % 1.0;
              final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2)
                  .clamp(0.3, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: ExodusTheme.brass.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
            const SizedBox(width: 10),
            Text(
              _formatElapsed(elapsedMs),
              style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Thumbnails for images attached to a message. Tapping one opens a
/// full-screen, pinch-to-zoom viewer.
class _AttachedImages extends StatelessWidget {
  final List<String> images;
  final bool hasText;

  const _AttachedImages({required this.images, required this.hasText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: hasText ? 10 : 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final url in images) _thumb(context, url),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, String url) {
    final bytes = _decodeDataUrl(url);
    if (bytes == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _openViewer(context, bytes),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          bytes,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _ImageViewer(bytes: bytes),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final Uint8List bytes;
  const _ImageViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.memory(bytes),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
