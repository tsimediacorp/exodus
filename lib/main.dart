import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'services/storage_service.dart';
import 'theme/exodus_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env missing or unreadable — fall back to empty env. AiService will
    // surface an auth error in the chat rather than crashing on launch.
  }
  try {
    await StorageService.instance.init();
  } catch (_) {
    // shared_preferences hiccup on first launch shouldn't crash the app;
    // user will see an empty conversation list and can start fresh.
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: ExodusTheme.obsidian,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ExodusApp());
}

class ExodusApp extends StatelessWidget {
  const ExodusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EXODUS',
      debugShowCheckedModeBanner: false,
      theme: ExodusTheme.build(),
      home: const SplashScreen(),
    );
  }
}
