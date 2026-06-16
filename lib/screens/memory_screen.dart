import 'package:flutter/material.dart';
import '../models/memory_item.dart';
import '../services/memory_store.dart';
import '../theme/exodus_theme.dart';

/// Lets the couple see, edit, add, and delete what EXODUS remembers about them.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = MemoryStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: ExodusTheme.ironMist),
            tooltip: 'Add memory',
            onPressed: () => _edit(context, null),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: ExodusTheme.ironMist),
            tooltip: 'Clear all',
            onPressed: () => _clearAll(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (_, __) {
            final items = store.items;
            if (items.isEmpty) return _empty();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _tile(context, items[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            "EXODUS hasn't learned anything to remember yet.\n\n"
            "As you talk in Counsel and Coaching, it will note durable things "
            "about your marriage here — and you can edit or remove any of them.",
            textAlign: TextAlign.center,
            style: TextStyle(color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
          ),
        ),
      );

  Widget _tile(BuildContext context, MemoryItem m) {
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: ExodusTheme.crimson.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: ExodusTheme.porcelain),
      ),
      onDismissed: (_) => MemoryStore.instance.remove(m.id),
      child: InkWell(
        onTap: () => _edit(context, m),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            border: Border.all(color: ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 12),
                child: Icon(Icons.psychology_outlined,
                    size: 18, color: ExodusTheme.brass),
              ),
              Expanded(
                child: Text(m.text,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain, fontSize: 14, height: 1.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, MemoryItem? existing) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: Text(existing == null ? 'Add memory' : 'Edit memory',
            style: const TextStyle(color: ExodusTheme.porcelain)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: ExodusTheme.porcelain),
          decoration: const InputDecoration(
              hintText: 'Something EXODUS should remember…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: ExodusTheme.ironMist)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: ExodusTheme.covenantBlue),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    if (existing == null) {
      await MemoryStore.instance.addManual(result);
    } else {
      await MemoryStore.instance.updateText(existing.id, result);
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    if (MemoryStore.instance.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Clear all memory?'),
        content: const Text(
            'EXODUS will forget everything it has learned about you. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (ok == true) await MemoryStore.instance.clear();
  }
}
