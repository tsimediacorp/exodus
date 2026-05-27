import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AiService _ai = AiService();
  final StorageService _storage = StorageService.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Conversation> _conversations = [];
  Conversation? _current;
  bool _sending = false;
  StreamSubscription<String>? _activeStream;

  final List<String> _starters = const [
    'How do we lead our marriage spiritually as newlyweds?',
    'What does scripture say about money in marriage?',
    'I\'m struggling with lust. Where do I begin?',
    'How do we resolve conflict without wounding each other?',
  ];

  List<ChatMessage> get _messages => _current?.messages ?? const [];

  @override
  void initState() {
    super.initState();
    _conversations = _storage.loadConversations();
    final id = _storage.getCurrentConversationId();
    if (id != null) {
      final match = _conversations.where((c) => c.id == id).toList();
      _current = match.isNotEmpty ? match.first : null;
    }
    if (_messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    _input.dispose();
    _scroll.dispose();
    _ai.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await _storage.saveConversations(_conversations);
    await _storage.setCurrentConversationId(_current?.id);
  }

  Future<void> _send([String? text]) async {
    final content = (text ?? _input.text).trim();
    if (content.isEmpty || _sending) return;

    // Create-on-first-message: avoids empty "New conversation" entries in history.
    if (_current == null) {
      final conv = Conversation.empty();
      _conversations = [..._conversations, conv];
      _current = conv;
    }

    final conv = _current!;
    final userMsg = ChatMessage(content: content, sender: Sender.user);
    final replyMsg = ChatMessage(
      content: '',
      sender: Sender.exodus,
      isLoading: true,
      isStreaming: true,
    );

    setState(() {
      conv.messages.add(userMsg);
      conv.messages.add(replyMsg);
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();

    // Eager save so the user message survives an app crash mid-stream.
    conv.updatedAt = DateTime.now();
    await _persist();

    final history = conv.messages.sublist(0, conv.messages.length - 2);
    final completer = Completer<void>();
    final stopwatch = Stopwatch()..start();

    try {
      _activeStream = _ai
          .askStream(userMessage: content, history: history)
          .listen(
        (chunk) {
          setState(() {
            if (replyMsg.isLoading) replyMsg.isLoading = false;
            replyMsg.content += chunk;
          });
          _scrollToEnd();
        },
        onError: (err) {
          setState(() {
            replyMsg.isLoading = false;
            replyMsg.isStreaming = false;
            // Surface the actual API error verbatim so the user sees moderation
            // / restricted-key / rate-limit messages instead of a generic wrap.
            replyMsg.content = '**Request failed.**\n\n```\n$err\n```';
          });
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          setState(() {
            replyMsg.isLoading = false;
            replyMsg.isStreaming = false;
          });
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;
    } catch (e) {
      setState(() {
        replyMsg.isLoading = false;
        replyMsg.isStreaming = false;
        replyMsg.content = '**Request failed.**\n\n```\n$e\n```';
      });
    } finally {
      stopwatch.stop();
      // If the model hit the token cap, tell the user instead of leaving them
      // wondering why the reply ended mid-sentence.
      if (_ai.lastFinishReason == 'length' && replyMsg.content.isNotEmpty) {
        replyMsg.content +=
            '\n\n_(Response truncated — hit the max_tokens limit. Raise it in Settings.)_';
      }
      setState(() {
        _sending = false;
        replyMsg.isStreaming = false;
        replyMsg.responseTimeMs = stopwatch.elapsedMilliseconds;
      });
      _activeStream = null;
      conv.updatedAt = DateTime.now();
      if (conv.title == 'New conversation') {
        conv.deriveTitleFromFirstUserMessage();
      }
      await _persist();
      _scrollToEnd();
    }
  }

  void _newConversation() {
    _activeStream?.cancel();
    setState(() {
      _current = null;
      _sending = false;
    });
    _storage.setCurrentConversationId(null);
  }

  void _selectConversation(String id) {
    _activeStream?.cancel();
    final conv = _conversations.firstWhere((c) => c.id == id);
    setState(() {
      _current = conv;
      _sending = false;
    });
    _storage.setCurrentConversationId(conv.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  Future<void> _deleteConversation(String id) async {
    final wasCurrent = _current?.id == id;
    setState(() {
      _conversations = _conversations.where((c) => c.id != id).toList();
      if (wasCurrent) _current = null;
    });
    await _persist();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    setState(() {});
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: ConversationDrawer(
        conversations: _conversations,
        currentId: _current?.id,
        onNewConversation: _newConversation,
        onSelect: _selectConversation,
        onDelete: _deleteConversation,
      ),
      appBar: AppBar(
        title: const Text('EXODUS'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Conversations',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined,
                color: ExodusTheme.ironMist),
            tooltip: 'New conversation',
            onPressed: _newConversation,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: ExodusTheme.ironMist),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty ? _buildWelcome() : _buildMessages(),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const ExodusShield(size: 96),
          const SizedBox(height: 28),
          const Text(
            'Walk in His design.',
            style: TextStyle(
              color: ExodusTheme.porcelain,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Scripture-first answers for the questions that matter most in your marriage.',
            style: TextStyle(
              color: ExodusTheme.ironMist,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          ..._starters.map(_buildStarter),
        ],
      ),
    );
  }

  Widget _buildStarter(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _send(prompt),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            border: Border.all(color: ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: ExodusTheme.brass),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prompt,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward,
                  size: 14, color: ExodusTheme.ironMist),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => MessageBubble(message: _messages[i]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: ExodusTheme.porcelain),
              decoration: const InputDecoration(
                hintText: 'Ask EXODUS...',
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _sending
                      ? const [ExodusTheme.steel, ExodusTheme.slate]
                      : const [ExodusTheme.covenantBlue, ExodusTheme.covenantGlow],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: _sending
                    ? null
                    : [
                        BoxShadow(
                          color: ExodusTheme.covenantBlue.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
              ),
              child: const Icon(Icons.arrow_upward,
                  color: ExodusTheme.porcelain, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
