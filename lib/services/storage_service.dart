import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/master_prompt.dart';
import '../models/chat_message.dart';
import '../models/coaching_session.dart';
import '../models/conversation.dart';
import '../models/devotional.dart';

/// Persists conversations and MasterPrompt runtime overrides to
/// shared_preferences (which on iOS is NSUserDefaults — local to the app,
/// not iCloud-synced). Call `init()` once at app startup; after that all
/// reads are synchronous against the cached SharedPreferences instance.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  SharedPreferences? _prefs;

  // Keys
  static const _kConversations     = 'exodus.conversations';
  static const _kCurrentConvId     = 'exodus.currentConversationId';
  static const _kLegacyMessages    = 'exodus.messages'; // pre-multi-thread
  static const _kIdentity          = 'exodus.prompt.identity';
  static const _kDoctrine          = 'exodus.prompt.doctrine';
  static const _kAudience          = 'exodus.prompt.audience';
  static const _kStyle             = 'exodus.prompt.style';
  static const _kGuardrails        = 'exodus.prompt.guardrails';
  static const _kSignature         = 'exodus.prompt.signature';
  static const _kTemperature       = 'exodus.model.temperature';
  static const _kMaxTokens         = 'exodus.model.maxTokens';
  static const _kActiveProvider    = 'exodus.model.activeProvider';
  static const _kCoachingSessions  = 'exodus.coachingSessions';
  static const _kDevotionalGoal    = 'exodus.devotional.goal';
  static const _kDevotionals       = 'exodus.devotional.entries';

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
      return;
    }

    final p = _prefs;
    if (p == null) return;

    MasterPrompt.identityOverride       = p.getString(_kIdentity);
    MasterPrompt.doctrineOverride       = p.getString(_kDoctrine);
    MasterPrompt.audienceOverride       = p.getString(_kAudience);
    MasterPrompt.styleOverride          = p.getString(_kStyle);
    MasterPrompt.guardrailsOverride     = p.getString(_kGuardrails);
    MasterPrompt.signatureOverride      = p.getString(_kSignature);
    MasterPrompt.temperatureOverride    = p.getDouble(_kTemperature);
    MasterPrompt.maxTokensOverride      = p.getInt(_kMaxTokens);
    MasterPrompt.activeProviderOverride = p.getString(_kActiveProvider);

    await _migrateLegacyMessagesIfPresent();
  }

  /// One-time migration: if the user upgraded from the single-thread version,
  /// fold those messages into a new Conversation so they don't disappear.
  Future<void> _migrateLegacyMessagesIfPresent() async {
    final p = _prefs;
    if (p == null) return;
    final legacy = p.getString(_kLegacyMessages);
    if (legacy == null || legacy.isEmpty) return;
    if (p.getString(_kConversations) != null) {
      await p.remove(_kLegacyMessages);
      return;
    }
    try {
      final list = jsonDecode(legacy) as List<dynamic>;
      final messages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      if (messages.isNotEmpty) {
        final conv = Conversation.empty()..messages.addAll(messages);
        conv.deriveTitleFromFirstUserMessage();
        await saveConversations([conv]);
        await setCurrentConversationId(conv.id);
      }
    } catch (_) {
      // Ignore malformed legacy data.
    }
    await p.remove(_kLegacyMessages);
  }

  // ---------------- Conversations ----------------

  List<Conversation> loadConversations() {
    final p = _prefs;
    if (p == null) return [];
    final raw = p.getString(_kConversations);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    final p = _prefs;
    if (p == null) return;
    final encoded =
        jsonEncode(conversations.map((c) => c.toJson()).toList());
    await p.setString(_kConversations, encoded);
  }

  String? getCurrentConversationId() => _prefs?.getString(_kCurrentConvId);

  Future<void> setCurrentConversationId(String? id) async {
    final p = _prefs;
    if (p == null) return;
    if (id == null) {
      await p.remove(_kCurrentConvId);
    } else {
      await p.setString(_kCurrentConvId, id);
    }
  }

  // ---------------- Coaching sessions ----------------

  List<CoachingSession> loadCoachingSessions() {
    final p = _prefs;
    if (p == null) return [];
    final raw = p.getString(_kCoachingSessions);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => CoachingSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCoachingSessions(List<CoachingSession> sessions) async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(
        _kCoachingSessions, jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }

  /// Append a finished session to history (newest first).
  Future<void> addCoachingSession(CoachingSession session) async {
    final all = loadCoachingSessions()..insert(0, session);
    await saveCoachingSessions(all);
  }

  // ---------------- Devotionals ----------------

  DevotionalGoal? loadDevotionalGoal() {
    final raw = _prefs?.getString(_kDevotionalGoal);
    if (raw == null || raw.isEmpty) return null;
    try {
      return DevotionalGoal.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDevotionalGoal(DevotionalGoal goal) async {
    await _prefs?.setString(_kDevotionalGoal, jsonEncode(goal.toJson()));
  }

  /// All saved devotionals, newest day first.
  List<Devotional> loadDevotionals() {
    final raw = _prefs?.getString(_kDevotionals);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Devotional.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.day.compareTo(a.day));
      return list;
    } catch (_) {
      return [];
    }
  }

  Devotional? devotionalForDay(DateTime day) {
    final key = Devotional.keyFor(day);
    for (final d in loadDevotionals()) {
      if (d.dayKey == key) return d;
    }
    return null;
  }

  /// Insert or replace the devotional for its day.
  Future<void> saveDevotional(Devotional devotional) async {
    final all = loadDevotionals()
      ..removeWhere((d) => d.dayKey == devotional.dayKey)
      ..add(devotional);
    all.sort((a, b) => b.day.compareTo(a.day));
    await _prefs?.setString(
        _kDevotionals, jsonEncode(all.map((d) => d.toJson()).toList()));
  }

  // ---------------- Prompt overrides ----------------

  Future<void> setPromptSection(String section, String? value) async {
    final key = switch (section) {
      'identity'   => _kIdentity,
      'doctrine'   => _kDoctrine,
      'audience'   => _kAudience,
      'style'      => _kStyle,
      'guardrails' => _kGuardrails,
      'signature'  => _kSignature,
      _ => throw ArgumentError('Unknown section: $section'),
    };
    final p = _prefs;
    if (p != null) {
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, value);
      }
    }
    _applyOverrideInMemory(section, value);
  }

  void _applyOverrideInMemory(String section, String? value) {
    switch (section) {
      case 'identity':   MasterPrompt.identityOverride   = value; break;
      case 'doctrine':   MasterPrompt.doctrineOverride   = value; break;
      case 'audience':   MasterPrompt.audienceOverride   = value; break;
      case 'style':      MasterPrompt.styleOverride      = value; break;
      case 'guardrails': MasterPrompt.guardrailsOverride = value; break;
      case 'signature':  MasterPrompt.signatureOverride  = value; break;
    }
  }

  Future<void> setTemperature(double? value) async {
    final p = _prefs;
    if (p != null) {
      if (value == null) {
        await p.remove(_kTemperature);
      } else {
        await p.setDouble(_kTemperature, value);
      }
    }
    MasterPrompt.temperatureOverride = value;
  }

  Future<void> setMaxTokens(int? value) async {
    final p = _prefs;
    if (p != null) {
      if (value == null) {
        await p.remove(_kMaxTokens);
      } else {
        await p.setInt(_kMaxTokens, value);
      }
    }
    MasterPrompt.maxTokensOverride = value;
  }

  Future<void> setActiveProvider(String? value) async {
    final p = _prefs;
    if (p != null) {
      if (value == null) {
        await p.remove(_kActiveProvider);
      } else {
        await p.setString(_kActiveProvider, value);
      }
    }
    MasterPrompt.activeProviderOverride = value;
  }

  Future<void> resetAllOverrides() async {
    final p = _prefs;
    if (p != null) {
      for (final k in [
        _kIdentity, _kDoctrine, _kAudience, _kStyle, _kGuardrails, _kSignature,
        _kTemperature, _kMaxTokens, _kActiveProvider,
      ]) {
        await p.remove(k);
      }
    }
    MasterPrompt.identityOverride = null;
    MasterPrompt.doctrineOverride = null;
    MasterPrompt.audienceOverride = null;
    MasterPrompt.styleOverride = null;
    MasterPrompt.guardrailsOverride = null;
    MasterPrompt.signatureOverride = null;
    MasterPrompt.temperatureOverride = null;
    MasterPrompt.maxTokensOverride = null;
    MasterPrompt.activeProviderOverride = null;
  }
}
