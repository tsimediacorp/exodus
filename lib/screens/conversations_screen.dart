import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/page_backdrop.dart';

/// Every conversation, searchable and deletable.
///
/// This is what the drawer's chats section used to be. Home shows the most
/// recent eight; this is "See all" — and it is where deleting a conversation
/// now lives, since that was only ever reachable by swiping a drawer row
/// nobody knew was swipeable.
class ConversationsScreen extends StatefulWidget {
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  /// True when this sits beside the thread on the unfolded screen rather
  /// than being pushed over it. Embedded, it never pops (there is nothing
  /// to pop back to), drops the back button, and marks the open thread.
  final bool embedded;

  /// The conversation open in the thread beside this list, when [embedded].
  final String? selectedId;

  const ConversationsScreen({
    super.key,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    this.embedded = false,
    this.selectedId,
  });

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Conversation> get _conversations {
    final all = StorageService.instance.loadConversations()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_query.isEmpty) return all;
    final needle = _query.toLowerCase();
    return all
        .where((c) =>
            c.title.toLowerCase().contains(needle) ||
            c.messages.any((m) => m.content.toLowerCase().contains(needle)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _conversations;

    final embedded = widget.embedded;
    final body = SafeArea(
      // Beside the thread the list must not claim the rail's side inset or
      // the bottom one; the thread beside it owns those.
      left: !embedded,
      child: Column(
        children: [
          _searchBox(),
          Expanded(
            child: conversations.isEmpty
                ? _empty()
                : ShaderMask(
                    // Tiles dissolve at the top and bottom edges instead of
                    // being sliced off by them.
                    shaderCallback: (r) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0, 12 / r.height, 1 - 28 / r.height, 1],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: ListView.builder(
                      padding: embedded
                          ? const EdgeInsets.fromLTRB(12, 8, 14, 32)
                          : const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: conversations.length,
                      itemBuilder: (_, i) => _tile(conversations[i]),
                    ),
                  ),
          ),
        ],
      ),
    );

    return Scaffold(
      // Embedded, the list is a window onto the shell's own light, so it is
      // see-through; pushed full screen it lights itself.
      backgroundColor: embedded ? Colors.transparent : ExodusTheme.obsidian,
      appBar: AppBar(
        backgroundColor: embedded ? Colors.transparent : null,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.embedded,
        centerTitle: !widget.embedded,
        title: const Text('Conversations',
            style: TextStyle(
              fontFamily: ExodusTheme.serif,
              color: ExodusTheme.parchment,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            )),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded,
                color: ExodusTheme.brass, size: 24),
            tooltip: 'New conversation',
            onPressed: () {
              if (!widget.embedded) Navigator.of(context).pop();
              widget.onNew();
            },
          ),
        ],
      ),
      body: embedded ? body : PageBackdrop(child: body),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: widget.embedded
          ? const EdgeInsets.fromLTRB(12, 4, 14, 4)
          : const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.7),
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                size: 18, color: ExodusTheme.ironMist),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                style:
                    const TextStyle(color: ExodusTheme.porcelain, fontSize: 15),
                cursorColor: ExodusTheme.brass,
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search conversations…',
                  hintStyle:
                      TextStyle(color: ExodusTheme.ironMist, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          _query.isEmpty
              ? 'No conversations yet.'
              : 'Nothing matches “$_query”.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: ExodusTheme.ironMist, fontSize: 14),
        ),
      ),
    );
  }

  Widget _tile(Conversation conv) {
    return ConversationTile(
      key: ValueKey(conv.id),
      conversation: conv,
      dense: widget.embedded,
      selected: widget.embedded && conv.id == widget.selectedId,
      onOpen: () {
        if (!widget.embedded) Navigator.of(context).pop();
        widget.onOpen(conv.id);
      },
      onDelete: () {
        // Storage is updated synchronously by the delete, so rebuilding now
        // drops the dismissed row in the same frame, as Dismissible needs.
        widget.onDelete(conv.id);
        setState(() {});
      },
    );
  }
}
