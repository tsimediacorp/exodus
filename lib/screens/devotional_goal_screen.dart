import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../config/devotional_prompt.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/devotional_service.dart';
import '../services/progress.dart';
import '../theme/exodus_theme.dart';
import '../widgets/progress_view.dart';

/// Conversational goal intake. EXODUS interviews the couple to draw out one
/// clear devotional goal. Returns the agreed goal string via Navigator.pop,
/// or null if cancelled. Used both for first-time setup and to shift the goal.
class DevotionalGoalScreen extends StatefulWidget {
  final String? currentGoal;
  const DevotionalGoalScreen({super.key, this.currentGoal});

  @override
  State<DevotionalGoalScreen> createState() => _DevotionalGoalScreenState();
}

class _DevotionalGoalScreenState extends State<DevotionalGoalScreen> {
  final AiService _ai = AiService();
  final DevotionalService _devo = DevotionalService();
  final ProgressController _status = ProgressController();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _busy = false;
  bool _firstUserTurn = true;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      sender: Sender.exodus,
      content: widget.currentGoal == null
          ? DevotionalPrompt.goalIntakeOpener()
          : 'Your current goal is:\n\n"${widget.currentGoal}"\n\nWhat would you '
              'like to shift it toward?',
    ));
  }

  @override
  void dispose() {
    _ai.dispose();
    _devo.dispose();
    _status.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    // Steer the model into goal-coach mode on the first turn only.
    final prompt =
        _firstUserTurn ? '${DevotionalPrompt.goalIntakeGuidance()}\n\n$text' : text;
    _firstUserTurn = false;

    final reply = ChatMessage(sender: Sender.exodus, content: '', isStreaming: true);
    setState(() {
      _messages.add(ChatMessage(sender: Sender.user, content: text));
      _messages.add(reply);
      _input.clear();
      _busy = true;
    });
    _scrollEnd();

    final history = _messages.sublist(0, _messages.length - 2);
    try {
      await for (final chunk
          in _ai.askStream(userMessage: prompt, history: history)) {
        if (!mounted) return;
        setState(() => reply.content += chunk);
        _scrollEnd();
      }
    } catch (e) {
      // Backing out mid-stream disposes the client and throws here, so every
      // setState below needs the mounted guard.
      if (mounted) {
        setState(() => reply.content = reply.content.isEmpty
            ? _friendlyError(e)
            : '${reply.content}\n\n_(cut off: ${_friendlyError(e)})_');
      }
    } finally {
      if (mounted) {
        setState(() {
          reply.isStreaming = false;
          _busy = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (e is TimeoutException || s.contains('TimeoutException')) {
      return 'EXODUS took too long to respond. Try again.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (s.contains('(401)') || s.contains('(403)')) {
      return 'The API key was rejected. Check Settings.';
    }
    if (s.contains('(429)')) return 'Rate limited — try again in a moment.';
    return 'Something went wrong. Try again.';
  }

  /// The couple's own words, as a starting point when the model can't
  /// summarise — better than handing them an empty box.
  String get _lastUserMessage => _messages
      .lastWhere((m) => m.sender == Sender.user,
          orElse: () => ChatMessage(sender: Sender.user, content: ''))
      .content
      .trim();

  Future<void> _saveGoal() async {
    if (_busy) return;
    setState(() => _busy = true);
    String goal = '';
    var failed = false;
    try {
      _status.begin('Reading your conversation…');
      goal = await _devo.summarizeGoal(_messages, progress: _status);
    } catch (_) {
      failed = true;
    } finally {
      _status.done();
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    // ask() returns '' WITHOUT throwing when a reasoning model burns its whole
    // budget on hidden reasoning, so an empty result is a failure too — it used
    // to open an empty dialog whose Save button silently did nothing.
    if (goal.isEmpty) {
      failed = true;
      goal = widget.currentGoal ?? _lastUserMessage;
    }
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'EXODUS couldn\'t summarise your goal — write it in your own '
              'words below.'),
          backgroundColor: ExodusTheme.steel,
        ),
      );
    }

    final controller = TextEditingController(text: goal);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Your devotional goal',
            style: TextStyle(color: ExodusTheme.porcelain)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: goal.isEmpty,
          style: const TextStyle(color: ExodusTheme.porcelain),
          decoration: const InputDecoration(hintText: 'Our goal…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: ExodusTheme.ironMist)),
          ),
          // Rebuild on every keystroke so Save is genuinely disabled while
          // empty rather than looking tappable and doing nothing.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.covenantBlue),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (confirmed == true && text.isNotEmpty && mounted) {
      Navigator.of(context).pop(text);
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.currentGoal == null ? 'Set your goal' : 'Shift your goal'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _saveGoal,
            // foregroundColor rather than a hardcoded colour on the child, so
            // the disabled state is actually visible.
            style: TextButton.styleFrom(
              foregroundColor: ExodusTheme.covenantGlow,
              disabledForegroundColor: ExodusTheme.steel,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: ExodusTheme.steel),
                  )
                : const Text('Save goal'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _bubble(_messages[i]),
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ProgressStrip(controller: _status),
              ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final isUser = m.sender == Sender.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? ExodusTheme.covenantBlue : ExodusTheme.midnight,
          border: isUser ? null : Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        // GptMarkdown, matching Counsel — plain Text rendered the model's
        // **bold** and headings as literal asterisks and hashes here.
        child: m.content.isEmpty && m.isStreaming
            ? const Text('…',
                style: TextStyle(color: ExodusTheme.porcelain, fontSize: 15))
            : GptMarkdown(
                m.content,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 15, height: 1.45),
              ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: ExodusTheme.porcelain),
              decoration: const InputDecoration(hintText: 'Answer EXODUS…'),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.arrow_upward, color: ExodusTheme.covenantGlow),
          ),
        ],
      ),
    );
  }
}
