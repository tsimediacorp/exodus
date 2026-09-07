import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_info.dart';

/// What the admin panel is telling this build.
///
/// Two jobs: block a build that is too old to be used, and switch closed-beta
/// features on and off per tester without shipping a new binary.
///
/// FAILURE MUST BE INVISIBLE. If the panel is down, unreachable, or was never
/// deployed, the app runs exactly as it did before this existed: no gate, and
/// every flag at its built-in default. A remote-config service that can brick
/// the app when it 500s is worse than no remote config, so nothing here throws
/// and nothing here blocks the first frame.
class RemoteConfig extends ChangeNotifier {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  static const _kCache = 'exodus.remoteConfig.cache';

  /// Built-in defaults. These are what runs when the panel says nothing, so
  /// they must be the shipping behaviour, not the experiment.
  static const Map<String, bool> _defaults = {
    'memoryEditing': true,
    'community': true,
    'coaching': true,
  };

  Map<String, dynamic> _values = const {};
  bool _fetched = false;

  bool get updateRequired => _values['updateRequired'] == true;
  bool get updateAvailable => _values['updateAvailable'] == true;
  String get updateUrl => (_values['updateUrl'] as String?) ?? '';
  String get updateMessage =>
      (_values['message'] as String?)?.trim().isNotEmpty == true
          ? _values['message'] as String
          : 'A newer build is ready.';
  String get group => (_values['group'] as String?) ?? 'A';

  /// Whether the panel has ever answered on this device.
  bool get hasAnswer => _values.isNotEmpty;

  /// A feature switch. Falls back to the built-in default, then to false.
  bool flag(String name) {
    final flags = _values['flags'];
    if (flags is Map && flags[name] is bool) return flags[name] as bool;
    return _defaults[name] ?? false;
  }

  /// Read the last answer off disk. Synchronous after this, and the reason a
  /// launch with no network still honours a gate set yesterday.
  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      if (raw != null && raw.isNotEmpty) {
        _values = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {
      // A corrupt cache is the same as no cache.
      _values = const {};
    }
  }

  /// Ask the panel. Never throws; never takes longer than [timeout].
  ///
  /// [userId] is the Cognito sub when signed in. Without it the tester still
  /// gets the defaults and a stable group, so this is safe to call before
  /// sign-in — which matters, because a build old enough to be blocked may be
  /// old enough to have a broken sign-in.
  Future<void> refresh({
    String? userId,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (kAdminBaseUrl.isEmpty) return;
    try {
      final uri = Uri.parse('$kAdminBaseUrl/api/v1/config').replace(
        queryParameters: {
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
          'build': '$kBuildNumber',
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      _values = decoded;
      _fetched = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kCache, response.body);
      } catch (_) {
        // Not being able to cache is not a reason to ignore a live answer.
      }
      notifyListeners();
    } catch (_) {
      // Offline, DNS, TLS, timeout, malformed JSON. The cached answer stands.
    }
  }

  /// True when this run got a live answer rather than a cached one. Shown in
  /// Settings so a tester can tell "the flag is off" from "the panel is down".
  bool get isLive => _fetched;

  @visibleForTesting
  void debugSet(Map<String, dynamic> values) {
    _values = values;
    notifyListeners();
  }
}
