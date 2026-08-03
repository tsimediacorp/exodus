import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/models/check_in.dart';

CheckIn make({
  String id = 'a',
  String question = 'How has that been since?',
  Duration due = Duration.zero,
  CheckInStatus status = CheckInStatus.pending,
}) =>
    CheckIn(
      id: id,
      question: question,
      because: 'they mentioned tension at home',
      topic: 'family',
      dueAt: DateTime.now().add(due),
      status: status,
    );

void main() {
  group('due and open state', () {
    test('a pending check-in past its due date is due', () {
      expect(make(due: const Duration(days: -1)).isDue, isTrue);
    });

    test('a pending check-in before its due date is not due', () {
      // The wait is the whole point — following up immediately is nagging.
      expect(make(due: const Duration(days: 3)).isDue, isFalse);
    });

    test('a dismissed check-in is never due, even past its date', () {
      final c = make(due: const Duration(days: -5), status: CheckInStatus.dismissed);
      expect(c.isOpen, isFalse);
      expect(c.isDue, isFalse);
    });

    test('an answered check-in is closed', () {
      expect(make(status: CheckInStatus.answered).isOpen, isFalse);
    });

    test('a raised check-in is still open', () {
      expect(make(status: CheckInStatus.raised).isOpen, isTrue);
    });
  });

  group('fingerprint de-duplication', () {
    test('the same question re-extracted is treated as a duplicate', () {
      final a = make(question: 'How has that been since?');
      final b = make(id: 'b', question: 'How has that been since?');
      expect(a.fingerprint, b.fingerprint);
    });

    test('punctuation and case do not create a false duplicate-miss', () {
      final a = make(question: 'How has that been since?');
      final b = make(id: 'b', question: 'how has THAT been since');
      expect(a.fingerprint, b.fingerprint);
    });

    test('genuinely different questions are distinct', () {
      final a = make(question: 'How is the budget going?');
      final b = make(id: 'b', question: 'How has that been since?');
      expect(a.fingerprint, isNot(b.fingerprint));
    });
  });

  group('JSON round-trip', () {
    test('preserves status and timestamps', () {
      final c = make(status: CheckInStatus.raised)
        ..raisedAt = DateTime(2026, 8, 2, 9, 30);
      final back = CheckIn.fromJson(c.toJson());
      expect(back.status, CheckInStatus.raised);
      expect(back.raisedAt, DateTime(2026, 8, 2, 9, 30));
      expect(back.question, c.question);
      expect(back.because, c.because);
      expect(back.topic, c.topic);
    });

    test('an unknown status falls back to pending rather than throwing', () {
      final json = make().toJson()..['status'] = 'nonsense';
      expect(CheckIn.fromJson(json).status, CheckInStatus.pending);
    });

    test('a dismissed check-in survives a restart still dismissed', () {
      // The important one: dismissing must be permanent across app launches,
      // or EXODUS re-asks something they already refused.
      final c = make(status: CheckInStatus.dismissed)
        ..resolvedAt = DateTime(2026, 8, 1);
      final back = CheckIn.fromJson(c.toJson());
      expect(back.status, CheckInStatus.dismissed);
      expect(back.isOpen, isFalse);
    });
  });
}
