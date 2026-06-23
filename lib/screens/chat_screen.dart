import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/ai_service.dart';
import '../services/memory_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  /// Opens the app-wide left drawer (owned by HomeShell).
  final VoidCallback? onOpenMenu;
  const ChatScreen({super.key, this.onOpenMenu});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

/// Public so HomeShell can drive conversation selection from the shared drawer.
class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AiService _ai = AiService();
  final MemoryService _memory = MemoryService();
  final StorageService _storage = StorageService.instance;
  final ImagePicker _picker = ImagePicker();

  List<Conversation> _conversations = [];
  Conversation? _current;
  bool _sending = false;
  StreamSubscription<String>? _activeStream;

  /// Whether to show the "jump to latest" arrow (user has scrolled up).
  bool _showScrollDown = false;

  /// Images staged for the next message, as data URLs ("data:image/...;base64,").
  final List<String> _pendingImages = [];

  /// Cap attachments per message to keep request payloads sane.
  static const int _maxAttachments = 4;

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
    _scroll.addListener(_onScroll);
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

  /// Show the jump-to-latest arrow once the user has scrolled up from the end.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final show =
        _scroll.position.maxScrollExtent - _scroll.position.pixels > 240;
    if (show != _showScrollDown) setState(() => _showScrollDown = show);
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    TtsService.instance.stop();
    _input.dispose();
    _scroll.dispose();
    _ai.dispose();
    _memory.dispose();
    super.dispose();
  }

  /// Fire-and-forget: distill durable memory from a conversation we're leaving.
  void _captureMemory(Conversation? conv) {
    if (conv == null) return;
    final meaningful = conv.messages
        .where((m) => !m.isLoading && m.content.trim().isNotEmpty)
        .length;
    if (meaningful < 2) return;
    _memory.captureFromChat(List.of(conv.messages));
  }

  Future<void> _persist() async {
    await _storage.saveConversations(_conversations);
    await _storage.setCurrentConversationId(_current?.id);
  }

  /// Let the user pick where the image comes from, then pick one.
  Future<void> _attachImage() async {
    if (_pendingImages.length >= _maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Up to $_maxAttachments images per message.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: ExodusTheme.obsidian,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: ExodusTheme.ironMist),
              title: const Text('Choose from library',
                  style: TextStyle(color: ExodusTheme.porcelain)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: ExodusTheme.ironMist),
              title: const Text('Take a photo',
                  style: TextStyle(color: ExodusTheme.porcelain)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        // Downscale + compress so base64 payloads stay small enough for the
        // model context and local storage.
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = _mimeForPath(file.path);
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      if (!mounted) return;
      setState(() => _pendingImages.add(dataUrl));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach image: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  /// Decode the base64 payload of a "data:...;base64,XXXX" URL for display.
  static Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma == -1) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _send([String? text]) async {
    final content = (text ?? _input.text).trim();
    // Allow sending with images only (no text), but never an empty message.
    if ((content.isEmpty && _pendingImages.isEmpty) || _sending) return;

    // Create-on-first-message: avoids empty "New conversation" entries in history.
    if (_current == null) {
      final conv = Conversation.empty();
      _conversations = [..._conversations, conv];
      _current = conv;
    }

    final conv = _current!;
    final images = List<String>.from(_pendingImages);
    final userMsg =
        ChatMessage(content: content, sender: Sender.user, images: images);

    setState(() {
      conv.messages.add(userMsg);
      _input.clear();
      _pendingImages.clear();
    });

    await _streamReply(conv, prompt: content, images: images);
  }

  /// Regenerate the assistant reply at [assistantMsg]: drop it and re-run the
  /// user prompt that preceded it.
  Future<void> _regenerate(ChatMessage assistantMsg) async {
    final conv = _current;
    if (conv == null || _sending) return;
    final idx = conv.messages.indexOf(assistantMsg);
    if (idx <= 0) return;
    final userMsg = conv.messages[idx - 1];
    if (userMsg.sender != Sender.user) return;

    setState(() {
      conv.messages.removeAt(idx); // remove old assistant reply
    });
    await _streamReply(conv, prompt: userMsg.content, images: userMsg.images);
  }

  /// Shared streaming routine. Assumes the conversation's last message is the
  /// user turn we're replying to. Appends a placeholder assistant message,
  /// streams into it, and persists.
  Future<void> _streamReply(Conversation conv,
      {required String prompt, List<String> images = const []}) async {
    final replyMsg = ChatMessage(
      content: '',
      sender: Sender.exodus,
      isLoading: true,
      isStreaming: true,
    );

    setState(() {
      conv.messages.add(replyMsg);
      _sending = true;
    });
    _scrollToEnd();

    // Eager save so the user message survives an app crash mid-stream.
    conv.updatedAt = DateTime.now();
    await _persist();

    // History = everything before the prompt's reply placeholder and the
    // prompt turn itself (the prompt is passed separately to askStream).
    final history = conv.messages.sublist(0, conv.messages.length - 2);
    final completer = Completer<void>();
    final stopwatch = Stopwatch()..start();

    try {
      _activeStream = _ai
          .askStream(userMessage: prompt, history: history, images: images)
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
      // Stream finished but nothing came back — don't leave an empty bubble.
      if (replyMsg.content.trim().isEmpty) {
        replyMsg.content =
            '_(No response came back. Tap Regenerate to try again.)_';
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

  /// Id of the open conversation (null = none yet). Read by HomeShell's drawer.
  String? get currentId => _current?.id;

  void newConversation() {
    _captureMemory(_current);
    _activeStream?.cancel();
    TtsService.instance.stop();
    setState(() {
      _current = null;
      _sending = false;
    });
    _storage.setCurrentConversationId(null);
  }

  void openConversation(String id) {
    if (id != _current?.id) _captureMemory(_current);
    _activeStream?.cancel();
    TtsService.instance.stop();
    final conv = _conversations.firstWhere((c) => c.id == id);
    setState(() {
      _current = conv;
      _sending = false;
    });
    _storage.setCurrentConversationId(conv.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  Future<void> deleteConversationById(String id) async {
    final wasCurrent = _current?.id == id;
    setState(() {
      _conversations = _conversations.where((c) => c.id != id).toList();
      if (wasCurrent) _current = null;
    });
    await _persist();
  }

  /// Edit a previously sent user message: drop it and everything after it,
  /// then load its text back into the composer so the user can revise and
  /// resend (which re-streams EXODUS's reply from that point).
  void _editMessage(ChatMessage msg) {
    final conv = _current;
    if (conv == null || _sending) return;
    final idx = conv.messages.indexOf(msg);
    if (idx < 0) return;
    _activeStream?.cancel();
    TtsService.instance.stop();
    setState(() {
      _input.text = msg.content;
      _pendingImages
        ..clear()
        ..addAll(msg.images);
      conv.messages.removeRange(idx, conv.messages.length);
      _sending = false;
    });
    _persist();
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
      appBar: AppBar(
        title: const Text('EXODUS'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined,
                color: ExodusTheme.ironMist),
            tooltip: 'New conversation',
            onPressed: newConversation,
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
    return Stack(
      children: [
        _buildMessageList(),
        if (_showScrollDown)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: ExodusTheme.midnight,
                shape: const CircleBorder(
                  side: BorderSide(color: ExodusTheme.steel),
                ),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _scrollToEnd,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: ExodusTheme.covenantGlow, size: 26),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        return MessageBubble(
          // Keyed by identity so Flutter keeps each bubble's expanded/action
          // state attached to the right message as the list grows.
          key: ObjectKey(msg),
          message: msg,
          onRegenerate: msg.sender == Sender.exodus && !_sending
              ? () => _regenerate(msg)
              : null,
          onEdit: msg.sender == Sender.user && !_sending
              ? () => _editMessage(msg)
              : null,
          onDelete: !_sending ? () => _deleteMessage(msg) : null,
        );
      },
    );
  }

  /// Delete a single message (user or assistant) from the conversation.
  void _deleteMessage(ChatMessage msg) {
    final conv = _current;
    if (conv == null || _sending) return;
    setState(() => conv.messages.remove(msg));
    conv.updatedAt = DateTime.now();
    _persist();
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImages.isNotEmpty) _buildPendingImages(),
          Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            color: ExodusTheme.ironMist,
            tooltip: 'Attach image',
            onPressed: _sending ? null : _attachImage,
          ),
          const SizedBox(width: 4),
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
        ],
      ),
    );
  }

  /// Horizontal strip of staged-image thumbnails shown above the input row,
  /// each with a remove button.
  Widget _buildPendingImages() {
    return Container(
      height: 76,
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final bytes = _decodeDataUrl(_pendingImages[i]);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: bytes == null
                    ? const SizedBox(width: 68, height: 68)
                    : Image.memory(bytes,
                        width: 68, height: 68, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removePendingImage(i),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: ExodusTheme.obsidian,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.cancel,
                        size: 20, color: ExodusTheme.ironMist),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
