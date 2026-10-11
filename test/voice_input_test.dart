import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/services/voice_input_service.dart';
import 'package:exodus/widgets/dictation_bar.dart';

void main() {
  group('what comes back from the transcriber', () {
    test('is used as it is', () {
      expect(VoiceInputService.clean('  We fought about Ephesians 5:25.  '),
          'We fought about Ephesians 5:25.');
    });

    test('silence is nothing, not the word silence', () {
      expect(VoiceInputService.clean('[silence]'), '');
      expect(VoiceInputService.clean('Silence.'), '');
      expect(VoiceInputService.clean(''), '');
    });

    test('a sentence that merely mentions silence is kept', () {
      expect(VoiceInputService.clean('The silence between us is the problem.'),
          'The silence between us is the problem.');
    });

    test('labels and wrapping quotes are removed', () {
      expect(VoiceInputService.clean('Transcript: We need help.'),
          'We need help.');
      expect(VoiceInputService.clean('Here is the transcription: Help us.'),
          'Help us.');
      expect(VoiceInputService.clean('"We need help."'), 'We need help.');
      expect(VoiceInputService.clean('“We need help.”'),
          'We need help.');
    });

    test('quotes inside what was said are left alone', () {
      expect(VoiceInputService.clean('He said "fine" and left.'),
          'He said "fine" and left.');
    });
  });

  group('joining speech onto a draft', () {
    test('into an empty composer', () {
      expect(VoiceInputService.appendTo('', 'Hello.'), 'Hello.');
      expect(VoiceInputService.appendTo('  ', 'Hello.'), 'Hello.');
    });

    test('after something already typed', () {
      expect(VoiceInputService.appendTo('First.', 'Second.'), 'First. Second.');
      expect(VoiceInputService.appendTo('First.\n', 'Second.'),
          'First.\nSecond.');
    });

    test('nothing heard leaves the draft untouched', () {
      expect(VoiceInputService.appendTo('Typed.', ''), 'Typed.');
    });
  });

  test('loudness is drawn from speech range, and the room is stillness', () {
    expect(VoiceInputService.normalise(-80), 0);
    expect(VoiceInputService.normalise(-45), 0);
    expect(VoiceInputService.normalise(-25), closeTo(0.5, 0.001));
    expect(VoiceInputService.normalise(0), 1);
    expect(VoiceInputService.normalise(double.negativeInfinity), 0);
    expect(VoiceInputService.normalise(double.nan), 0);
  });

  test('the request forbids answering and carries the audio', () {
    final audio = Uint8List.fromList([1, 2, 3, 4]);
    final body = VoiceInputService.openRouterBody(audio);
    expect(body['temperature'], 0);

    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.first['role'], 'system');
    // The failure this guards against was observed: asked what two verses
    // say, a model recited them instead of writing down the question.
    expect(messages.first['content'], contains('Never answer'));

    final parts = (messages.last['content'] as List).cast<Map>();
    final clip = parts.firstWhere((p) => p['type'] == 'input_audio');
    expect(clip['input_audio']['format'], 'm4a');
    expect(base64Decode(clip['input_audio']['data'] as String), audio);
  });

  test('dictation is unavailable rather than broken with no keys', () {
    // No .env is loaded in tests.
    expect(VoiceInputService.isConfigured, isFalse);
  });

  testWidgets('the bar offers cancel, review and send while recording',
      (tester) async {
    final voice = VoiceInputService();
    var done = 0, sent = 0, cancelled = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DictationBar(
          voice: voice,
          transcribing: false,
          onCancel: () => cancelled++,
          onDone: () => done++,
          onSend: () => sent++,
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Stop and review'));
    await tester.tap(find.bySemanticsLabel('Stop and send'));
    await tester.tap(find.byTooltip('Cancel recording'));
    expect([done, sent, cancelled], [1, 1, 1]);

    await tester.pumpWidget(const SizedBox());
    await voice.dispose();
  });

  testWidgets('while transcribing only cancel remains', (tester) async {
    final voice = VoiceInputService();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DictationBar(
          voice: voice,
          transcribing: true,
          onCancel: () {},
          onDone: () {},
          onSend: () {},
        ),
      ),
    ));
    expect(find.text('Writing down what you said…'), findsOneWidget);
    expect(find.byTooltip('Stop and review'), findsNothing);
    expect(find.bySemanticsLabel('Stop and send'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await voice.dispose();
  });
}
