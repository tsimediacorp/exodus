import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../config/bible_prompt.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../theme/exodus_theme.dart';

/// EXODUS explaining a passage the couple selected in the reader. Streams so
/// the answer starts appearing immediately rather than after a long wait.
class BibleExplainSheet extends StatefulWidget {
  final String reference;
  final String text;

  /// The couple's own question, when they asked one rather than just tapping
  /// "Explain".
  final String? question;

  const BibleExplainSheet({
    super.key,
    required this.reference,
    required this.text,
    this.question,
  });

  @override
  State<BibleExplainSheet> createState() => _BibleExplainSheetState();
}

class _BibleExplainSheetState extends State<BibleExplainSheet> {
  final AiService _ai = AiService();
  StreamSubscription<String>? _sub;

  String _answer = '';
  bool _streaming = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ai.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _answer = '';
      _streaming = true;
      _error = null;
    });
    _sub?.cancel();
    _sub = _ai
        .askStream(
          userMessage: BiblePrompt.explain(
            reference: widget.reference,
            text: widget.text,
            question: widget.question,
          ),
          history: const <ChatMessage>[],
        )
        .listen(
          (chunk) {
            if (mounted) setState(() => _answer += chunk);
          },
          onError: (e) {
            if (mounted) {
              setState(() {
                _streaming = false;
                _error = _friendly(e);
              });
            }
          },
          onDone: () {
            if (mounted) setState(() => _streaming = false);
          },
          cancelOnError: true,
        );
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (e is TimeoutException || s.contains('TimeoutException')) {
      return 'EXODUS took too long to answer.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (s.contains('(401)') || s.contains('(403)')) {
      return 'The API key was rejected. Check Settings.';
    }
    if (s.contains('(429)')) return 'Rate limited — try again in a moment.';
    return 'Something went wrong.';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ExodusTheme.steel,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Text(widget.reference.toUpperCase(),
                    style: const TextStyle(
                        color: ExodusTheme.brass,
                        fontSize: 12,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('“${widget.text}”',
                    style: const TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 14,
                        height: 1.5,
                        fontStyle: FontStyle.italic)),
                if (widget.question != null &&
                    widget.question!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ExodusTheme.covenantBlue.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(widget.question!,
                        style: const TextStyle(
                            color: ExodusTheme.porcelain,
                            fontSize: 14,
                            height: 1.45)),
                  ),
                ],
                const SizedBox(height: 18),
                const Divider(color: ExodusTheme.steel, height: 1),
                const SizedBox(height: 18),
                if (_error != null)
                  _errorBlock()
                else if (_answer.isEmpty && _streaming)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: ExodusTheme.brass, strokeWidth: 2),
                    ),
                  )
                else
                  GptMarkdown(
                    _answer,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 15,
                        height: 1.6),
                  ),
                if (_streaming && _answer.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('…',
                        style: TextStyle(
                            color: ExodusTheme.ironMist, fontSize: 16)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_error!,
            style: const TextStyle(
                color: ExodusTheme.porcelain, fontSize: 14, height: 1.5)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
          child: const Text('Try again'),
        ),
      ],
    );
  }
}
