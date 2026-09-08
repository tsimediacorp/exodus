import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_info.dart';
import 'remote_config.dart';

/// Counts what happens, so the A/B split can answer something.
///
/// The panel could already put half the testers in group B, but there was
/// nothing to compare, which made the split decorative. This is the other
/// half of that feature.
///
/// WHAT IT SENDS: an event name, a count, the build, and the A/B group.
/// Never any content, never a message, never a verse, never a name. If a
/// question needs the text of something to answer it, the Chats page is
/// where that lives and it is deliberately a separate, visible thing.
///
/// The confessional is NOT instrumented at all. Even a bare count is metadata
/// about a feature the app promises is private, and no product question is
/// worth reaching into it.
///
/// Beta scaffolding. With no admin URL compiled in nothing is recorded and
/// nothing is sent.
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  static const _kBuffer = 'exodus.analytics.buffer';
  static const _kDeviceId = 'exodus.push.deviceId';

  /// Flush once the buffer reaches this, so a long session still reports.
  static const int _flushAt = 25;

  /// Stop growing if the panel is unreachable for a long stretch. Old counts
  /// matter less than a buffer that fills a phone's storage.
  static const int _maxBuffer = 500;

  bool get isEnabled => kAdminBaseUrl.isNotEmpty;

  /// Record one thing happening. Cheap, never throws, never blocks the caller.
  Future<void> track(String event) async {
    if (!isEnabled || event.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final buffer = prefs.getStringList(_kBuffer) ?? <String>[];
      if (buffer.length >= _maxBuffer) return;
      buffer.add(event);
      await prefs.setStringList(_kBuffer, buffer);
      if (buffer.length >= _flushAt) unawaited(flush());
    } catch (_) {
      // Analytics must never be the reason something the user did fails.
    }
  }

  /// Send what has been counted and clear it.
  ///
  /// The buffer is cleared only after the panel confirms. Clearing first would
  /// lose a day of counts to one flaky request, and these numbers only exist
  /// to be compared across groups, where a hole is worse than a delay.
  Future<void> flush() async {
    if (!isEnabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final buffer = prefs.getStringList(_kBuffer) ?? <String>[];
      if (buffer.isEmpty) return;

      final counts = <String, int>{};
      for (final event in buffer) {
        counts[event] = (counts[event] ?? 0) + 1;
      }

      final response = await http
          .post(
            Uri.parse('$kAdminBaseUrl/api/v1/events'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': prefs.getString(_kDeviceId) ?? '',
              'build': kBuildNumber,
              'group': RemoteConfig.instance.group,
              'counts': counts,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      // Only the events we actually sent: anything tracked while the request
      // was in flight must survive.
      final now = prefs.getStringList(_kBuffer) ?? <String>[];
      await prefs.setStringList(
          _kBuffer, now.length > buffer.length ? now.sublist(buffer.length) : <String>[]);
    } catch (_) {
      // Try again next launch. The counts are still on the device.
    }
  }
}

/// The events worth counting.
///
/// A fixed list rather than free strings: a typo in a tracking call produces a
/// second series that looks like a real one and quietly halves whatever it was
/// measuring.
class Events {
  Events._();

  static const appOpen = 'app_open';
  static const counselMessage = 'counsel_message';
  static const devotionalOpen = 'devotional_open';
  static const studyOpen = 'study_open';
  static const coachingStart = 'coaching_start';
  static const communityThreadOpen = 'community_thread_open';
  static const verseOpen = 'verse_open';

  /// The A/B question the split exists to answer: does being able to see and
  /// edit what EXODUS remembers change anything?
  static const memoryOpen = 'memory_open';
  static const memoryEdit = 'memory_edit';

  /// Every name the panel knows how to show. The confessional is absent on
  /// purpose - see [Analytics].
  static const all = [
    appOpen,
    counselMessage,
    devotionalOpen,
    studyOpen,
    coachingStart,
    communityThreadOpen,
    verseOpen,
    memoryOpen,
    memoryEdit,
  ];
}
