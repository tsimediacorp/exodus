import 'dart:convert';
import '../models/chat_message.dart';
import '../models/coaching_session.dart';
import 'ai_service.dart';
import 'memory_store.dart';

/// Distills durable facts about the couple from a finished conversation and
/// merges them into [MemoryStore]. Runs at the end of a chat or coaching
/// session. Best-effort: any failure is swallowed so it never disrupts the UX.
class MemoryService {
  final AiService _ai = AiService();

  static const _instruction = '''
Review this conversation and extract anything NEW and durable about this couple
worth holding on to for future conversations.

Two kinds of thing:

1. FACTS about their life: names, how long they have been together, children,
   relationship dynamics, recurring struggles, goals, prayer requests,
   milestones, decisions they made.

2. PREFERENCES: anything they asked of YOU. What to call them, how long or
   short to be, a tone they want or do not want, something to stop doing,
   something to always do, a translation they read, a subject to leave alone.
   Start each of these with "Preference: " and write it as an instruction you
   could follow, e.g. "Preference: Keep answers to a few sentences unless
   asked for more." If they said "remember" or "from now on", it belongs
   here or above, always.

Ignore small talk and anything you already know. One short plain-text line
per item.

Return ONLY a JSON array of strings. If there is nothing new, return [].
''';

  /// Whether [message] asks for something to be kept.
  ///
  /// Memory was only ever distilled when a conversation was LEFT. A couple who
  /// said "remember that" and carried on in the same thread, or closed the
  /// app from inside it, never had it saved at all, and found out the next
  /// day. A message that matches this is captured as soon as it is answered.
  static bool asksToRemember(String message) {
    final m = message.toLowerCase();
    return _rememberCues.any((cue) => cue.hasMatch(m));
  }

  static final List<RegExp> _rememberCues = [
    RegExp(r"\bremember\b"),
    RegExp(r"\bdon'?t forget\b"),
    RegExp(r"\bfrom now on\b"),
    RegExp(r"\bgoing forward\b"),
    RegExp(r"\bin (the )?future\b"),
    RegExp(r"\b(always|never)\b.{0,40}\b(call|say|use|quote|give|ask|tell|end|start|mention|bring)\b"),
    RegExp(r"\b(stop|quit)\b.{0,30}\b(calling|saying|using|quoting|giving|asking|telling|ending|starting|mentioning|bringing)\b"),
    RegExp(r"\bcall (me|us|her|him)\b"),
    RegExp(r"\b(i|we) (prefer|would rather|want you to|need you to)\b"),
    RegExp(r"\bkeep (it|your (answers|replies|responses))\b"),
    RegExp(r"\bmy name is\b"),
    RegExp(r"\b(i|we) told you\b"),
  ];

  /// Fire-and-forget capture that owns its own client and closes it when the
  /// request finishes. Use this when the caller is about to be disposed (e.g.
  /// a coaching session popping its route) — an instance owned by that caller
  /// would have its client closed out from under the in-flight request, and
  /// one constructed inline would leak instead.
  static Future<void> captureCoachingDetached(List<CoachingTurn> transcript) async {
    final service = MemoryService();
    try {
      await service.captureFromCoaching(transcript);
    } finally {
      service.dispose();
    }
  }

  Future<void> captureFromChat(List<ChatMessage> conversation) =>
      _capture(conversation, 'chat');

  Future<void> captureFromCoaching(List<CoachingTurn> transcript) {
    final msgs = transcript
        .map((t) => ChatMessage(
              sender: t.speaker == 'exodus' ? Sender.exodus : Sender.user,
              content: t.text,
            ))
        .toList();
    return _capture(msgs, 'coaching');
  }

  Future<void> _capture(List<ChatMessage> conversation, String source) async {
    final meaningful = conversation
        .where((m) => !m.isLoading && m.content.trim().isNotEmpty)
        .toList();
    if (meaningful.length < 2) return; // too short to learn anything
    try {
      final raw = await _ai.ask(
        userMessage: _instruction,
        history: meaningful,
        maxTokens: 1500,
      );
      final facts = _parseFacts(raw);
      if (facts.isNotEmpty) {
        await MemoryStore.instance.addMany(facts, source);
      }
    } catch (_) {
      // Memory capture is best-effort; never surface errors to the user.
    }
  }

  List<String> _parseFacts(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    try {
      final list = jsonDecode(raw.substring(start, end + 1)) as List<dynamic>;
      return list
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() => _ai.dispose();
}
