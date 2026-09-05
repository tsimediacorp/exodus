import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'services/amplify_service.dart';
import 'services/memory_store.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/exodus_theme.dart';

/// Holds the last fatal startup error so we can render it on screen instead
/// of showing a blank white view.
String? _startupError;

/// True once runApp has been called. Distinguishes a fatal startup failure
/// (worth showing an error screen for) from a background error in a running
/// app (which must not blow the UI away).
bool _appStarted = false;

Future<void> main() async {
  // Replace the default grey error box with a readable, copyable error screen.
  ErrorWidget.builder = (FlutterErrorDetails details) => _ErrorView(
        message: '${details.exception}\n\n${details.stack}',
      );

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env missing or unreadable — AiService surfaces an auth error later.
    }

    try {
      await StorageService.instance.init();
      MemoryStore.instance.load();
    } catch (e, st) {
      // Don't crash to white — capture it so we can see what happened.
      _startupError = 'Storage init failed:\n$e\n\n$st';
    }

    try {
      await NotificationService.instance.init();
      // Android 13+ will not deliver anything without a granted runtime
      // permission, and it was only ever requested from inside the Devotional
      // tab — so a couple who never opened that tab silently got no reminders
      // at all. Asking here costs one prompt on first launch.
      // Permission is NOT requested here any more. Android grants exactly one
      // system dialog, and spending it before the couple knows what EXODUS
      // would send permanently disables follow-ups on a reflexive "no".
      // HomeShell explains first, then asks — see NotificationPrimer.
      final allowed = await NotificationService.instance.areEnabled() ?? false;
      // Re-arm the recurring reminder on every launch whenever notifications
      // are permitted. This used to be gated on the couple having set a
      // devotional goal, which meant anyone who never finished that flow had
      // nothing scheduled at all — no reminder existed to be delivered, and
      // every fix to the delivery path was beside the point. The devotional
      // always has content to open, canned or generated, so there is nothing
      // to wait for.
      if (allowed) {
        await NotificationService.instance.scheduleDailyDevotional();
      }
    } catch (_) {
      // Notifications are best-effort; the app still works without them.
    }

    // Couples-in-Sync backend. Best-effort: the local-first app works without
    // it, so a slow network must not hold the first frame hostage.
    try {
      await AmplifyService.configure().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Together shows its own "unavailable" state with a retry.
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ExodusTheme.obsidian,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _appStarted = true;
    runApp(const ExodusApp());
  }, (error, stack) {
    // Only a failure BEFORE the app is up warrants replacing the whole UI with
    // the error screen. Once running, an uncaught async error from any
    // background task used to tear down the live app with no way back — now it
    // is just reported.
    if (_appStarted) {
      FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack));
      return;
    }
    _startupError = '$error\n\n$stack';
    runApp(ExodusApp(forcedError: '$error\n\n$stack'));
  });
}

class ExodusApp extends StatelessWidget {
  final String? forcedError;
  const ExodusApp({super.key, this.forcedError});

  @override
  Widget build(BuildContext context) {
    final err = forcedError ?? _startupError;
    return MaterialApp(
      title: 'EXODUS',
      debugShowCheckedModeBanner: false,
      theme: ExodusTheme.build(),
      home: err != null ? _ErrorView(message: err) : const SplashScreen(),
    );
  }
}

/// Visible error screen — replaces white/blank crashes so we can read what
/// actually went wrong on the device. Tap-and-hold to select/copy.
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ExodusTheme.obsidian,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EXODUS hit an error',
                style: TextStyle(
                  color: ExodusTheme.crimson,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    message,
                    style: const TextStyle(
                      color: ExodusTheme.porcelain,
                      fontSize: 12,
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
