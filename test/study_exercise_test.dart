import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/config/study_fallback.dart';
import 'package:exodus/models/study_exercise.dart';

void main() {
  final day = DateTime(2026, 8, 28);

  group('fromGenerated', () {
    test('reads steps when the model returns a list', () {
      final e = StudyExercise.fromGenerated(day: day, json: {
        'title': 'Take the Enemy to Court',
        'form': 'courtroom',
        'steps': ['Write the accusation.', 'Answer it with scripture.'],
      });
      expect(e.steps, ['Write the accusation.', 'Answer it with scripture.']);
    });

    test('reads steps when the model returns one newline-joined string', () {
      // Models drift between a list and a block of text; both have to work.
      final e = StudyExercise.fromGenerated(day: day, json: {
        'steps': '1. Write the accusation.\n2. Answer it with scripture.',
      });
      expect(e.steps, ['Write the accusation.', 'Answer it with scripture.']);
    });

    test('strips bullet markers as well as numbering', () {
      final e = StudyExercise.fromGenerated(day: day, json: {
        'steps': '- First thing\n* Second thing\n3) Third thing',
      });
      expect(e.steps, ['First thing', 'Second thing', 'Third thing']);
    });

    test('drops blank steps rather than rendering empty rows', () {
      final e = StudyExercise.fromGenerated(day: day, json: {
        'steps': ['Real step', '   ', ''],
      });
      expect(e.steps, ['Real step']);
    });

    test('missing keys do not throw and the title has a floor', () {
      final e = StudyExercise.fromGenerated(day: day, json: const {});
      expect(e.title, isNotEmpty);
      expect(e.steps, isEmpty);
      expect(e.premise, '');
    });
  });

  group('needsGeneration', () {
    StudyExercise make({bool fallback = false}) => StudyExercise(
          day: day,
          title: 'T',
          form: 'f',
          premise: 'p',
          scriptureRef: 'John 1:1',
          scriptureText: 'In the beginning was the Word.',
          steps: const ['one', 'two'],
          question: 'q',
          closingPrayer: 'amen',
          isFallback: fallback,
        );

    test('nothing stored needs generating', () {
      expect(StudyExercise.needsGeneration(null), isTrue);
    });

    test('a real exercise is left alone', () {
      expect(StudyExercise.needsGeneration(make()), isFalse);
    });

    test('an untouched fallback is upgraded when the network returns', () {
      expect(StudyExercise.needsGeneration(make(fallback: true)), isTrue);
    });

    test('a fallback already completed is NOT replaced underneath them', () {
      final done = make(fallback: true)..completedAt = DateTime.now();
      expect(StudyExercise.needsGeneration(done), isFalse);
    });

    test('a fallback with notes written against it is NOT replaced', () {
      final written = make(fallback: true)..notes = 'what I saw';
      expect(StudyExercise.needsGeneration(written), isFalse);
    });
  });

  group('round trip', () {
    test('survives json, completion and notes included', () {
      final original = StudyExercise.fromGenerated(day: day, json: {
        'title': 'The Third Reading',
        'form': 'copy by hand',
        'premise': 'Slow down enough to see it again.',
        'scriptureRef': '1 Corinthians 13:4',
        'scriptureText': 'Charity suffereth long.',
        'steps': ['Copy it out.', 'Read it aloud.'],
        'question': 'What did you circle?',
        'closingPrayer': 'Amen.',
      })
        ..completedAt = DateTime(2026, 8, 28, 9, 30)
        ..notes = 'patience';

      final restored =
          StudyExercise.fromJson(original.toJson());

      expect(restored.title, original.title);
      expect(restored.form, original.form);
      expect(restored.steps, original.steps);
      expect(restored.notes, 'patience');
      expect(restored.isComplete, isTrue);
      expect(restored.completedAt, DateTime(2026, 8, 28, 9, 30));
      expect(restored.dayKey, original.dayKey);
    });

    test('an incomplete exercise round-trips with a null completedAt', () {
      final e = StudyExercise.fromGenerated(day: day, json: {'title': 'x'});
      expect(StudyExercise.fromJson(e.toJson()).isComplete, isFalse);
    });
  });

  group('fallback bank', () {
    test('every entry is a complete, usable exercise', () {
      // The bank is the offline guarantee, so a malformed entry there is a
      // blank tab for someone with no signal.
      for (var i = 0; i < StudyFallback.count; i++) {
        final e = StudyExercise.fromGenerated(
          day: DateTime(2026, 1, 1).add(Duration(days: i)),
          json: Map<String, dynamic>.from(
              StudyFallback.forDay(DateTime(2026, 1, 1).add(Duration(days: i)))),
          isFallback: true,
        );
        expect(e.title, isNotEmpty, reason: 'entry $i has no title');
        expect(e.steps.length, greaterThanOrEqualTo(2),
            reason: 'entry $i is not an exercise');
        expect(e.scriptureText, isNotEmpty, reason: 'entry $i has no passage');
        expect(e.closingPrayer, isNotEmpty, reason: 'entry $i has no prayer');
        expect(e.isFallback, isTrue);
      }
    });

    test('rotates rather than serving one practice forever', () {
      final titles = {
        for (var i = 0; i < StudyFallback.count; i++)
          StudyFallback.forDay(DateTime(2026, 1, 1).add(Duration(days: i)))['title']
      };
      expect(titles, hasLength(StudyFallback.count));
    });

    test('dates before the epoch anchor still land in range', () {
      // forDay indexes off a difference from 2000, which is negative for
      // earlier dates — a raw modulo would throw a RangeError.
      expect(() => StudyFallback.forDay(DateTime(1999, 5, 4)), returnsNormally);
    });
  });
}
