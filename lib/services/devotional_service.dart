import 'dart:convert';
import '../config/devotional_prompt.dart';
import '../models/chat_message.dart';
import '../models/devotional.dart';
import 'ai_service.dart';

/// Generates daily devotionals. Routes through [AiService], so the system
/// prompt is always `MasterPrompt.build()` — the devotional is EXODUS, grounded
/// in the same source of truth as everything else.
class DevotionalService {
  final AiService _ai = AiService();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _dateLabel(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Generate the devotional for [forDay] (default today) tied to [goal].
  /// Uses a generous token budget: glm-4.6v is a reasoning model, so it spends
  /// tokens "thinking" before the JSON — too small a cap yields empty content.
  Future<Devotional> generate({
    required String goal,
    DateTime? forDay,
    List<String> recentRefs = const [],
  }) async {
    final day = forDay ?? DateTime.now();
    final raw = await _ai.ask(
      userMessage: DevotionalPrompt.task(
          goal: goal, dateLabel: _dateLabel(day), recentRefs: recentRefs),
      history: const <ChatMessage>[],
      maxTokens: 4000,
    );
    if (raw.trim().isEmpty) {
      throw Exception(
          "EXODUS couldn't finish today's devotional (the model hit its limit). Tap Try again.");
    }
    return Devotional.fromGenerated(day: day, json: _extractJson(raw), goal: goal);
  }

  /// Distill a free-form goal-setting conversation into one clear goal line.
  Future<String> summarizeGoal(List<ChatMessage> conversation) async {
    final line = await _ai.ask(
      userMessage: DevotionalPrompt.goalSummaryTask(),
      history: conversation,
      maxTokens: 1500,
    );
    return line.trim().replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
  }

  /// Pull the devotional fields out of a model reply, tolerating stray text or
  /// code fences. If strict JSON parsing fails (e.g. an unescaped quote inside
  /// a value), fall back to per-field regex extraction so the devotional still
  /// renders cleanly instead of dumping raw text into the reflection.
  Map<String, dynamic> _extractJson(String s) {
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
      } catch (_) {/* fall through to field extraction */}
    }
    const keys = [
      'title', 'scriptureRef', 'scriptureText', 'reflection', 'prayer', 'action'
    ];
    final fields = <String, dynamic>{};
    for (final key in keys) {
      final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(s);
      if (m != null) {
        fields[key] = m
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .trim();
      }
    }
    return fields.isNotEmpty ? fields : {'reflection': s.trim()};
  }

  void dispose() => _ai.dispose();
}
