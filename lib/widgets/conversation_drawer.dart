import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

class ConversationDrawer extends StatelessWidget {
  final List<Conversation> conversations;
  final String? currentId;
  final VoidCallback onNewConversation;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  const ConversationDrawer({
    super.key,
    required this.conversations,
    required this.currentId,
    required this.onNewConversation,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Drawer(
      backgroundColor: ExodusTheme.obsidian,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            _newButton(context),
            const Divider(color: ExodusTheme.steel, height: 1),
            Expanded(
              child: sorted.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) => _tile(context, sorted[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          ExodusShield(size: 32, glow: false),
          SizedBox(width: 12),
          Text(
            'EXODUS',
            style: TextStyle(
              color: ExodusTheme.porcelain,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _newButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop();
          onNewConversation();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            border: Border.all(color: ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.add, color: ExodusTheme.covenantGlow, size: 18),
              SizedBox(width: 10),
              Text(
                'New conversation',
                style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No conversations yet.\nTap "New conversation" to begin.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ExodusTheme.ironMist, fontSize: 13, height: 1.5),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Conversation conv) {
    final isActive = conv.id == currentId;
    return Dismissible(
      key: ValueKey(conv.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: ExodusTheme.crimson.withValues(alpha: 0.85),
        child: const Icon(Icons.delete_outline, color: ExodusTheme.porcelain),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: ExodusTheme.midnight,
                title: const Text('Delete conversation?'),
                content: Text(
                  '"${conv.title}" will be permanently removed from this device.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete',
                        style: TextStyle(color: ExodusTheme.crimson)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(conv.id),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onSelect(conv.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? ExodusTheme.midnight : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? ExodusTheme.brass : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conv.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? ExodusTheme.porcelain : ExodusTheme.porcelain,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(conv.updatedAt),
                style: const TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d/${dt.year}';
  }
}
