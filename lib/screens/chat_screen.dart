import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../models/check_in.dart';
import '../models/conversation.dart';
import '../services/ai_service.dart';
import '../services/check_in_service.dart';
import '../services/conversation_search.dart';
import '../services/memory_service.dart';
import '../services/progress.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/check_in_card.dart';
import '../widgets/message_bubble.dart';
import '../widgets/progress_view.dart';

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
  final ProgressController _status = ProgressController();

  List<Conversation> _conversations = [];
  Conversation? _current;
  bool _sending = false;
  StreamSubscription<String>? _activeStream;

  /// Completed when the active stream ends. Held here (not just as a local in
  /// _send) so "Stop" can release the awaiting send — cancelling a
  /// subscription does NOT fire onDone, so without this the send would hang.
  Completer<void>? _activeCompleter;

  /// Set when the user hits Stop, so the finished reply is labelled as stopped
  /// rather than as an empty/failed response.
  bool _stopRequested = false;

  Timer? _draftDebounce;

  /// Whether to show the "jump to latest" arrow (user has scrolled up).
  bool _showScrollDown = false;

  /// Images staged for the next message, as data URLs ("data:image/...;base64,").
  final List<String> _pendingImages = [];

  /// Cap attachments per message to keep request payloads sane.
  static const int _maxAttachments = 4;

  // ---------------- In-conversation search ----------------

  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  /// Every occurrence of the search term in the open conversation, in thread
  /// order: which message, and which occurrence within that message. Flat
  /// rather than grouped so "4 of 17" counts what the user counts.
  List<({int message, int occurrence})> _matches = const [];
  int _activeMatch = 0;

  /// Keys on the messages that contain a match, so the active one can be
  /// scrolled to. Only matching messages get one — a key per message would
  /// cost the whole thread for a feature most sessions never open.
  final Map<int, GlobalKey> _matchKeys = {};

  /// Whether the composer has anything to send. Tracked so the send button can
  /// go flat when there's nothing to do without rebuilding on every keystroke.
  bool _hasDraft = false;

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
    // Restore anything typed but never sent before the app was killed.
    _input.text = _storage.loadComposerDraft();
    _hasDraft = _input.text.trim().isNotEmpty;
    _input.addListener(_saveDraft);
    _input.addListener(_onInputChanged);
    _conversations = _storage.loadConversations();
    final id = _storage.getCurrentConversationId();
    if (id != null) {
      final match = _conversations.where((c) => c.id == id).toList();
      _current = match.isNotEmpty ? match.first : null;
    }
    if (_messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
    // The banner reads straight off the service, so it needs a nudge when the
    // queue changes while this screen is already built — a background scan
    // landing, or the tester forcing one from Settings.
    CheckInService.instance.addListener(_onCheckInsChanged);
    // Background, best-effort: look through memory for anything worth coming
    // back to. Rate-limited inside the service, and silent on failure.
    unawaited(CheckInService.instance.scan());
  }

  void _onCheckInsChanged() {
    if (mounted) setState(() {});
  }

  /// Only rebuilds when the composer crosses empty/non-empty, not on every
  /// keystroke — the send button is the only thing that cares.
  void _onInputChanged() {
    final has = _input.text.trim().isNotEmpty;
    if (has != _hasDraft) setState(() => _hasDraft = has);
  }

  // ---------------- In-conversation search ----------------

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _search.clear();
    setState(() {
      _searching = false;
      _matches = const [];
      _activeMatch = 0;
      _matchKeys.clear();
    });
  }

  void _onSearchChanged(String raw) {
    final found = ConversationSearch.matches(
        [for (final m in _messages) m.content], raw);
    _matchKeys.clear();
    for (final match in found) {
      _matchKeys.putIfAbsent(match.message, () => GlobalKey());
    }
    setState(() {
      _matches = found;
      _activeMatch = 0;
    });
    if (found.isNotEmpty) unawaited(_revealMatch());
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    HapticFeedback.selectionClick();
    // Dart's % is non-negative for a positive divisor, so stepping back from
    // the first match wraps to the last one.
    setState(() => _activeMatch = (_activeMatch + delta) % _matches.length);
    unawaited(_revealMatch());
  }

  /// Bring the active match on screen.
  ///
  /// The thread is a lazy list, so the target message often isn't built yet
  /// and has no context to scroll to. Jump to a proportional estimate, let a
  /// frame settle so the builder catches up, then correct with
  /// [Scrollable.ensureVisible]. Repeated a few times because one estimate can
  /// land short when message lengths are very uneven; it gives up quietly
  /// rather than looping if the target never materialises.
  Future<void> _revealMatch() async {
    if (_matches.isEmpty) return;
    final target = _matches[_activeMatch].message;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      final ctx = _matchKeys[target]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.25,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final count = _messages.length;
      final fraction = count < 2 ? 0.0 : target / (count - 1);
      _scroll.jumpTo(fraction * _scroll.position.maxScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  /// Which occurrence inside [messageIndex] is the selected one, or null when
  /// the selected match lives in a different message.
  int? _activeOccurrenceIn(int messageIndex) {
    if (_matches.isEmpty) return null;
    final active = _matches[_activeMatch];
    return active.message == messageIndex ? active.occurrence : null;
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
    _draftDebounce?.cancel();
    CheckInService.instance.removeListener(_onCheckInsChanged);
    TtsService.instance.stop();
    _input.removeListener(_saveDraft);
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _search.dispose();
    _scroll.dispose();
    _status.dispose();
    _ai.dispose();
    _memory.dispose();
    super.dispose();
  }

  /// Debounced so we're not hitting prefs on every keystroke.
  void _saveDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400),
        () => _storage.saveComposerDraft(_input.text));
  }

  void _sendWithHaptic() {
    HapticFeedback.lightImpact();
    _send();
  }

  /// Stop the in-flight reply, keeping whatever text already arrived.
  /// Cancelling the subscription doesn't fire onDone, so the completer has to
  /// be released by hand or _send would wait forever.
  void _stopGenerating() {
    if (!_sending) return;
    HapticFeedback.lightImpact();
    _status.done();
    _stopRequested = true;
    _activeStream?.cancel();
    _activeStream = null;
    if (_activeCompleter?.isCompleted == false) _activeCompleter!.complete();
  }

  /// Plain-language message for a failed request. The raw provider text is
  /// kept underneath in a details block rather than dumped as the whole reply.
  String _errorMessage(Object err) {
    final s = err.toString();
    String headline;
    if (err is TimeoutException || s.contains('TimeoutException')) {
      headline = 'EXODUS took too long to respond.';
    } else if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused')) {
      headline = 'No internet connection.';
    } else if (s.contains('(401)') || s.contains('(403)')) {
      headline = 'The API key was rejected. Check it in Settings.';
    } else if (s.contains('(429)')) {
      headline = 'Rate limited — wait a moment and try again.';
    } else if (s.contains('No API key configured')) {
      headline = 'No API key is set up. Add one in Settings.';
    } else {
      headline = 'The request failed.';
    }
    return '**$headline**\n\nTap Regenerate to try again.\n\n'
        '<details><summary>Details</summary>\n\n```\n$s\n```\n\n</details>';
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

  /// Send a message.
  ///
  /// [overridePrompt] sends something other than the composer's contents.
  /// With [silentPrompt] the prompt is sent to the model but NOT added to the
  /// thread — used to seed a check-in, where the instruction primes EXODUS's
  /// opening line and would be nonsense shown as a message from the couple.
  Future<void> _send([
    String? text,
    String? overridePrompt,
    bool silentPrompt = false,
  ]) async {
    final content = (overridePrompt ?? text ?? _input.text).trim();
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

    setState(() {
      if (!silentPrompt) {
        conv.messages.add(
            ChatMessage(content: content, sender: Sender.user, images: images));
      }
      _input.clear();
      // The message is now in the conversation — drop the saved draft.
      _draftDebounce?.cancel();
      _storage.saveComposerDraft('');
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
    _activeCompleter = completer;
    final stopwatch = Stopwatch()..start();

    try {
      _status.begin(images.isEmpty
          ? 'Sending to EXODUS…'
          : 'Sending with ${images.length} image${images.length == 1 ? '' : 's'}…');
      _activeStream = _ai
          .askStream(
              userMessage: prompt,
              history: history,
              images: images,
              progress: _status)
          .listen(
        (chunk) {
          setState(() {
            if (replyMsg.isLoading) replyMsg.isLoading = false;
            replyMsg.content += chunk;
          });
          // Only follow along if the user is already at the bottom. Scrolling
          // unconditionally yanked them back down mid-read on every token.
          if (!_showScrollDown) _scrollToEnd();
        },
        onError: (err) {
          setState(() {
            replyMsg.isLoading = false;
            replyMsg.isStreaming = false;
            replyMsg.content = _errorMessage(err);
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
        replyMsg.content = _errorMessage(e);
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
        replyMsg.content = _stopRequested
            ? '_(Stopped.)_'
            : '_(No response came back. Tap Regenerate to try again.)_';
      } else if (_stopRequested) {
        replyMsg.content += '\n\n_(Stopped.)_';
      }
      _stopRequested = false;
      setState(() {
        _sending = false;
        replyMsg.isStreaming = false;
        // Stopping cancels the subscription, so onDone never fires and this
        // would stay true — which would drop the message from the history
        // sent on the next turn (_buildBody filters out isLoading messages).
        replyMsg.isLoading = false;
        replyMsg.responseTimeMs = stopwatch.elapsedMilliseconds;
      });
      _status.done();
      _activeStream = null;
      _activeCompleter = null;
      conv.updatedAt = DateTime.now();
      if (conv.title == 'New conversation') {
        conv.deriveTitleFromFirstUserMessage();
      }
      await _persist();
      if (!_showScrollDown) _scrollToEnd();
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
      appBar: _searching ? _searchBar() : _appBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Something EXODUS remembered and means to come back to. Sits
            // above the thread rather than interrupting it, and only when
            // nothing is being sent. Hidden while searching: it would shift
            // every match by its own height mid-scroll.
            if (!_sending && !_searching) _checkInBanner(),
            Expanded(
              child: _messages.isEmpty && !_searching
                  ? _buildWelcome()
                  : _buildMessages(),
            ),
            if (_searching) _searchFooter() else _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final title = _current?.title.trim() ?? '';
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
        tooltip: 'Menu',
        onPressed: widget.onOpenMenu,
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('EXODUS',
              style: TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              )),
          // Which conversation is open was visible only inside the drawer.
          if (title.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 11)),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded, color: ExodusTheme.ironMist),
          tooltip: 'Search this conversation',
          onPressed: _messages.isEmpty ? null : _openSearch,
        ),
        IconButton(
          icon: const Icon(Icons.add_comment_outlined,
              color: ExodusTheme.ironMist),
          tooltip: 'New conversation',
          onPressed: newConversation,
        ),
        // Settings moved out of here — it is pinned at the bottom of the
        // drawer, reachable from every mode, and this bar needed the room.
      ],
    );
  }

  /// The app bar in search mode. Replaces the bar rather than sliding in under
  /// it, so the thread doesn't jump by a bar's height when search opens.
  PreferredSizeWidget _searchBar() {
    final total = _matches.length;
    final hasQuery = _search.text.trim().isNotEmpty;
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: ExodusTheme.ironMist),
        tooltip: 'Close search',
        onPressed: _closeSearch,
      ),
      title: Container(
        height: 38,
        padding: const EdgeInsets.only(left: 13, right: 4),
        decoration: BoxDecoration(
          color: ExodusTheme.slate,
          border: Border.all(color: ExodusTheme.covenantBlue),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                size: 15, color: ExodusTheme.covenantGlow),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _stepMatch(1),
                cursorColor: ExodusTheme.covenantGlow,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 15),
                // The app-wide input theme fills and outlines every field.
                // Inside the pill that would draw a box within a box.
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search this conversation',
                  hintStyle:
                      TextStyle(color: ExodusTheme.ironMist, fontSize: 14),
                ),
              ),
            ),
            if (hasQuery)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  total == 0 ? 'none' : '${_activeMatch + 1}/$total',
                  style: const TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          color: ExodusTheme.ironMist,
          disabledColor: ExodusTheme.steel,
          tooltip: 'Previous match',
          onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          color: ExodusTheme.porcelain,
          disabledColor: ExodusTheme.steel,
          tooltip: 'Next match',
          onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
        ),
      ],
    );
  }

  /// Stands in for the composer while searching — there is nothing to type
  /// into, and the keyboard belongs to the search field.
  Widget _searchFooter() {
    final total = _matches.length;
    final hasQuery = _search.text.trim().isNotEmpty;
    final label = !hasQuery
        ? 'Type to search this conversation'
        : total == 0
            ? 'No matches'
            : '$total ${total == 1 ? 'match' : 'matches'} in this conversation';
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 15, color: ExodusTheme.ironMist),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _checkInBanner() {
    final checkIn = CheckInService.instance.current;
    if (checkIn == null) return const SizedBox.shrink();
    return CheckInCard(
      checkIn: checkIn,
      onChanged: () => setState(() {}),
      onOpen: () => _openCheckIn(checkIn),
    );
  }

  /// Take a check-in into a fresh conversation, seeded so EXODUS opens by
  /// naming what it remembered rather than waiting to be prompted.
  Future<void> _openCheckIn(CheckIn checkIn) async {
    await CheckInService.instance.markAnswered(checkIn);
    if (!mounted) return;

    _captureMemory(_current);
    final conv = Conversation.empty()..title = 'Checking in';
    setState(() {
      _conversations.insert(0, conv);
      _current = conv;
    });
    await _persist();
    if (!mounted) return;

    // The seed is instruction, not dialogue — it primes the reply without
    // appearing in the thread as something the couple said.
    await _send(null, CheckInService.instance.seedPrompt(checkIn), true);
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 32),
      child: Column(
        children: [
          const ExodusShield(size: 88),
          const SizedBox(height: 30),
          const Text(
            'Walk in His design.',
            style: TextStyle(
              color: ExodusTheme.porcelain,
              fontSize: 25,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const Text(
              'Scripture-first answers for the questions that matter most in your marriage.',
              style: TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 14,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          ..._starters.map(_buildStarter),
        ],
      ),
    );
  }

  /// A conversation starter.
  ///
  /// The outline comes off: four bordered cards in a column read as a form to
  /// fill in. Fill alone separates them from the ground, and the brass mark
  /// carries the invitation.
  Widget _buildStarter(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: () => _send(prompt),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: ExodusTheme.brass),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  prompt,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: ExodusTheme.ironMist),
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
        // While searching, the up/down match controls own vertical movement —
        // a second jump affordance would just fight them.
        if (_showScrollDown && !_searching)
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
        final bubble = MessageBubble(
          // Keyed by identity so Flutter keeps each bubble's expanded/action
          // state attached to the right message as the list grows.
          key: ObjectKey(msg),
          message: msg,
          searchQuery: _searching ? _search.text.trim() : '',
          activeOccurrence: _searching ? _activeOccurrenceIn(i) : null,
          onRegenerate: msg.sender == Sender.exodus && !_sending
              ? () => _regenerate(msg)
              : null,
          onEdit: msg.sender == Sender.user && !_sending
              ? () => _editMessage(msg)
              : null,
          onDelete: !_sending ? () => _deleteMessage(msg) : null,
        );
        // The match key goes on a wrapper, not the bubble: the bubble already
        // carries an ObjectKey, and a widget can only hold one.
        final matchKey = _matchKeys[i];
        return matchKey == null ? bubble : KeyedSubtree(key: matchKey, child: bubble);
      },
    );
  }

  /// Delete a single message (user or assistant) from the conversation.
  /// Confirmed first — the action row sits at thumb height and Delete is one
  /// mis-tap away from Copy. Matches the conversation-delete flow in the drawer.
  Future<void> _deleteMessage(ChatMessage msg) async {
    final conv = _current;
    if (conv == null || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Delete message?'),
        content: const Text('This message will be removed from the conversation.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => conv.messages.remove(msg));
    conv.updatedAt = DateTime.now();
    await _persist();
  }

  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_sending)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ProgressStrip(controller: _status),
          ),
        _composer(),
      ],
    );
  }

  Widget _composer() {
    final canSend = _hasDraft || _pendingImages.isNotEmpty;
    return Container(
      color: ExodusTheme.obsidian,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      // One pill holding attach, field and send. Previously the bar was a
      // full-width slab with a rule above it and a 48pt button hanging off the
      // end; the send button now sits inside the same object it acts on.
      child: Container(
        decoration: BoxDecoration(
          color: ExodusTheme.slate,
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: EdgeInsets.fromLTRB(6, _pendingImages.isNotEmpty ? 10 : 5, 5, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImages.isNotEmpty) _buildPendingImages(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 21),
                    color: ExodusTheme.ironMist,
                    disabledColor: ExodusTheme.steel,
                    tooltip: 'Attach image',
                    onPressed: _sending ? null : _attachImage,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: _input,
                      maxLines: 5,
                      minLines: 1,
                      // Multi-line composing: Return inserts a newline, so
                      // there's no onSubmitted callback to hang a send off
                      // (it never fires).
                      textInputAction: TextInputAction.newline,
                      cursorColor: ExodusTheme.covenantGlow,
                      style: const TextStyle(
                          color: ExodusTheme.porcelain, fontSize: 15),
                      // The field is inside the pill now, so it must not draw
                      // the app-wide fill and outline of its own.
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Ask EXODUS...',
                      ),
                    ),
                  ),
                ),
                // While streaming this becomes a Stop button — the
                // subscription was already cancellable, it just had no way to
                // reach it.
                Semantics(
                  button: true,
                  label: _sending ? 'Stop generating' : 'Send message',
                  child: GestureDetector(
                    onTap: _sending
                        ? _stopGenerating
                        : (canSend ? _sendWithHaptic : null),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        // Flat steel until there is something to send, so the
                        // glowing button always means "this will do something".
                        gradient: (!_sending && canSend)
                            ? const LinearGradient(
                                colors: [
                                  ExodusTheme.covenantBlue,
                                  ExodusTheme.covenantGlow
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: (!_sending && canSend) ? null : ExodusTheme.steel,
                        shape: BoxShape.circle,
                        boxShadow: (!_sending && canSend)
                            ? [
                                BoxShadow(
                                  color: ExodusTheme.covenantBlue
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        _sending ? Icons.stop_rounded : Icons.arrow_upward,
                        color: (_sending || canSend)
                            ? ExodusTheme.porcelain
                            : ExodusTheme.ironMist,
                        size: _sending ? 18 : 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal strip of staged-image thumbnails shown above the input row,
  /// each with a remove button.
  Widget _buildPendingImages() {
    // Sized from the text scale so the thumbnails don't clip when the user
    // has large type turned on.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final thumb = 68.0 * (scale > 1 ? scale.clamp(1.0, 1.4) : 1.0);
    return Container(
      height: thumb + 8,
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final bytes = _decodeDataUrl(_pendingImages[i]);
          // The remove button lives INSIDE the Stack's bounds — it used to be
          // Positioned at -6,-6, and Flutter doesn't hit-test children outside
          // their parent, so the outer edge of the button was dead.
          return SizedBox(
            width: thumb,
            height: thumb,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: bytes == null
                      ? SizedBox(width: thumb, height: thumb)
                      : Image.memory(bytes,
                          width: thumb, height: thumb, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: 'Remove attachment',
                    child: GestureDetector(
                      onTap: () => _removePendingImage(i),
                      // Transparent padding widens the tap target without
                      // making the visible chip any bigger.
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ExodusTheme.obsidian,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.cancel,
                              size: 22, color: ExodusTheme.ironMist),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
