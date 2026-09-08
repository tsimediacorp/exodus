import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_info.dart';
import 'debug_sync.dart';
import 'notification_service.dart';

/// Remote push, so the admin panel can reach a device.
///
/// This is the piece that did not exist: [NotificationService] only SCHEDULES
/// notifications on the phone, so nothing a server sent could ever arrive.
/// Here the device registers an FCM token with the panel, and the panel can
/// send to it.
///
/// BETA SCAFFOLDING. The registry lives in the admin panel rather than in
/// Amplify on purpose: everything built for the closed beta should come out in
/// one piece at launch, and deleting the panel deletes the registry with it.
///
/// Every failure is swallowed. A phone that cannot register is a phone that
/// does not get admin pushes; it is not a phone that fails to start.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _kToken = 'exodus.push.lastRegisteredToken';
  static const _kDeviceId = 'exodus.push.deviceId';

  bool _started = false;
  String? _token;

  String? get token => _token;

  /// Wire up Firebase and register. Safe to call when nothing is configured:
  /// with no admin URL there is nobody to register with, so it does nothing.
  Future<void> start({String? userId}) async {
    if (_started || kAdminBaseUrl.isEmpty) return;
    _started = true;
    try {
      await Firebase.initializeApp();

      // The OS permission prompt is spent by NotificationPrimer, which
      // explains first. Asking again here would be a second dialog for the
      // same permission, and on Android there is only one to spend.
      final messaging = FirebaseMessaging.instance;
      _token = await messaging.getToken();
      await _register(userId: userId);

      // A token can rotate at any time. An unregistered rotation is a device
      // that silently stops receiving, which looks exactly like a broken
      // server, so this is not optional.
      messaging.onTokenRefresh.listen((fresh) {
        _token = fresh;
        _register(userId: userId);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      // Launched from a notification while the app was dead.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);
    } catch (_) {
      // No Firebase config, no network, permission denied. Local
      // notifications and the rest of the app are unaffected.
    }
  }

  /// A stable id for this install, so the panel can list "Pixel 8" rather than
  /// a wall of identical rows, and so re-registering replaces rather than
  /// duplicates.
  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(_kDeviceId, fresh);
    return fresh;
  }

  Future<void> _register({String? userId}) async {
    final token = _token;
    if (token == null || token.isEmpty || kAdminBaseUrl.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await _deviceId();
      await http
          .post(
            Uri.parse('$kAdminBaseUrl/api/v1/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'deviceId': deviceId,
              'userId': userId ?? '',
              'platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
              'build': kBuildNumber,
            }),
          )
          .timeout(const Duration(seconds: 8));
      await prefs.setString(_kToken, token);
    } catch (_) {
      // Try again next launch. The token is still live on the device.
    }
  }

  /// A push that arrived while the app was open.
  ///
  /// Android does not draw a system notification for a foreground message, so
  /// one is raised locally. Without this an admin push sent to someone
  /// actively using the app simply vanishes, which reads as a broken send.
  void _handleForeground(RemoteMessage message) {
    // A push announcing a message from EXODUS arrives before the message
    // itself does. Pull it now so the thread is right when they open it,
    // rather than empty under a notification that said otherwise.
    if ((message.data['payload'] as String? ?? '')
        .startsWith(NotificationService.chatPayload)) {
      unawaited(DebugSync.instance.drain());
    }
    final notification = message.notification;
    if (notification == null) return;
    NotificationService.instance.deliverNow(
      title: notification.title ?? 'EXODUS',
      body: notification.body ?? '',
      payload: message.data['payload'] as String? ?? '',
    );
  }

  /// The user tapped it. Routed through the same door as a local notification
  /// so there is one place that decides where a tap lands.
  void _handleOpened(RemoteMessage message) {
    final payload = message.data['payload'] as String?;
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith(NotificationService.chatPayload)) {
      // Fetch first, then route. Opening the thread and watching the message
      // appear a second later reads as a glitch.
      unawaited(DebugSync.instance
          .drain()
          .whenComplete(() => NotificationService.instance.routeFromPush(payload)));
      return;
    }
    NotificationService.instance.routeFromPush(payload);
  }
}
