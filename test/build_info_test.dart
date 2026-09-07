import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exodus/config/build_info.dart';

/// The force-update gate compares [kBuildNumber] against a number set in the
/// admin panel. If the constant drifts behind pubspec, every shipped build
/// reports an old number and locks its own users out of an app they already
/// updated. That failure would look like a server problem and be nearly
/// impossible to spot from the panel, so it is pinned here instead.
void main() {
  test('kBuildNumber matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*\S+\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no "version: x.y.z+build" in pubspec.yaml');

    final fromPubspec = int.parse(match!.group(1)!);
    expect(kBuildNumber, fromPubspec,
        reason: 'lib/config/build_info.dart says $kBuildNumber but pubspec.yaml '
            'says $fromPubspec. Bump both, or the shipped build will report a '
            'stale number to the update gate and lock users out.');
  });
}
