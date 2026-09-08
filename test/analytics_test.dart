import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:exodus/services/analytics.dart';

/// Analytics is beta scaffolding that runs on every screen. The risks are that
/// it does something when it should not, and that a typo in an event name
/// quietly halves whatever it was measuring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a build with nowhere to report does nothing', () {
    test('disabled without an admin url, which is a launch build', () {
      expect(Analytics.instance.isEnabled, isFalse);
    });

    test('tracking writes nothing to disk', () async {
      await Analytics.instance.track(Events.appOpen);
      await Analytics.instance.track(Events.counselMessage);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('exodus.analytics.buffer'), isNull);
    });

    test('flushing is a no-op rather than a failed request', () async {
      await Analytics.instance.flush();
    });

    test('an empty event name is never recorded', () async {
      await Analytics.instance.track('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('exodus.analytics.buffer'), isNull);
    });
  });

  group('the event names', () {
    test('are unique, so nothing is counted under two series', () {
      expect(Events.all.toSet().length, Events.all.length);
    });

    test('are all non-empty and lower_snake, matching the panel labels', () {
      for (final name in Events.all) {
        expect(name, isNotEmpty);
        expect(RegExp(r'^[a-z][a-z_]*$').hasMatch(name), isTrue, reason: name);
      }
    });

    test('include the two the A/B split exists to answer', () {
      expect(Events.all, contains(Events.memoryOpen));
      expect(Events.all, contains(Events.memoryEdit));
    });

    test('never mention the confessional', () {
      // Even a bare count is metadata about a feature the app promises is
      // private. Nothing here should ever make that measurable.
      for (final name in Events.all) {
        expect(name.contains('confess'), isFalse, reason: name);
      }
    });
  });
}
