import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/master_prompt.dart';
import '../models/chat_message.dart';
import '../models/check_in.dart';
import '../models/coaching_session.dart';
import '../models/confession.dart';
import '../models/conversation.dart';
import '../models/devotional.dart';
import '../models/journey.dart';
import '../models/marriage_letter.dart';
import '../models/memory_item.dart';
import '../models/saved_verse.dart';
import '../models/study_exercise.dart';

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
  static const _kMemory            = 'exodus.memory.items';
  static const _kComposerDraft     = 'exodus.composer.draft';
  static const _kReaderFontSize    = 'exodus.reader.fontSize';
  static const _kBiblePaged        = 'exodus.bible.pagedMode';
  static const _kBibleTranslation  = 'exodus.bible.translation';
  static const _kJourneys          = 'exodus.journeys.progress';
  static const _kActionDays        = 'exodus.devotional.actionDays';
  static const _kSavedVerses       = 'exodus.verses.saved';
  static const _kLetters           = 'exodus.letters';
  static const _kCheckIns          = 'exodus.checkIns';
  static const _kCheckInScan       = 'exodus.checkIns.lastScan';
  static const _kCheckInsEnabled   = 'exodus.checkIns.enabled';
  static const _kStudyExercises    = 'exodus.study.exercises';
  // Confessions are stored under their own key and never merged into
  // conversations or memory — see ConfessionService for why that matters.
  static const _kConfessions       = 'exodus.confessions';

  /// Why storage could not be opened, or null when it is working.
  ///
  /// This matters because every write in this class is `_prefs?.setX(...)`:
  /// with no prefs instance those calls are silent no-ops and every read comes
  /// back empty. The app would look exactly as though its history had been
  /// wiped, while cheerfully discarding everything written afterwards. Better
  /// to be able to say so than to pretend.
  String? initError;

  bool get isAvailable => _prefs != null;

  Future<void> init() async {
    // Retry once. SharedPreferences can fail transiently on Android while the
    // platform channel is still coming up, and giving up on the first attempt
    // costs the user everything they write for the rest of the session.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        _prefs = await SharedPreferences.getInstance();
        initError = null;
        break;
      } catch (e) {
        _prefs = null;
        initError = '$e';
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
    }
    if (_prefs == null) return;

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

  // ---------------- Journeys ----------------

  /// Progress for every journey the couple has started, keyed by journey id.
  Map<String, JourneyProgress> loadJourneys() {
    final raw = _prefs?.getString(_kJourneys);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(
          k, JourneyProgress.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  JourneyProgress? journeyProgress(String journeyId) =>
      loadJourneys()[journeyId];

  Future<void> saveJourneyProgress(JourneyProgress progress) async {
    final all = loadJourneys()..[progress.journeyId] = progress;
    await _prefs?.setString(
        _kJourneys, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> deleteJourneyProgress(String journeyId) async {
    final all = loadJourneys()..remove(journeyId);
    await _prefs?.setString(
        _kJourneys, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }

  // ---------------- "Together today" streak ----------------

  /// Day keys (yyyy-mm-dd) on which the couple marked the devotional's
  /// together-action done.
  Set<String> loadActionDays() =>
      (_prefs?.getStringList(_kActionDays) ?? const []).toSet();

  Future<void> setActionDone(String dayKey, bool done) async {
    final all = loadActionDays();
    if (done) {
      all.add(dayKey);
    } else {
      all.remove(dayKey);
    }
    await _prefs?.setStringList(_kActionDays, all.toList()..sort());
  }

  // ---------------- Saved verses ----------------

  List<SavedVerse> loadSavedVerses() {
    final raw = _prefs?.getString(_kSavedVerses);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => SavedVerse.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  bool isVerseSaved(String ref) =>
      loadSavedVerses().any((v) => v.reference == ref);

  Future<void> saveVerse(SavedVerse verse) async {
    final all = loadSavedVerses()
      ..removeWhere((v) => v.reference == verse.reference)
      ..insert(0, verse);
    await _prefs?.setString(
        _kSavedVerses, jsonEncode(all.map((v) => v.toJson()).toList()));
  }

  Future<void> removeVerse(String reference) async {
    final all = loadSavedVerses()..removeWhere((v) => v.reference == reference);
    await _prefs?.setString(
        _kSavedVerses, jsonEncode(all.map((v) => v.toJson()).toList()));
  }

  // ---------------- Weekly letters ----------------

  List<MarriageLetter> loadLetters() {
    final raw = _prefs?.getString(_kLetters);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => MarriageLetter.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.weekStart.compareTo(a.weekStart));
      return list;
    } catch (_) {
      return [];
    }
  }

  MarriageLetter? letterForWeek(DateTime weekStart) {
    final key = MarriageLetter.keyFor(weekStart);
    for (final l in loadLetters()) {
      if (l.weekKey == key) return l;
    }
    return null;
  }

  Future<void> saveLetter(MarriageLetter letter) async {
    final all = loadLetters()
      ..removeWhere((l) => l.weekKey == letter.weekKey)
      ..add(letter);
    all.sort((a, b) => b.weekStart.compareTo(a.weekStart));
    await _prefs?.setString(
        _kLetters, jsonEncode(all.map((l) => l.toJson()).toList()));
  }

  // ---------------- Check-ins ----------------

  List<CheckIn> loadCheckIns() {
    final raw = _prefs?.getString(_kCheckIns);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => CheckIn.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Insert or replace by id.
  Future<void> saveCheckIn(CheckIn checkIn) async {
    final all = loadCheckIns()
      ..removeWhere((c) => c.id == checkIn.id)
      ..add(checkIn);
    await _prefs?.setString(
        _kCheckIns, jsonEncode(all.map((c) => c.toJson()).toList()));
  }

  Future<void> deleteCheckIn(String id) async {
    final all = loadCheckIns()..removeWhere((c) => c.id == id);
    await _prefs?.setString(
        _kCheckIns, jsonEncode(all.map((c) => c.toJson()).toList()));
  }

  /// Whether EXODUS may follow up unprompted. On by default, but this reads
  /// the couple's history to decide what to raise, so it must be refusable.
  bool loadCheckInsEnabled() => _prefs?.getBool(_kCheckInsEnabled) ?? true;

  Future<void> saveCheckInsEnabled(bool enabled) async =>
      _prefs?.setBool(_kCheckInsEnabled, enabled);

  DateTime? loadLastCheckInScan() {
    final raw = _prefs?.getString(_kCheckInScan);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> saveLastCheckInScan(DateTime when) async =>
      _prefs?.setString(_kCheckInScan, when.toIso8601String());

  // ---------------- Composer draft ----------------

  /// Unsent composer text, so a force-quit mid-compose doesn't lose it.
  String loadComposerDraft() => _prefs?.getString(_kComposerDraft) ?? '';

  Future<void> saveComposerDraft(String text) async {
    if (text.isEmpty) {
      await _prefs?.remove(_kComposerDraft);
    } else {
      await _prefs?.setString(_kComposerDraft, text);
    }
  }

  // ---------------- Reader ----------------

  /// Reader font size, so it survives closing the reader.
  double? loadReaderFontSize() => _prefs?.getDouble(_kReaderFontSize);

  Future<void> saveReaderFontSize(double size) async =>
      _prefs?.setDouble(_kReaderFontSize, size);

  // ---------------- Bible ----------------

  /// Whether the Bible reader turns pages (true, the default) or scrolls.
  bool loadBiblePagedMode() => _prefs?.getBool(_kBiblePaged) ?? true;

  Future<void> saveBiblePagedMode(bool paged) async =>
      _prefs?.setBool(_kBiblePaged, paged);

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

  // ---------------- Bible translation ----------------

  /// The translation id last chosen, or null on a device that has never
  /// picked. BibleService resolves an unknown id back to the default, so a
  /// translation that is later removed from the bundle does not strand anyone.
  String? loadBibleTranslation() => _prefs?.getString(_kBibleTranslation);

  Future<void> saveBibleTranslation(String id) async {
    await _prefs?.setString(_kBibleTranslation, id);
  }

  // ---------------- Bible study exercises ----------------

  /// All saved exercises, newest day first.
  List<StudyExercise> loadStudyExercises() {
    final raw = _prefs?.getString(_kStudyExercises);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => StudyExercise.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.day.compareTo(a.day));
      return list;
    } catch (_) {
      return [];
    }
  }

  StudyExercise? studyExerciseForDay(DateTime day) {
    final key = StudyExercise.keyFor(day);
    for (final e in loadStudyExercises()) {
      if (e.dayKey == key) return e;
    }
    return null;
  }

  /// Insert or replace the exercise for its day.
  Future<void> saveStudyExercise(StudyExercise exercise) async {
    final all = loadStudyExercises()
      ..removeWhere((e) => e.dayKey == exercise.dayKey)
      ..add(exercise);
    all.sort((a, b) => b.day.compareTo(a.day));
    await _prefs?.setString(
        _kStudyExercises, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  // ---------------- Confessions ----------------

  /// Everything confessed on this device, newest first. Deliberately separate
  /// from conversations and from memory.
  List<Confession> loadConfessions() {
    final raw = _prefs?.getString(_kConfessions);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Confession.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConfession(Confession confession) async {
    final all = loadConfessions()
      ..removeWhere((c) => c.id == confession.id)
      ..add(confession);
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _prefs?.setString(
        _kConfessions, jsonEncode(all.map((c) => c.toJson()).toList()));
  }

  Future<void> deleteConfession(String id) async {
    final all = loadConfessions()..removeWhere((c) => c.id == id);
    await _prefs?.setString(
        _kConfessions, jsonEncode(all.map((c) => c.toJson()).toList()));
  }

  /// Remove every confession. Uses remove() rather than writing an empty list
  /// so nothing is left behind in the prefs file at all.
  Future<void> clearConfessions() async {
    await _prefs?.remove(_kConfessions);
  }

  // ---------------- Memory ----------------

  List<MemoryItem> loadMemory() {
    final raw = _prefs?.getString(_kMemory);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => MemoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMemory(List<MemoryItem> items) async {
    await _prefs?.setString(
        _kMemory, jsonEncode(items.map((m) => m.toJson()).toList()));
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
