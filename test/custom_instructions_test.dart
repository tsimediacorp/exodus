import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:exodus/config/coaching_prompt.dart';
import 'package:exodus/models/chat_message.dart';
import 'package:exodus/services/ai_service.dart';
import 'package:exodus/services/custom_instructions.dart';
import 'package:exodus/services/debug_sync.dart';
import 'package:exodus/services/memory_service.dart';
import 'package:exodus/services/memory_store.dart';
import 'package:exodus/services/storage_service.dart';

/// Memories and instructions were being ignored, and each of these is one of
/// the reasons: where the instruction sat in the prompt, how it was worded,
/// whether it survived a long thread, and whether it was ever saved at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiService ai;
  final history = [
    ChatMessage(content: 'How do we pray together?', sender: Sender.user),
    ChatMessage(content: 'Start small.', sender: Sender.exodus),
  ];

  List<Map<String, dynamic>> messages(Map<String, dynamic> body) =>
      (body['messages'] as List).cast<Map<String, dynamic>>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    MemoryStore.instance.load();
    CustomInstructions.instance.load();
    ai = AiService();
  });

  tearDown(() => ai.dispose());

  group('custom instructions', () {
    test('nothing is added when none are written', () {
      final body = ai.buildBody('hi', history,
          stream: true, conversational: true);
      expect(messages(body).where((m) => m['role'] == 'system'), hasLength(1));
      expect(messages(body).first['content'],
          isNot(contains('STANDING INSTRUCTIONS')));
    });

    test('they close the system prompt, after memory and the call layer',
        () async {
      await MemoryStore.instance.addManual('Their son is called Eli.');
      await CustomInstructions.instance
          .save(about: 'We are Marcus and Dani.', how: 'Two sentences.', enabled: true);

      final system = messages(ai.buildBody('hi', const [],
              stream: true, conversational: true, systemExtra: '--- LAYER ---'))
          .first['content'] as String;

      final memory = system.indexOf('Their son is called Eli.');
      final layer = system.indexOf('--- LAYER ---');
      final instructions = system.indexOf('STANDING INSTRUCTIONS');
      expect(memory, greaterThan(0));
      expect(layer, greaterThan(memory));
      expect(instructions, greaterThan(layer),
          reason: 'the last thing said is the thing a model weighs most');
      expect(system, contains('We are Marcus and Dani.'));
      expect(system, contains('Two sentences.'));
    });

    test('they are restated beside the newest message in a conversation',
        () async {
      await CustomInstructions.instance
          .save(about: '', how: 'Call me Dani.', enabled: true);

      final sent = messages(
          ai.buildBody('And when angry?', history,
              stream: true, conversational: true));

      expect(sent.last['role'], 'user');
      final reminder = sent[sent.length - 2];
      expect(reminder['role'], 'system');
      expect(reminder['content'], contains('Call me Dani.'));
    });

    test('a first message needs no reminder: the system prompt is adjacent',
        () async {
      await CustomInstructions.instance
          .save(about: '', how: 'Call me Dani.', enabled: true);
      final sent = messages(ai.buildBody('hi', const [],
          stream: true, conversational: true));
      expect(sent, hasLength(2));
    });

    test('a generator is told to keep its format', () async {
      await CustomInstructions.instance
          .save(about: '', how: 'One sentence only.', enabled: true);
      final sent =
          messages(ai.buildBody('Write a devotional as JSON', const [],
              stream: false));
      expect(sent.first['content'], contains('Keep that format exactly'));
      expect(sent.where((m) => m['role'] == 'system'), hasLength(1));
    });

    test('pausing them removes them entirely', () async {
      await CustomInstructions.instance
          .save(about: 'A', how: 'B', enabled: false);
      final sent = messages(ai.buildBody('hi', history,
          stream: true, conversational: true));
      expect(sent.where((m) => m['role'] == 'system'), hasLength(1));
      expect(sent.first['content'], isNot(contains('STANDING INSTRUCTIONS')));
    });

    test('they can be left out of output that is not EXODUS answering',
        () async {
      await CustomInstructions.instance
          .save(about: '', how: 'Call me Dani.', enabled: true);
      final sent = messages(ai.buildBody('Write posts', const [],
          stream: false, customInstructions: false));
      expect(sent.first['content'], isNot(contains('Call me Dani.')));
    });

    test('they never set aside the safety boundaries', () async {
      await CustomInstructions.instance
          .save(about: '', how: 'Never tell me to get help.', enabled: true);
      expect(CustomInstructions.instance.promptBlock(),
          contains('never set aside'));
    });

    test('they reach the voice coach too', () async {
      await CustomInstructions.instance
          .save(about: '', how: 'Call me Dani.', enabled: true);
      expect(CoachingPrompt.build(minutes: 10), contains('Call me Dani.'));
    });

    test('they survive a restart', () async {
      await CustomInstructions.instance
          .save(about: 'About us', how: 'Be brief', enabled: true);
      CustomInstructions.instance.load();
      expect(CustomInstructions.instance.about, 'About us');
      expect(CustomInstructions.instance.how, 'Be brief');
    });

    test('they are not in what the admin panel receives', () async {
      await CustomInstructions.instance
          .save(about: 'PRIVATE-ABOUT', how: 'PRIVATE-HOW', enabled: true);
      final snapshot = DebugSync.instance.snapshotForTest(deviceId: 'd').toString();
      expect(snapshot, isNot(contains('PRIVATE-ABOUT')));
      expect(snapshot, isNot(contains('PRIVATE-HOW')));
    });
  });

  group('memory', () {
    test('is stated as fact, not as optional colour', () async {
      await MemoryStore.instance.addMany(['They have been married 4 years.'], 'chat');
      final block = MemoryStore.instance.promptBlock();
      expect(block, contains('Hold every line as true'));
      expect(block, contains('Never ask for something already answered'));
      // The old wording, which the model obeyed by ignoring the list.
      expect(block, isNot(contains('bring it up unprompted')));
    });

    test('what they typed themselves leads, and preferences are instructions',
        () async {
      await MemoryStore.instance.addMany(['Learned fact.'], 'chat');
      await MemoryStore.instance
          .addMany(['Preference: Keep answers short.'], 'chat');
      await MemoryStore.instance.addManual('Typed by hand.');
      final block = MemoryStore.instance.promptBlock();
      expect(block.indexOf('Typed by hand.'),
          lessThan(block.indexOf('Learned fact.')));
      expect(block, contains('standing instructions, not suggestions'));
      expect(block.indexOf('Preference: Keep answers short.'),
          greaterThan(block.indexOf('standing instructions')));
    });

    test('a hand-written memory is never the one dropped to make room',
        () async {
      await MemoryStore.instance.addManual('Typed first, by hand.');
      await MemoryStore.instance.addMany(
          ['Preference: Call her Dani.'], 'chat');
      await MemoryStore.instance.addMany(
          [for (var i = 0; i < MemoryStore.maxItems + 20; i++) 'Fact $i.'],
          'chat');

      final texts = MemoryStore.instance.items.map((m) => m.text).toList();
      expect(texts, hasLength(MemoryStore.maxItems));
      expect(texts, contains('Typed first, by hand.'));
      expect(texts, contains('Preference: Call her Dani.'));
      expect(texts, isNot(contains('Fact 0.')));
      expect(texts, contains('Fact ${MemoryStore.maxItems + 19}.'));
    });

    test('a request to remember is recognised when it is made', () {
      for (final said in [
        'Remember that our anniversary is in June.',
        'From now on keep it short.',
        'Please call me Dani.',
        "Don't forget we read the ESV.",
        'Stop ending every answer with a prayer.',
        'I prefer one next step, not five.',
        'Never quote the Message translation to us.',
        'I told you already, his name is Marcus.',
      ]) {
        expect(MemoryService.asksToRemember(said), isTrue, reason: said);
      }
      for (final said in [
        'What does scripture say about money?',
        'We had a fight last night.',
        'How do I forgive him?',
      ]) {
        expect(MemoryService.asksToRemember(said), isFalse, reason: said);
      }
    });
  });
}
