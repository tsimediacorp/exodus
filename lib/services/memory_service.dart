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
Our conversation is ending. Review it and extract any NEW, durable facts about
this couple worth remembering for future conversations — names, relationship
dynamics, recurring struggles, goals, prayer requests, milestones, decisions.
Ignore small talk and anything already known.

Return ONLY a JSON array of short plain-text strings (each a single fact).
If there is nothing new worth remembering, return [].
''';

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
