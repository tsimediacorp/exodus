import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/services/remote_config.dart';

/// The rule this file exists to protect: a remote-config service that can
/// brick the app when the panel is down is worse than no remote config. Every
/// test here is a way the panel could fail, and the assertion is that the app
/// carries on.
void main() {
  final config = RemoteConfig.instance;

  tearDown(() => config.debugSet(const {}));

  group('when the panel has said nothing', () {
    test('no gate, and the flags are the shipping defaults', () {
      expect(config.updateRequired, isFalse);
      expect(config.updateAvailable, isFalse);
      expect(config.hasAnswer, isFalse);
      expect(config.flag('memoryEditing'), isTrue);
      expect(config.flag('community'), isTrue);
      expect(config.flag('coaching'), isTrue);
    });

    test('an unknown flag is off rather than an exception', () {
      expect(config.flag('somethingNobodyShipped'), isFalse);
    });

    test('the group is A, so nobody lands in an experiment by accident', () {
      expect(config.group, 'A');
    });
  });

  group('a malformed answer cannot lock anyone out', () {
    test('flags of the wrong type fall back to the defaults', () {
      config.debugSet({'flags': 'not a map'});
      expect(config.flag('memoryEditing'), isTrue);

      config.debugSet({'flags': {'memoryEditing': 'yes'}});
      expect(config.flag('memoryEditing'), isTrue,
          reason: 'a string is not a bool, so the default stands');
    });

    test('updateRequired only blocks on a real true', () {
      for (final value in ['true', 1, null, 'yes']) {
        config.debugSet({'updateRequired': value});
        expect(config.updateRequired, isFalse, reason: '$value');
      }
      config.debugSet({'updateRequired': true});
      expect(config.updateRequired, isTrue);
    });

    test('an empty message still reads as a sentence', () {
      config.debugSet({'message': '   '});
      expect(config.updateMessage, isNotEmpty);
      config.debugSet({'message': 'Notifications finally work.'});
      expect(config.updateMessage, 'Notifications finally work.');
    });

    test('a missing update url is empty, not null', () {
      config.debugSet({'updateRequired': true});
      expect(config.updateUrl, '');
    });
  });

  group('a real answer is honoured', () {
    setUp(() => config.debugSet({
          'updateRequired': true,
          'updateAvailable': true,
          'updateUrl': 'https://appdistribution.firebase.google.com/x',
          'message': 'Build 46 fixes the notification bug.',
          'group': 'B',
          'flags': {'memoryEditing': false, 'community': true},
        }));

    test('the gate, the link and the message all come through', () {
      expect(config.updateRequired, isTrue);
      expect(config.updateUrl, contains('appdistribution'));
      expect(config.updateMessage, 'Build 46 fixes the notification bug.');
    });

    test('a flag turned off remotely is off', () {
      expect(config.flag('memoryEditing'), isFalse);
      expect(config.flag('community'), isTrue);
    });

    test('a flag the panel did not mention keeps its default', () {
      expect(config.flag('coaching'), isTrue);
    });

    test('the group comes through for the app to vary on', () {
      expect(config.group, 'B');
    });
  });
}
