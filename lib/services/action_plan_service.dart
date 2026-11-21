import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/action_plan_prompt.dart';
import '../models/action_plan.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'ai_service.dart';
import 'follow_ups.dart';
import 'key_scripture.dart';
import 'notification_service.dart';
import 'progress.dart';
import 'storage_service.dart';

/// Active Steps: writing, keeping and following through on plans.
class ActionPlanService extends ChangeNotifier {
  ActionPlanService._();
  static final ActionPlanService instance = ActionPlanService._();

  /// Injectable for tests.
  @visibleForTesting
  Future<String> Function(String prompt, ProgressController? status)? askOverride;

  final StorageService _storage = StorageService.instance;

  List<ActionPlan>? _cache;

  List<ActionPlan> get all {
    if (_cache != null) return _cache!;
    final raw = _storage.loadActionPlansRaw();
    if (raw == null || raw.isEmpty) return _cache = [];
    try {
      return _cache = (jsonDecode(raw) as List<dynamic>)
          .map((e) => ActionPlan.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _cache = [];
    }
  }

  /// Plans still running, most recent first.
  List<ActionPlan> get active =>
      all.where((p) => p.isActive).toList().reversed.toList();

  ActionPlan? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  ActionPlan? forConversation(String? conversationId) {
    if (conversationId == null) return null;
    for (final p in all.reversed) {
      if (p.conversationId == conversationId) return p;
    }
    return null;
  }

  /// Drop the in-memory copy, e.g. after storage was reset in a test.
  @visibleForTesting
  void reset() {
    _cache = null;
    askOverride = null;
  }

  Future<void> _save() async {
    await _storage
        .saveActionPlansRaw(jsonEncode(all.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  // ---------------- The offer ----------------

  static final RegExp _offer =
      RegExp(r'\[\[\s*PLAN\s*\]\]', caseSensitive: false);
  static final RegExp _danglingOffer =
      RegExp(r'\[\[\s*P?L?A?N?\s*$', caseSensitive: false);

  /// Whether EXODUS offered a plan at the end of [content].
  static bool offers(String content) => _offer.hasMatch(content);

  /// The reply without the marker.
  static String strip(String content) => content
      .replaceAll(_offer, '')
      .replaceAll(_danglingOffer, '')
      .trimRight();

  // ---------------- Writing a plan ----------------

  /// Why the last [create] failed, or null.
  String? lastError;

  /// Write a plan from [conversation]. Returns null on failure, with
  /// [lastError] set; never throws.
  Future<ActionPlan?> create({
    required Conversation conversation,
    required PlanLength length,
    ProgressController? status,
  }) async {
    lastError = null;
    final prompt = ActionPlanPrompt.generate(
      length: length,
      transcript: transcriptOf(conversation.messages),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = askOverride != null
            ? await askOverride!(prompt, status)
            : await _ask(prompt, status, length);
        final plan = parse(raw,
            length: length, conversationId: conversation.id);
        if (plan == null) continue;
        all.add(plan);
        await _save();
        unawaited(_scheduleReminders());
        return plan;
      } catch (e) {
        lastError = 'Could not write the plan. Check your connection and '
            'try again.';
      }
    }
    lastError ??= 'The plan came back incomplete. Try again.';
    return null;
  }

  Future<String> _ask(
      String prompt, ProgressController? status, PlanLength length) {
    final ai = AiService();
    return ai
        .ask(
          userMessage: prompt,
          history: const <ChatMessage>[],
          maxTokens: length.days >= 30 ? 6000 : 2500,
          timeout: const Duration(seconds: 75),
          progress: status,
          workingMessage: 'Writing your ${length.label} plan…',
        )
        .whenComplete(ai.dispose);
  }

  /// The conversation as plain text for the prompt: the last thirty turns,
  /// markers removed, so the plan is about what was actually said.
  static String transcriptOf(List<ChatMessage> messages) {
    final recent = messages.length > 30
        ? messages.sublist(messages.length - 30)
        : messages;
    return recent
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) {
          final who = m.sender == Sender.user ? 'COUPLE' : 'EXODUS';
          final text = strip(KeyScripture.strip(FollowUps.strip(m.content)));
          return '$who: ${text.trim()}';
        })
        .join('\n\n');
  }

  /// Parse the model's JSON into a plan. Lenient about fences and stray
  /// prose; strict about having one usable step per day.
  @visibleForTesting
  static ActionPlan? parse(String raw,
      {required PlanLength length, String? conversationId}) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final rawSteps = json['steps'];
    if (rawSteps is! List) return null;
    final steps = <PlanStep>[];
    for (final s in rawSteps) {
      if (s is! Map) continue;
      final title = (s['title'] ?? '').toString().trim();
      final action = (s['action'] ?? '').toString().trim();
      if (title.isEmpty && action.isEmpty) continue;
      steps.add(PlanStep(
        day: steps.length + 1,
        title: title.isEmpty ? 'Day ${steps.length + 1}' : title,
        action: action,
        scripture: (s['scripture'] ?? '').toString().trim(),
      ));
      if (steps.length == length.days) break;
    }
    // A plan short by more than a day or two is not the plan they asked
    // for; better to retry than to hand them a week that is four days long.
    if (steps.length < length.days - (length.days >= 30 ? 2 : 0)) return null;
    final title = (json['title'] ?? '').toString().trim();
    final goal = (json['goal'] ?? '').toString().trim();
    return ActionPlan(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      conversationId: conversationId,
      title: title.isEmpty ? 'Your ${length.label} plan' : title,
      goal: goal,
      steps: steps,
    );
  }

  // ---------------- Following through ----------------

  Future<void> toggleStep(ActionPlan plan, PlanStep step) async {
    step.doneAt = step.done ? null : DateTime.now();
    await _save();
    unawaited(_scheduleReminders());
  }

  Future<void> end(ActionPlan plan) async {
    plan.endedAt = DateTime.now();
    await _save();
    unawaited(_scheduleReminders());
  }

  /// Context for Counsel while a plan is running.
  String counselLayer(DateTime now) {
    final running = active;
    if (running.isEmpty) return '';
    return ActionPlanPrompt.activeLayer(running.first, now);
  }

  /// Keep the reminder window current. Called on launch too.
  Future<void> refreshReminders() => _scheduleReminders();

  Future<void> _scheduleReminders() async {
    try {
      final running = active;
      if (running.isEmpty) {
        await NotificationService.instance.cancelStepReminders();
        return;
      }
      final plan = running.first;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final pending = plan.steps.where((s) => !s.done).toList();
      // Pending steps land one per day from tomorrow (today's is already
      // in front of them), so falling behind shifts reminders rather than
      // nagging about a day that has passed.
      final upcoming = [
        for (var i = 0; i < pending.length; i++)
          (
            day: pending[i].day,
            title: pending[i].title,
            date: today.add(Duration(days: i + 1)),
          ),
      ];
      await NotificationService.instance.scheduleStepReminders(
        planId: plan.id,
        planTitle: plan.title,
        upcoming: upcoming,
      );
    } catch (_) {/* reminders are best-effort */}
  }
}
