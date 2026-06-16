import 'package:flutter/foundation.dart';
import '../models/memory_item.dart';
import 'storage_service.dart';

/// Persistent, cross-conversation memory about the couple. Loaded once at
/// startup (synchronous reads after that), mutated by [MemoryService] and the
/// Memory screen. Pure data + persistence — no model calls live here, so other
/// services can read [promptBlock] without a circular dependency.
class MemoryStore extends ChangeNotifier {
  MemoryStore._();
  static final MemoryStore instance = MemoryStore._();

  /// Cap so the injected context stays bounded.
  static const int maxItems = 60;

  final List<MemoryItem> _items = [];
  List<MemoryItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  void load() {
    _items
      ..clear()
      ..addAll(StorageService.instance.loadMemory());
    notifyListeners();
  }

  Future<void> _persist() async {
    await StorageService.instance.saveMemory(_items);
    notifyListeners();
  }

  bool _hasSimilar(String text) {
    final n = _norm(text);
    return _items.any((m) => _norm(m.text) == n);
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  /// Merge freshly-extracted facts, skipping near-duplicates and trimming to
  /// the cap (oldest first when over).
  Future<void> addMany(Iterable<String> texts, String source) async {
    var changed = false;
    for (final t in texts) {
      final text = t.trim();
      if (text.isEmpty || _hasSimilar(text)) continue;
      _items.add(MemoryItem.create(text, source));
      changed = true;
    }
    if (_items.length > maxItems) {
      _items.removeRange(0, _items.length - maxItems);
      changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> addManual(String text) async {
    if (text.trim().isEmpty) return;
    _items.add(MemoryItem.create(text.trim(), 'manual'));
    await _persist();
  }

  Future<void> updateText(String id, String text) async {
    final m = _items.where((e) => e.id == id).firstOrNull;
    if (m == null) return;
    m.text = text.trim();
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
  }

  /// The block injected into prompts. Empty string when there's nothing yet,
  /// so callers can append unconditionally.
  String promptBlock() {
    if (_items.isEmpty) return '';
    final lines = _items.map((m) => '- ${m.text}').join('\n');
    return '''

# ============================================================
# WHAT YOU REMEMBER ABOUT THIS COUPLE
# Durable context gathered from past conversations. Use it to personalize
# your counsel, coaching, and devotionals. Don't recite it back verbatim or
# bring it up unprompted — let it inform you naturally.
# ============================================================
$lines
''';
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
