import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
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

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      appBar: AppBar(
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
      body: PageBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: widget.embedded
                    ? const EdgeInsets.fromLTRB(12, 4, 12, 12)
                    : const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: ExodusTheme.midnight.withValues(alpha: 0.7),
                    border: Border.all(color: ExodusTheme.steel),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          size: 18, color: ExodusTheme.ironMist),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (v) =>
                              setState(() => _query = v.trim()),
                          style: const TextStyle(
                              color: ExodusTheme.porcelain, fontSize: 15),
                          cursorColor: ExodusTheme.brass,
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: 'Search conversations…',
                            hintStyle: TextStyle(
                                color: ExodusTheme.ironMist, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: widget.embedded
                            ? const EdgeInsets.fromLTRB(12, 0, 12, 24)
                            : const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: conversations.length,
                        itemBuilder: (_, i) => _tile(conversations[i]),
                      ),
              ),
            ],
          ),
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
    final isOpen = widget.embedded && conv.id == widget.selectedId;
    final preview = conv.messages.isEmpty
        ? 'No messages yet'
        : conv.messages.last.content.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(conv.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: ExodusTheme.crimson.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: ExodusTheme.porcelain),
        ),
        confirmDismiss: (_) async =>
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ExodusTheme.midnight,
                title: const Text('Delete conversation?'),
                content: Text(
                    '“${conv.title}” will be permanently removed from this '
                    'device.'),
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
            ) ??
            false,
        onDismissed: (_) {
          widget.onDelete(conv.id);
          setState(() {});
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!widget.embedded) Navigator.of(context).pop();
            widget.onOpen(conv.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isOpen
                  ? ExodusTheme.brass.withValues(alpha: 0.10)
                  : ExodusTheme.midnight.withValues(alpha: 0.72),
              border: Border.all(
                  color: isOpen
                      ? ExodusTheme.brass.withValues(alpha: 0.55)
                      : ExodusTheme.steel),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ExodusTheme.slate,
                    border: Border.all(
                        color: ExodusTheme.brass.withValues(alpha: 0.30)),
                  ),
                  child: const ExodusShield(size: 19, glow: false),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(conv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ExodusTheme.porcelain,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 4),
                      Text(preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: ExodusTheme.ironMist,
                              fontSize: 13,
                              height: 1.4)),
                    ],
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
