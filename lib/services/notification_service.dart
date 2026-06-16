import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications for the daily devotional.
///
/// No backend: the next day's devotional is generated while the app is open
/// (see DevotionalScreen) and a local notification is scheduled for the
/// morning carrying it. Tapping opens the Devotional tab.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Flipped true when a devotional notification is tapped; HomeShell watches
  /// this to switch to the Devotional tab.
  final ValueNotifier<bool> openDevotionalRequested = ValueNotifier(false);

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(iOS: ios, android: android),
      onDidReceiveNotificationResponse: (_) =>
          openDevotionalRequested.value = true,
    );
    _ready = true;
  }

  /// Ask the OS for notification permission. Returns whether it was granted.
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Schedule a one-shot morning notification for [day] at [hour]:00 local.
  /// Using TZDateTime.from on a local wall-clock DateTime fires at the correct
  /// absolute instant regardless of the configured tz database default.
  Future<void> scheduleMorning({
    required DateTime day,
    required int hour,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    final when = tz.TZDateTime.from(
      DateTime(day.year, day.month, day.day, hour),
      tz.local,
    );
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return; // never schedule the past
    await _plugin.zonedSchedule(
      90000 + day.day, // stable id per day-of-month
      title,
      body,
      when,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          'devotional',
          'Daily Devotional',
          channelDescription: 'Your morning devotional from EXODUS',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
