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
  /// the cap.
  Future<void> addMany(Iterable<String> texts, String source) async {
    var changed = false;
    for (final t in texts) {
      final text = t.trim();
      if (text.isEmpty || _hasSimilar(text)) continue;
      _items.add(MemoryItem.create(text, source));
      changed = true;
    }
    if (_trim()) changed = true;
    if (changed) await _persist();
  }

  /// Drop the oldest LEARNED facts until the list fits.
  ///
  /// This used to remove from the front regardless of where a line came from,
  /// so the first thing a couple ever typed in by hand was also the first
  /// thing forgotten once EXODUS had inferred sixty others. Anything they
  /// wrote themselves, and any stated preference, now outlives anything
  /// inferred.
  bool _trim() {
    var changed = false;
    while (_items.length > maxItems) {
      var at = _items.indexWhere((m) => !m.pinned && !m.isPreference);
      if (at < 0) at = _items.indexWhere((m) => !m.pinned);
      if (at < 0) at = 0;
      _items.removeAt(at);
      changed = true;
    }
    return changed;
  }

  Future<void> addManual(String text) async {
    if (text.trim().isEmpty) return;
    _items.add(MemoryItem.create(text.trim(), 'manual'));
    _trim();
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

  /// Replace everything with [texts], in order.
  ///
  /// Used by the admin panel during the closed beta, which hands back the
  /// whole list rather than a diff. Deliberately skips the near-duplicate
  /// check in [addMany]: whoever edited this list meant what they typed, and
  /// silently dropping a line they wrote would look like a failed save.
  Future<void> replaceAll(Iterable<String> texts) async {
    _items
      ..clear()
      ..addAll([
        for (final text in texts)
          if (text.trim().isNotEmpty) MemoryItem.create(text.trim(), 'admin'),
      ]);
    if (_items.length > maxItems) {
      _items.removeRange(0, _items.length - maxItems);
    }
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
  }

  /// The block injected into prompts. Empty string when there's nothing yet,
  /// so callers can append unconditionally.
  ///
  /// The wording matters more than it looks. This used to say "don't bring it
  /// up unprompted, let it inform you naturally", and the model took that at
  /// its word: it asked for names it had been given and offered advice that
  /// contradicted what it had been told. A memory that is optional to use is
  /// one that gets ignored, so these are stated as facts to hold to, and
  /// anything recording how the couple wants to be treated is stated as an
  /// instruction.
  String promptBlock() {
    if (_items.isEmpty) return '';

    String lines(Iterable<MemoryItem> items) =>
        items.map((m) => '- ${m.text}').join('\n');

    final preferences = _items.where((m) => m.isPreference).toList();
    final told =
        _items.where((m) => m.pinned && !m.isPreference).toList();
    final learned =
        _items.where((m) => !m.pinned && !m.isPreference).toList();

    final b = StringBuffer('''

# ============================================================
# WHAT YOU KNOW ABOUT THIS COUPLE
# Everything below is established and current. You are not meeting them for
# the first time.
# ============================================================
''');
    if (told.isNotEmpty) {
      b.writeln('They told you these directly and asked you to remember:');
      b.writeln(lines(told));
      b.writeln();
    }
    if (learned.isNotEmpty) {
      b.writeln('You learned these from earlier conversations:');
      b.writeln(lines(learned));
      b.writeln();
    }
    if (preferences.isNotEmpty) {
      b.writeln('How they have asked you to treat them. These are standing '
          'instructions, not suggestions:');
      b.writeln(lines(preferences));
      b.writeln();
    }
    b.write('''
HOW TO USE THIS
- Hold every line as true. Never contradict one, and never give counsel that
  only makes sense if you had forgotten one.
- Never ask for something already answered here. Use the names, the history
  and the circumstances the way someone who knows them would.
- When what they are asking touches something here, connect it. That is the
  difference between counsel for them and counsel for anyone.
- If they tell you something that changes a line, the new thing is true.
- Do not recite this list, and do not announce that you remember.
''');
    return b.toString();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
