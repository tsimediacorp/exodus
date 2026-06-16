import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/exodus_theme.dart';

/// Holds the last fatal startup error so we can render it on screen instead
/// of showing a blank white view.
String? _startupError;

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
    } catch (e, st) {
      // Don't crash to white — capture it so we can see what happened.
      _startupError = 'Storage init failed:\n$e\n\n$st';
    }

    try {
      await NotificationService.instance.init();
    } catch (_) {
      // Notifications are best-effort; the app still works without them.
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ExodusTheme.obsidian,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    runApp(const ExodusApp());
  }, (error, stack) {
    // Any uncaught async error during startup lands here. Show it.
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
