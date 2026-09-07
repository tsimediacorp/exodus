import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/community_fallback.dart';
import '../config/community_prompt.dart';
import '../models/chat_message.dart';
import '../models/community_post.dart';
import 'ai_service.dart';
import 'memory_store.dart';
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
/// Posts are written by EXODUS, and every one carries [CommunityPost.composite]
/// so the UI can say so. See [CommunityPrompt.compositeNotice].
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

  /// Seed on first run, then top up once a day.
  ///
  /// Safe to call on every home-screen build: it returns immediately when
  /// today's posts already exist, and only one generation runs at a time.
  Future<void> ensureFresh() async {
    load();
    if (_working) return;

    final storage = StorageService.instance;
    final today = _dayStamp(DateTime.now());
    if (_posts.isNotEmpty && storage.communityLastDay == today) return;

    _working = true;
    lastError = null;
    notifyListeners();
    try {
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
