import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// The app-wide left drawer. Top section switches between the three modes
/// (Counsel / Coaching / Devotional); below it, the chats section lists the
/// Counsel conversations.
class AppDrawer extends StatelessWidget {
  final int currentMode;
  final ValueChanged<int> onSelectMode;

  final List<Conversation> conversations;
  final String? currentConversationId;
  final VoidCallback onNewConversation;
  final ValueChanged<String> onSelectConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onOpenMemory;

  const AppDrawer({
    super.key,
    required this.currentMode,
    required this.onSelectMode,
    required this.conversations,
    required this.currentConversationId,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onOpenMemory,
  });

  static const _modes = [
    (icon: Icons.menu_book_outlined, active: Icons.menu_book, label: 'Counsel'),
    (icon: Icons.spatial_audio_off_outlined, active: Icons.spatial_audio_off, label: 'Coaching'),
    (icon: Icons.wb_sunny_outlined, active: Icons.wb_sunny, label: 'Devotional'),
    (icon: Icons.favorite_outline, active: Icons.favorite, label: 'Together'),
  ];

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
            // ---- Modes ----
            for (var i = 0; i < _modes.length; i++) _modeTile(context, i),
            const Divider(color: ExodusTheme.steel, height: 24),
            // ---- Chats ----
            _sectionLabel('CHATS'),
            _newButton(context),
            Expanded(
              child: sorted.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) => _tile(context, sorted[i]),
                    ),
            ),
            const Divider(color: ExodusTheme.steel, height: 1),
            _footerTile(
              context,
              icon: Icons.psychology_outlined,
              label: 'Memory',
              onTap: onOpenMemory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerTile(BuildContext context,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ExodusTheme.ironMist),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          ExodusShield(size: 32, glow: false),
          SizedBox(width: 12),
          Text('EXODUS',
              style: TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              )),
        ],
      ),
    );
  }

  Widget _modeTile(BuildContext context, int i) {
    final m = _modes[i];
    final selected = i == currentMode;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onSelectMode(i);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? ExodusTheme.midnight : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? ExodusTheme.brass : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(selected ? m.active : m.icon,
                size: 20,
                color: selected ? ExodusTheme.covenantGlow : ExodusTheme.ironMist),
            const SizedBox(width: 14),
            Text(m.label,
                style: TextStyle(
                  color: selected ? ExodusTheme.porcelain : ExodusTheme.ironMist,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(
              color: ExodusTheme.ironMist,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }

  Widget _newButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop();
          onNewConversation();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            border: Border.all(color: ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.add, color: ExodusTheme.covenantGlow, size: 18),
              SizedBox(width: 10),
              Text('New conversation',
                  style: TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  )),
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
        child: Text('No conversations yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ExodusTheme.ironMist, fontSize: 13)),
      ),
    );
  }

  Widget _tile(BuildContext context, Conversation conv) {
    final isActive = conv.id == currentConversationId && currentMode == 0;
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
                    '"${conv.title}" will be permanently removed from this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete',
                          style: TextStyle(color: ExodusTheme.crimson))),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDeleteConversation(conv.id),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onSelectConversation(conv.id);
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
              Text(conv.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    height: 1.35,
                  )),
              const SizedBox(height: 4),
              Text(_formatDate(conv.updatedAt),
                  style: const TextStyle(color: ExodusTheme.ironMist, fontSize: 11)),
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
