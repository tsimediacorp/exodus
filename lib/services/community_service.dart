import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/community_fallback.dart';
import '../config/community_prompt.dart';
import '../models/chat_message.dart';
import '../models/community_post.dart';
import 'package:http/http.dart' as http;

import 'ai_service.dart';
import '../config/build_info.dart';
import 'memory_store.dart';
import 'remote_config.dart';
import 'storage_service.dart';

/// The community feed: stories tailored to what this couple is actually
/// carrying.
///
/// Generated ON DEVICE from [MemoryStore] and kept there. Nothing about the
/// couple's struggles is stored anywhere but their phone, and no post is ever
/// sent anywhere — the feed is private to them even though it reads as a
/// group. That is a deliberate constraint, not an implementation detail: the
/// whole premise is that they can be honest here.
///
/// Posts are written by EXODUS. Nothing in the UI says so — that is a
/// deliberate pre-launch decision — but every post still carries
/// [CommunityPost.composite], which is what makes it possible to find and
/// clear the generated ones once real members start posting.
class CommunityService extends ChangeNotifier {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  final AiService _ai = AiService();

  /// How many to write the first time, and how many to add each day after.
  static const int seedCount = 5;
  static const int dailyCount = 3;

  /// Ceiling on what we keep. Enough to scroll for a while, bounded so the
  /// feed cannot grow without limit on a device.
  static const int maxPosts = 60;

  List<CommunityPost> _posts = [];
  bool _loaded = false;
  bool _working = false;

  /// Why the last refresh produced nothing new, or null. [ensureFresh] never
  /// throws, so this is how the UI learns the feed is stale rather than quiet.
  String? lastError;

  List<CommunityPost> get posts => List.unmodifiable(_posts);
  bool get isWorking => _working;
  bool get isEmpty => _posts.isEmpty;
  int get unreadCount => _posts.where((p) => !p.read).length;

  void load() {
    if (_loaded) return;
    _posts = StorageService.instance.loadCommunityPosts();
    _loaded = true;
  }

  /// Pull the stories written in the admin panel.
  ///
  /// The whole set replaces the previous one rather than merging, which is
  /// what makes an edit or a delete in the panel actually take effect: a merge
  /// would leave a deleted story on every device that had already seen it,
  /// with no way to get it off.
  ///
  /// Generated posts are untouched. Returns whether anything changed.
  Future<bool> _syncCurated() async {
    if (kAdminBaseUrl.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse('$kAdminBaseUrl/api/v1/stories'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final raw = (decoded['stories'] as List<dynamic>?) ?? const [];

      final curated = <CommunityPost>[];
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final id = entry['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final post = CommunityPost.fromGenerated(
          entry,
          id: id,
          createdAt: DateTime.tryParse(entry['publishedAt'] as String? ?? '') ??
              DateTime.now(),
        );
        // A curated story is shown as written. The usable check exists to
        // catch a model producing junk, not to overrule someone who typed it.
        if (post.title.isNotEmpty && post.body.isNotEmpty) curated.add(post);
      }

      final wasRead = {
        for (final p in _posts)
          if (p.curated && p.read) p.id,
      };
      for (final post in curated) {
        post.read = wasRead.contains(post.id);
      }

      _posts = [..._posts.where((p) => !p.curated), ...curated];
      _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await StorageService.instance.saveCommunityPosts(_posts);
      return true;
    } catch (_) {
      // Panel down or no network. The stories already on the device stand.
      return false;
    }
  }

  /// Seed on first run, then top up once a day.
  ///
  /// Safe to call on every home-screen build: it returns immediately when
  /// today's posts already exist, and only one generation runs at a time.
  Future<void> ensureFresh({bool force = false}) async {
    load();
    if (_working) return;

    final storage = StorageService.instance;
    final today = _dayStamp(DateTime.now());
    final alreadyToday = _posts.isNotEmpty && storage.communityLastDay == today;

    _working = true;
    if (force) lastError = null;
    notifyListeners();
    try {
      // Curated stories are checked on every launch, not once a day: an edit
      // in the panel should reach a demo phone in seconds, not tomorrow.
      final curatedChanged = await _syncCurated();
      if (curatedChanged) notifyListeners();

      // With curated-only on, the panel is the whole feed and generating would
      // put stories on the device that nobody chose.
      if (RemoteConfig.instance.flag('communityCuratedOnly')) return;
      if (alreadyToday && !force) return;

      lastError = null;
      final fresh = await _generate(_posts.isEmpty ? seedCount : dailyCount);
      if (fresh.isNotEmpty) {
        _merge(fresh);
        await storage.saveCommunityPosts(_posts);
        await storage.setCommunityLastDay(today);
      } else if (_posts.isEmpty) {
        // First run with no network: better a real feed of general stories
        // than an empty panel where the couple was promised company. Not
        // stamped with today, so a later launch still tries for tailored ones.
        _merge(_fallbackPosts());
        await storage.saveCommunityPosts(_posts);
      }
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  /// Mark a thread read. Cheap and local; drives the unread dot only.
  Future<void> markRead(String id) async {
    load();
    final post = _posts.firstWhere((p) => p.id == id,
        orElse: () => throw StateError('no post $id'));
    if (post.read) return;
    post.read = true;
    await StorageService.instance.saveCommunityPosts(_posts);
    notifyListeners();
  }

  /// Throw away everything and rebuild from scratch. Used by Settings, and
  /// after the couple edits their memory — the feed should follow.
  Future<void> reset() async {
    load();
    _posts = [];
    await StorageService.instance.saveCommunityPosts(_posts);
    await StorageService.instance.setCommunityLastDay('');
    notifyListeners();
    await ensureFresh();
  }

  // ----------------------------------------------------------

  void _merge(List<CommunityPost> fresh) {
    // Newest first, and never past the cap.
    _posts = [...fresh, ..._posts];
    _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_posts.length > maxPosts) _posts = _posts.sublist(0, maxPosts);
  }

  /// Days since a fixed epoch. Only used to rotate the subjects, so it must
  /// advance by exactly one a day and never depend on the time of day.
  static int _dayIndex(DateTime d) =>
      DateTime(d.year, d.month, d.day).difference(DateTime(2000)).inDays;

  static String _dayStamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<CommunityPost> _fallbackPosts() {
    final now = DateTime.now();
    return [
      for (var i = 0; i < CommunityFallback.posts.length; i++)
        CommunityPost.fromGenerated(
          Map<String, dynamic>.from(CommunityFallback.posts[i]),
          id: 'fallback-$i',
          createdAt: now.subtract(Duration(hours: 3 + i * 9)),
        ),
    ];
  }

  /// Ask for [count] posts. Returns empty rather than throwing.
  Future<List<CommunityPost>> _generate(int count) async {
    const maxAttempts = 2;
    Object? lastFailure;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final raw = await _ai.ask(
          userMessage: CommunityPrompt.task(
            memoryBlock: MemoryStore.instance.promptBlock(),
            count: count,
            // Rotates the subjects so today's batch cannot repeat yesterday's.
            dayIndex: _dayIndex(DateTime.now()),
            recentTitles: _posts.take(12).map((p) => p.title).toList(),
            recentAuthors: _posts.take(12).map((p) => p.author).toList(),
            recentTags: _posts.take(8).map((p) => p.tag).toList(),
          ),
          history: const <ChatMessage>[],
          // Several full threads in one response. Too small a cap truncates
          // mid-array and the whole batch parses to nothing.
          maxTokens: 6000,
          timeout: const Duration(seconds: 60),
          workingMessage: 'Finding people who have been here…',
        );

        final posts = _parse(raw);
        if (posts.isNotEmpty) return posts;
        lastFailure = 'The model returned no usable posts.';
      } catch (e) {
        lastFailure = e;
        // A missing or rejected key will not fix itself in 600ms. Retrying it
        // costs a second attempt and leaves a timer running after whoever
        // asked has moved on, which is how this leaked into the home screen.
        if (!_isWorthRetrying(e)) break;
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    lastError = _friendlyError(lastFailure);
    return const [];
  }

  /// Exposed so the batch rules can be exercised without a model: dropping
  /// one malformed thread while keeping the good ones is the behaviour that
  /// decides whether a bad night leaves the couple with a feed or a blank.
  @visibleForTesting
  List<CommunityPost> parseBatch(String raw) => _parse(raw);

  /// Pull posts out of whatever came back.
  ///
  /// Per-element rather than all-or-nothing: models routinely produce four
  /// good threads and one malformed, and dropping the good four over the bad
  /// one leaves the couple with an empty feed for the day.
  List<CommunityPost> _parse(String raw) {
    final decoded = _extractArray(raw);
    final now = DateTime.now();
    final out = <CommunityPost>[];

    for (var i = 0; i < decoded.length; i++) {
      try {
        final post = CommunityPost.fromGenerated(
          decoded[i],
          id: '${now.microsecondsSinceEpoch.toRadixString(36)}-$i',
          // Spread back through the day so the feed reads as something that
          // happened while they were away, not a batch stamped 9:04am.
          createdAt: now.subtract(Duration(minutes: 37 + i * 143)),
        );
        if (post.isUsable) out.add(post);
      } catch (_) {
        // One bad element does not spoil the batch.
      }
    }
    return out;
  }

  /// The JSON array in [s], or empty.
  ///
  /// Tolerates a markdown fence and any preamble the model adds despite being
  /// told not to, by scanning to the outermost brackets.
  List<Map<String, dynamic>> _extractArray(String s) {
    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      return (jsonDecode(s.substring(start, end + 1)) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Whether a second attempt could plausibly do better.
  ///
  /// Timeouts, dropped sockets and rate limits are worth another try. A
  /// missing or rejected API key is a configuration problem, and hammering it
  /// only delays the fallback the couple is waiting on.
  static bool _isWorthRetrying(Object? e) {
    final s = e.toString();
    if (s.contains('No API key configured')) return false;
    if (s.contains('(401)') || s.contains('(403)')) return false;
    // dotenv throws NotInitializedError when the .env was never loaded, and
    // its toString carries no message — so this has to match on the type.
    // That is the shape of the failure in tests and in any build shipped
    // without an .env, and neither improves on a second attempt.
    if (e.runtimeType.toString().contains('NotInitialized')) return false;
    return true;
  }

  static String _friendlyError(Object? e) {
    if (e == null) return 'Could not reach EXODUS.';
    final s = e.toString();
    if (e is TimeoutException || s.contains('TimeoutException')) {
      return 'The connection timed out.';
    }
    if (e is SocketException || s.contains('SocketException')) {
      return 'No internet connection.';
    }
    if (s.contains('(401)') || s.contains('(403)')) {
      return 'The API key was rejected. Check Settings.';
    }
    if (s.contains('(429)')) return 'Rate limited — try again in a moment.';
    return s.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _ai.dispose();
    super.dispose();
  }
}
