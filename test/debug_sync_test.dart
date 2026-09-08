import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:exodus/models/chat_message.dart';
import 'package:exodus/models/conversation.dart';
import 'package:exodus/services/debug_sync.dart';
import 'package:exodus/services/memory_store.dart';
import 'package:exodus/services/storage_service.dart';

/// DebugSync is beta scaffolding that carries the most private material in the
/// app. These cover the two ways it could do real harm: sending more than it
/// should, and applying a panel command wrongly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Conversation chat(String id, int messages, {String body = 'hello there'}) =>
      Conversation(
        id: id,
        title: 'Thread $id',
        updatedAt: DateTime(2026, 9, id.hashCode.abs() % 27 + 1),
        messages: [
          for (var i = 0; i < messages; i++)
            ChatMessage(
              content: '$body $i',
              sender: i.isEven ? Sender.user : Sender.exodus,
              timestamp: DateTime(2026, 9, 1, 8, i),
            ),
        ],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    MemoryStore.instance.load();
  });

  group('nothing is sent without somewhere to send it', () {
    test('a build with no admin url is disabled', () {
      // kAdminBaseUrl is empty in tests, which is exactly a launch build.
      expect(DebugSync.instance.isEnabled, isFalse);
    });

    test('run and drain are no-ops when disabled', () async {
      await StorageService.instance.saveConversations([chat('a', 4)]);
      // Would throw or hang if it tried to reach the network.
      await DebugSync.instance.run();
      await DebugSync.instance.drain();
      expect(StorageService.instance.loadConversations(), hasLength(1));
    });
  });

  group('a panel command changes the device', () {
    test('a message is appended to the right thread, as EXODUS', () async {
      await StorageService.instance.saveConversations([chat('a', 2), chat('b', 2)]);

      await DebugSync.instance.applyForTest([
        {'id': 'c1', 'type': 'message', 'conversationId': 'b', 'text': 'Thinking of you both.'},
      ]);

      final all = StorageService.instance.loadConversations();
      final a = all.firstWhere((c) => c.id == 'a');
      final b = all.firstWhere((c) => c.id == 'b');
      expect(a.messages, hasLength(2), reason: 'the other thread is untouched');
      expect(b.messages, hasLength(3));
      expect(b.messages.last.content, 'Thinking of you both.');
      expect(b.messages.last.sender, Sender.exodus);
    });

    test('a message for a thread that is gone is dropped, not crashed on',
        () async {
      await StorageService.instance.saveConversations([chat('a', 2)]);
      await DebugSync.instance.applyForTest([
        {'id': 'c1', 'type': 'message', 'conversationId': 'deleted', 'text': 'hi'},
      ]);
      expect(StorageService.instance.loadConversations().first.messages, hasLength(2));
    });

    test('memory is replaced wholesale, in the order given', () async {
      await MemoryStore.instance.addMany(['old one', 'old two'], 'chat');
      await DebugSync.instance.applyForTest([
        {'id': 'c2', 'type': 'memorySet', 'items': ['they argue about money', '  ', 'his mother']},
      ]);
      final texts = MemoryStore.instance.items.map((m) => m.text).toList();
      expect(texts, ['they argue about money', 'his mother']);
    });

    test('near-duplicates survive an admin edit', () async {
      // addMany drops near-duplicates; an explicit edit must not, or a line
      // someone typed vanishes and looks like a failed save.
      await DebugSync.instance.applyForTest([
        {'id': 'c3', 'type': 'memorySet', 'items': ['They argue about money', 'they argue about money!']},
      ]);
      expect(MemoryStore.instance.items, hasLength(2));
    });

    test('a command with no id is ignored', () async {
      await StorageService.instance.saveConversations([chat('a', 1)]);
      await DebugSync.instance.applyForTest([
        {'type': 'message', 'conversationId': 'a', 'text': 'no id'},
      ]);
      expect(StorageService.instance.loadConversations().first.messages, hasLength(1));
    });

    test('junk in the queue does not stop the good commands', () async {
      await StorageService.instance.saveConversations([chat('a', 1)]);
      await DebugSync.instance.applyForTest([
        'not a map',
        {'id': 'x', 'type': 'somethingNewer'},
        {'id': 'c1', 'type': 'message', 'conversationId': 'a', 'text': 'landed'},
      ]);
      expect(StorageService.instance.loadConversations().first.messages.last.content,
          'landed');
    });
  });

  group('the snapshot stays small', () {
    test('only the newest conversations go, and it says what it left', () async {
      await StorageService.instance.saveConversations([
        for (var i = 0; i < 30; i++) chat('c$i', 3),
      ]);
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd1');
      final conversations = snapshot['conversations'] as List;
      expect(conversations.length, lessThanOrEqualTo(20));
      expect(snapshot['truncated'], isNotNull);
      expect(snapshot['truncated'] as String, contains('not sent'));
    });

    test('a very long thread keeps its most recent messages', () async {
      await StorageService.instance.saveConversations([chat('a', 200)]);
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd1');
      final messages =
          (snapshot['conversations'] as List).first['messages'] as List;
      expect(messages.length, 80);
      // The tail, in order: debugging needs what happened most recently.
      expect((messages.last as Map)['content'], 'hello there 199');
      expect((messages.first as Map)['content'], 'hello there 120');
    });

    test('a single enormous message is trimmed rather than dropped', () async {
      await StorageService.instance
          .saveConversations([chat('a', 1, body: 'x' * 9000)]);
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd1');
      final content =
          ((snapshot['conversations'] as List).first['messages'] as List)
              .first['content'] as String;
      expect(content.length, lessThan(4100));
      expect(content, endsWith('[trimmed]'));
    });

    test('the whole payload stays under the budget', () async {
      await StorageService.instance.saveConversations([
        for (var i = 0; i < 25; i++) chat('c$i', 80, body: 'y' * 3000),
      ]);
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd1');
      final bytes = snapshot.toString().length;
      expect(bytes, lessThan(600 * 1024), reason: 'roughly the 400KB budget');
    });

    test('memory goes in full, and confessions never do', () async {
      await MemoryStore.instance.addMany(['a fact'], 'chat');
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd1');
      expect(snapshot['memory'], hasLength(1));
      expect(snapshot.containsKey('confessions'), isFalse,
          reason: 'the confessional was promised to never leave the device');
    });
  });
}
