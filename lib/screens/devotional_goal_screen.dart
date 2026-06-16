import 'dart:async';
import 'package:flutter/material.dart';
import '../config/devotional_prompt.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/devotional_service.dart';
import '../theme/exodus_theme.dart';

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
        setState(() => reply.content += chunk);
        _scrollEnd();
      }
    } catch (e) {
      setState(() => reply.content = 'Something went wrong: $e');
    } finally {
      setState(() {
        reply.isStreaming = false;
        _busy = false;
      });
    }
  }

  Future<void> _saveGoal() async {
    if (_busy) return;
    setState(() => _busy = true);
    String goal;
    try {
      goal = await _devo.summarizeGoal(_messages);
    } catch (_) {
      goal = widget.currentGoal ?? '';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
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
          style: const TextStyle(color: ExodusTheme.porcelain),
          decoration: const InputDecoration(hintText: 'Our goal…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: ExodusTheme.ironMist)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ExodusTheme.covenantBlue),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && controller.text.trim().isNotEmpty && mounted) {
      Navigator.of(context).pop(controller.text.trim());
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
            child: const Text('Save goal',
                style: TextStyle(color: ExodusTheme.covenantGlow, fontWeight: FontWeight.w600)),
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
        child: Text(
          m.content.isEmpty && m.isStreaming ? '…' : m.content,
          style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15, height: 1.45),
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
