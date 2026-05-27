import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/chat_message.dart';
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

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == Sender.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const ExodusShield(size: 28, glow: false),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(
                        colors: [ExodusTheme.covenantBlue, Color(0xFF2D5BC8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isUser ? null : ExodusTheme.midnight,
                border: isUser
                    ? null
                    : Border.all(color: ExodusTheme.steel, width: 1),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: message.isLoading
                  ? _TypingIndicator(startTime: message.timestamp)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUser)
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
                        if (!isUser &&
                            !message.isStreaming &&
                            message.responseTimeMs != null)
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
                    ),
            ),
          ),
        ],
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
