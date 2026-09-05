import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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
    // Set the device's actual timezone so a "7am" daily notification fires at
    // 7am LOCAL (without this, tz.local defaults to UTC).
    try {
      // flutter_timezone 5 returns a TimezoneInfo; `identifier` is the IANA
      // name that tz.getLocation expects.
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Fall back to UTC if the platform can't report a timezone.
    }
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

  /// Fixed id for the repeating daily devotional reminder.
  static const int _dailyId = 1001;

  /// Schedule a RECURRING daily devotional reminder at [hour]:00 local that
  /// repeats every day on its own — it does NOT depend on the app being opened
  /// each day. Re-calling replaces the existing one (same id), so it's safe to
  /// call on every app launch / Devotional tab open.
  Future<void> scheduleDailyDevotional({int hour = 7}) async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      _dailyId,
      'Your daily devotional',
      "Today's devotional is ready — open EXODUS to read it together.",
      first,
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
      // Repeat every day at the same local time.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Cancel the recurring daily devotional reminder.
  Future<void> cancelDailyDevotional() => _plugin.cancel(_dailyId);

  // ---------------- Diagnostics ----------------
  //
  // Notifications have now been "fixed" twice without either of us being able
  // to see whether anything actually changed — the only feedback loop was
  // waiting until seven the next morning. These make each step of the chain
  // observable, because the failure could be permission, scheduling, the
  // receivers, the timezone, or nothing having been scheduled at all.

  /// The timezone the scheduler is actually using. UTC here means
  /// [FlutterTimezone] failed and a 7am reminder will fire at the wrong hour.
  String get timezoneName => tz.local.name;

  /// Whether the OS will show our notifications at all. False means the user
  /// denied the permission or switched the app's notifications off in
  /// settings, and nothing this class does can succeed.
  Future<bool?> areEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return android.areNotificationsEnabled();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return true; // iOS reports through the permission request
    return null;
  }

  /// Everything currently scheduled. An empty list when a reminder is expected
  /// is the single most useful fact: it means nothing was ever scheduled,
  /// rather than scheduled and swallowed.
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  static const NotificationDetails _details = NotificationDetails(
    iOS: DarwinNotificationDetails(),
    android: AndroidNotificationDetails(
      'devotional',
      'Daily Devotional',
      channelDescription: 'Your morning devotional from EXODUS',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Post immediately. Proves permission, the channel and delivery — but NOT
  /// scheduling, which is the part that has been failing.
  Future<void> showNow() => _plugin.show(
        9001,
        'EXODUS is working',
        'If you can see this, notifications are permitted on this device.',
        _details,
      );

  /// Schedule one a minute out. This is the real test: it exercises the alarm
  /// and the receivers declared in the manifest, which is exactly where a
  /// scheduled notification was being lost.
  Future<tz.TZDateTime> scheduleTestSoon(
      {Duration delay = const Duration(minutes: 1)}) async {
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      9002,
      'EXODUS reminder test',
      'Scheduled notifications are working. Your devotional reminder will '
          'arrive like this.',
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    return when;
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
