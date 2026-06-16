import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/exodus_theme.dart';
import 'chat_screen.dart';
import 'coaching_screen.dart';
import 'devotional_screen.dart';

/// Root navigation after the splash. Three tabs: the text "Counsel" chat, the
/// live "Coaching" voice sessions, and the daily "Devotional". An IndexedStack
/// keeps each tab's state alive when switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [ChatScreen(), CoachingScreen(), DevotionalScreen()];
  static const int _devotionalTab = 2;

  @override
  void initState() {
    super.initState();
    // A tapped morning devotional notification asks us to open that tab.
    NotificationService.instance.openDevotionalRequested
        .addListener(_onOpenDevotional);
  }

  @override
  void dispose() {
    NotificationService.instance.openDevotionalRequested
        .removeListener(_onOpenDevotional);
    super.dispose();
  }

  void _onOpenDevotional() {
    if (NotificationService.instance.openDevotionalRequested.value && mounted) {
      setState(() => _index = _devotionalTab);
      NotificationService.instance.openDevotionalRequested.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: ExodusTheme.obsidian,
          border: Border(top: BorderSide(color: ExodusTheme.steel, width: 1)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: ExodusTheme.covenantBlue.withValues(alpha: 0.18),
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 12, color: ExodusTheme.ironMist),
            ),
          ),
          child: NavigationBar(
            height: 64,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined, color: ExodusTheme.ironMist),
                selectedIcon: Icon(Icons.menu_book, color: ExodusTheme.covenantGlow),
                label: 'Counsel',
              ),
              NavigationDestination(
                icon: Icon(Icons.spatial_audio_off_outlined, color: ExodusTheme.ironMist),
                selectedIcon: Icon(Icons.spatial_audio_off, color: ExodusTheme.covenantGlow),
                label: 'Coaching',
              ),
              NavigationDestination(
                icon: Icon(Icons.wb_sunny_outlined, color: ExodusTheme.ironMist),
                selectedIcon: Icon(Icons.wb_sunny, color: ExodusTheme.covenantGlow),
                label: 'Devotional',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
