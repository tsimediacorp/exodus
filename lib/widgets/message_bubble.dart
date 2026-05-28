import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/chat_message.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

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

  const MessageBubble({
    super.key,
    required this.message,
    this.onRegenerate,
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

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied'),
      duration: Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
        crossAxisAlignment:
            _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!_isUser) ...[
                const ExodusShield(size: 28, glow: false),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: GestureDetector(
                  onTap: _toggleActions,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: _isUser
                          ? const LinearGradient(
                              colors: [
                                ExodusTheme.covenantBlue,
                                Color(0xFF2D5BC8)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: _isUser ? null : ExodusTheme.midnight,
                      border: _isUser
                          ? null
                          : Border.all(color: ExodusTheme.steel, width: 1),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(_isUser ? 16 : 4),
                        bottomRight: Radius.circular(_isUser ? 4 : 16),
                      ),
                    ),
                    // Show the typing dots until real text actually arrives —
                    // not just until isLoading flips — so we never render an
                    // empty bubble with a lonely streaming cursor.
                    child: (message.content.trim().isEmpty &&
                            (message.isLoading || message.isStreaming))
                        ? _TypingIndicator(startTime: message.timestamp)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isUser)
                                SelectableText(
                                  message.content,
                                  style: const TextStyle(
                                    color: ExodusTheme.porcelain,
                                    fontSize: 15,
                                    height: 1.55,
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              else
                                GptMarkdown(
                                  message.content,
                                  style: const TextStyle(
                                    color: ExodusTheme.porcelain,
                                    fontSize: 15,
                                    height: 1.55,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              if (message.isStreaming)
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: _StreamingCursor(),
                                ),
                              if (!_isUser &&
                                  !message.isStreaming &&
                                  message.responseTimeMs != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _formatElapsed(message.responseTimeMs!),
                                    style: const TextStyle(
                                      color: ExodusTheme.ironMist,
                                      fontSize: 11,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (_showActions && _canShowActions)
            Padding(
              padding: EdgeInsets.only(
                top: 6,
                left: _isUser ? 0 : 38, // align past the shield avatar
              ),
              child: _ActionBar(
                isAssistant: !_isUser,
                ttsKey: _ttsKey,
                onCopy: _copy,
                onPlay: () =>
                    TtsService.instance.toggle(_ttsKey, message.content),
                onRegenerate: widget.onRegenerate,
              ),
            ),
        ],
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

  const _ActionBar({
    required this.isAssistant,
    required this.ttsKey,
    required this.onCopy,
    required this.onPlay,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(icon: Icons.copy_rounded, label: 'Copy', onTap: onCopy),
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
      ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
