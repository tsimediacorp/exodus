import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_info.dart';
import '../models/chat_message.dart';
import 'memory_store.dart';
import 'storage_service.dart';

/// Hands this device's local state to the admin panel, and applies whatever
/// the panel is waiting to do.
///
/// BETA SCAFFOLDING, AND THE MOST SENSITIVE CODE IN THE APP. Counsel
/// conversations and memory are the most private material EXODUS holds and
/// normally never leave the phone. This exists so a closed beta can be
/// debugged and is meant to be deleted at launch, along with the panel.
///
/// Two things it deliberately does NOT do:
///
///  * Confessions are never synced. That tab was built and described to users
///    as never leaving the device, its debugging value is low, and the cost of
///    breaking that promise is the feature itself.
///  * Nothing is uploaded when there is no admin URL compiled in. A release
///    built without --dart-define=EXODUS_ADMIN_URL sends nothing anywhere,
///    which is what a launch build should be.
class DebugSync {
  DebugSync._();
  static final DebugSync instance = DebugSync._();

  static const _kDeviceId = 'exodus.push.deviceId';

  /// Keeps a snapshot small enough for one request. Redis and the panel both
  /// have limits, and a couple six months in could otherwise carry megabytes
  /// of transcript on a phone connection.
  static const int _maxConversations = 20;
  static const int _maxMessagesPerConversation = 80;
  static const int _maxMessageChars = 4000;
  static const int _byteBudget = 400 * 1024;

  bool get isEnabled => kAdminBaseUrl.isNotEmpty;

  /// Upload, then apply anything the panel queued. Never throws.
  Future<void> run({String? userId}) async {
    if (!isEnabled) return;
    try {
      final deviceId = await _deviceId();
      if (deviceId.isEmpty) return;

      final snapshot = _snapshot(deviceId: deviceId, userId: userId);
      final response = await http
          .post(
            Uri.parse('$kAdminBaseUrl/api/v1/sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(snapshot),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return;
      await _apply(deviceId, (body['commands'] as List<dynamic>?) ?? const []);
    } catch (_) {
      // Offline, panel down, malformed reply. Nothing about the app changes.
    }
  }

  /// Pull and apply without uploading. Used when a push wakes the app: the
  /// message the couple was just told about should be there when they arrive,
  /// and a full upload would make that wait on their whole history.
  Future<void> drain() async {
    if (!isEnabled) return;
    try {
      final deviceId = await _deviceId();
      if (deviceId.isEmpty) return;
      final response = await http
          .get(Uri.parse('$kAdminBaseUrl/api/v1/outbox?deviceId=$deviceId'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return;
      await _apply(deviceId, (body['commands'] as List<dynamic>?) ?? const []);
    } catch (_) {
      // Same as above.
    }
  }

  Future<String> _deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kDeviceId) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Exposed so the trimming rules can be checked without a network: what
  /// this leaves out is the difference between a debuggable beta and a
  /// snapshot the panel rejects whole.
  @visibleForTesting
  Map<String, dynamic> snapshotForTest({required String deviceId}) =>
      _snapshot(deviceId: deviceId);

  /// Exposed so command handling can be checked without a panel. Applying one
  /// wrongly writes to a couple's real conversation, so it is worth pinning.
  @visibleForTesting
  Future<void> applyForTest(List<dynamic> commands) => _apply('', commands);

  Map<String, dynamic> _snapshot({
    required String deviceId,
    String? userId,
  }) {
    final storage = StorageService.instance;
    final all = storage.loadConversations()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    var dropped = 0;
    final kept = <Map<String, dynamic>>[];
    var bytes = 0;

    for (final conversation in all.take(_maxConversations)) {
      // Newest messages matter most for debugging, but a thread reads
      // forwards, so take the tail and keep it in order.
      final messages = conversation.messages
          .where((m) => !m.isLoading && m.content.trim().isNotEmpty)
          .toList();
      final trimmed = messages.length > _maxMessagesPerConversation
          ? messages.sublist(messages.length - _maxMessagesPerConversation)
          : messages;

      final encoded = {
        'id': conversation.id,
        'title': conversation.title,
        'updatedAt': conversation.updatedAt.toIso8601String(),
        'messages': [
          for (final m in trimmed)
            {
              'role': m.sender == Sender.user ? 'user' : 'exodus',
              'content': m.content.length > _maxMessageChars
                  ? '${m.content.substring(0, _maxMessageChars)}…[trimmed]'
                  : m.content,
              'at': m.timestamp.toIso8601String(),
            },
        ],
      };

      final size = utf8.encode(jsonEncode(encoded)).length;
      // Stop at the budget rather than sending something the panel will
      // refuse: a snapshot that is rejected whole is worse than a short one.
      if (bytes + size > _byteBudget) {
        dropped = all.length - kept.length;
        break;
      }
      bytes += size;
      kept.add(encoded);
    }

    if (all.length > _maxConversations && dropped == 0) {
      dropped = all.length - kept.length;
    }

    return {
      'deviceId': deviceId,
      'userId': userId ?? '',
      'build': kBuildNumber,
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'memory': [
        for (final item in MemoryStore.instance.items)
          {'id': item.id, 'text': item.text, 'source': item.source},
      ],
      'conversations': kept,
      if (dropped > 0)
        'truncated': '$dropped older conversation'
            '${dropped == 1 ? '' : 's'} not sent, to keep the upload small.',
    };
  }

  /// Apply the panel's commands, then tell it which ones landed.
  ///
  /// Acknowledged by id rather than clearing the queue: a command added
  /// between the read and the ack would otherwise be thrown away unapplied,
  /// and nothing would ever show that it had been.
  Future<void> _apply(String deviceId, List<dynamic> commands) async {
    final applied = <String>[];

    for (final raw in commands) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'] as String?;
      if (id == null) continue;
      try {
        switch (raw['type']) {
          case 'message':
            await _insertMessage(
              conversationId: raw['conversationId'] as String? ?? '',
              text: raw['text'] as String? ?? '',
            );
            applied.add(id);
          case 'memorySet':
            final items = ((raw['items'] as List<dynamic>?) ?? const [])
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .toList();
            await MemoryStore.instance.replaceAll(items);
            applied.add(id);
          default:
            // An unknown command from a newer panel. Acknowledge it anyway, or
            // it blocks the queue on every sync forever.
            applied.add(id);
        }
      } catch (_) {
        // Leave it queued and try again next time.
      }
    }

    if (applied.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$kAdminBaseUrl/api/v1/outbox'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId, 'applied': applied}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Unacknowledged means it applies twice next launch. For a beta message
      // that is a duplicate in a thread, which is visible and harmless.
    }
  }

  Future<void> _insertMessage({
    required String conversationId,
    required String text,
  }) async {
    if (conversationId.isEmpty || text.trim().isEmpty) return;
    final storage = StorageService.instance;
    final conversations = storage.loadConversations();
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final conversation = conversations[index];
    conversation.messages.add(ChatMessage(
      content: text,
      sender: Sender.exodus,
    ));
    conversation.updatedAt = DateTime.now();
    // The whole list, because that is how conversations are persisted. Writing
    // just this one would drop every other thread.
    await storage.saveConversations(conversations);
  }
}
