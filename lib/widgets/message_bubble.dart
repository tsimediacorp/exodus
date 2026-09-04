import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/chat_message.dart';
import '../screens/reader_screen.dart';
import '../services/bible_service.dart';
import '../services/conversation_search.dart';
import '../services/progress.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../services/follow_ups.dart';
import 'arrival.dart';
import 'drop_cap_text.dart';
import 'exodus_shield.dart';
import 'thinking_presence.dart';
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

  /// True only for a reply that has just landed, so it settles onto the page
  /// once. Scrolling back through a conversation must never replay it.
  final bool arriving;

  /// Narration for the waiting state, while EXODUS is still composing.
  final ProgressController? progress;

  /// Tapping one of EXODUS's suggested next questions.
  final ValueChanged<String>? onFollowUp;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRegenerate,
    this.onEdit,
    this.onDelete,
    this.searchQuery = '',
    this.activeOccurrence,
    this.arriving = false,
    this.progress,
    this.onFollowUp,
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

  /// Scripture EXODUS cited, set as illuminated blocks rather than chips.
  ///
  /// A chip is a filter control; these are passages. Quoting the verse under a
  /// brass rule makes the citation readable where it stands, instead of asking
  /// the couple to tap away to find out what it says. Still tappable, and still
  /// opens the in-app Bible at the passage.
  Widget _scriptureBlocks() {
    final refs = BibleService.instance.findAll(widget.message.content);
    if (refs.isEmpty) return const SizedBox.shrink();
    final bible = BibleService.instance;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: ExodusTheme.brass.withValues(alpha: 0.55), width: 2),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ref in refs.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Semantics(
                  button: true,
                  label: 'Open ${bible.label(ref)} in the Bible',
                  child: InkWell(
                    onTap: () => openScripture(context, ref),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The verse itself, when the translation is loaded.
                        // Without it this degrades to just the reference,
                        // which is what the chips always were.
                        if (bible.textFor(ref).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Text(
                              '\u201C${bible.textFor(ref)}\u201D',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: ExodusTheme.serif,
                                color: ExodusTheme.parchment,
                                fontSize: 16,
                                height: 1.68,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        Text(
                          bible.label(ref).toUpperCase(),
                          style: const TextStyle(
                            color: ExodusTheme.brass,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
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

  /// EXODUS speaks in the reading face. The replies are long-form devotional
  /// prose, and a serif at this measure is what makes them read as something
  /// to sit with rather than a chat message to skim.
  static const TextStyle _exodusText = TextStyle(
    fontFamily: ExodusTheme.serif,
    color: ExodusTheme.parchment,
    fontSize: 17,
    height: 1.78,
    fontWeight: FontWeight.w300,
  );

  /// The illuminated initial. Sized to drop two lines.
  static const TextStyle _capText = TextStyle(
    fontFamily: ExodusTheme.serif,
    color: ExodusTheme.brass,
    fontSize: 50,
    height: 0.92,
    fontWeight: FontWeight.w600,
  );

  /// The question is the prompt, not the point: smaller, quieter, italic, and
  /// set flush right without a bubble.
  static const TextStyle _userText = TextStyle(
    fontFamily: ExodusTheme.serif,
    color: ExodusTheme.ironMist,
    fontSize: 15,
    height: 1.5,
    fontStyle: FontStyle.italic,
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
  /// The reply text as the couple should read it — never the raw content,
  /// which may still carry the follow-up marker.
  String get _visibleText => _isUser
      ? widget.message.content
      : FollowUps.strip(widget.message.content);

  Widget _content(TextStyle style) {
    final message = widget.message;
    // SelectableText handles its own taps for text selection, so a tap landing
    // on the words never reached the GestureDetector wrapping it — the action
    // row only opened if you happened to hit the padding around the text.
    // Routing through its own onTap makes the whole message tappable.
    if (widget.searchQuery.isNotEmpty) {
      return SelectableText.rich(
        TextSpan(children: _highlighted(_visibleText, style)),
        onTap: _toggleActions,
      );
    }
    if (_isUser) {
      return SelectableText(message.content,
          style: style, textAlign: TextAlign.right, onTap: _toggleActions);
    }
    return _illuminated(_visibleText, style);
  }

  /// A reply, opened with an illuminated initial.
  ///
  /// Only the FIRST paragraph gets the treatment, and only when it is plain
  /// prose. Everything after it goes through the markdown renderer as before,
  /// because replies routinely carry bold headings and lists that a drop cap
  /// would fight. A reply that opens with a heading or a list gets no capital
  /// at all — dropping a capital onto "**Next Step:**" would look like a
  /// mistake rather than a flourish.
  Widget _illuminated(String content, TextStyle style) {
    final text = content.trimLeft();
    final split = text.indexOf('\n\n');
    final first = (split == -1 ? text : text.substring(0, split)).trim();
    final rest = split == -1 ? '' : text.substring(split).trim();

    final plainOpening = first.isNotEmpty &&
        RegExp(r'^[A-Za-z]').hasMatch(first) &&
        !RegExp(r'[*_`#\[\]|]').hasMatch(first);

    if (!plainOpening) {
      return GptMarkdown(content, style: style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropCapText(text: first, style: style, capStyle: _capText),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 16),
          GptMarkdown(rest, style: style),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 30pt between turns, which is where the breathing room comes from now
    // that neither speaker is padded inside a box.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
      child: _isUser ? _userTurn(context) : _exodusTurn(context),
    );
  }

  /// The question, set as a standfirst rather than a bubble.
  ///
  /// It loses its filled pill entirely: in a thread where the answer is the
  /// substance, a saturated blue slab for "can you give us some verses" pulls
  /// more weight than the question deserves. A caps label and italic serif
  /// flush right say who is speaking without competing.
  Widget _userTurn(BuildContext context) {
    final message = widget.message;
    final hasText = message.content.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('YOU ASKED',
            style: TextStyle(
              color: ExodusTheme.ironMist,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
            )),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          child: Semantics(
            button: true,
            label: 'Your message. Tap for options.',
            child: GestureDetector(
              onTap: _toggleActions,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.images.isNotEmpty)
                    _AttachedImages(images: message.images, hasText: hasText),
                  if (hasText) _content(_userText),
                ],
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

    return Arrival(
      // Only a reply that has just landed settles in. Replaying this while
      // scrolling back through a long conversation would be unbearable.
      enabled: widget.arriving,
      children: [
        // A rule, not just a label. In a reply this long the label alone
        // scrolls away and the turn loses its start; a hairline running to the
        // edge marks it unmistakably and gives the wall of prose a lid.
        Row(
          children: [
            const ExodusShield(size: 17, glow: false),
            const SizedBox(width: 8),
            const Text('EXODUS',
                style: TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                )),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    ExodusTheme.brass.withValues(alpha: 0.45),
                    ExodusTheme.brass.withValues(alpha: 0.05),
                  ]),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          button: true,
          label: 'EXODUS reply. Tap for options.',
          child: GestureDetector(
            onTap: _toggleActions,
            // Opaque, so the whitespace beside a short line responds too.
            // With deferToChild only the painted glyphs were tappable, which
            // makes "tap for options" a hunt on a one-line reply.
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waiting)
                  ThinkingPresence(
                      startTime: message.timestamp, progress: widget.progress)
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
        // Scripture EXODUS cited, quoted where it stands.
        if (!message.isStreaming) _scriptureBlocks(),
        if (!message.isStreaming) _followUps(),
        if (_showActions && _canShowActions) _actionBar(),
      ],
    );
  }

  /// The questions EXODUS offers next.
  ///
  /// This is the piece that makes it feel like EXODUS is leading rather than
  /// waiting: instead of a blank composer after a heavy answer, there are two
  /// or three things the couple might actually want to ask, in their own
  /// words. Hidden while streaming — half a suggested question is worse than
  /// none — and absent entirely when the model offered nothing.
  Widget _followUps() {
    final questions = FollowUps.parse(widget.message.content);
    if (questions.isEmpty || widget.onFollowUp == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final question in questions)
            Semantics(
              button: true,
              label: 'Ask: $question',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onFollowUp!(question);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: ExodusTheme.covenantGlow
                            .withValues(alpha: 0.32)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(question,
                      style: const TextStyle(
                        color: ExodusTheme.covenantGlow,
                        fontSize: 13,
                        height: 1.3,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _ActionBar(
        isAssistant: !_isUser,
        elapsedMs: widget.message.responseTimeMs,
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

  /// How long the reply took, shown at the end of the row. Null for user
  /// messages and for anything still streaming.
  final int? elapsedMs;
  final String ttsKey;
  final VoidCallback onCopy;
  final VoidCallback onPlay;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReader;

  const _ActionBar({
    required this.isAssistant,
    required this.elapsedMs,
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
        if (elapsedMs != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 10),
            child: Text(
              _formatElapsed(elapsedMs!),
              style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
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
