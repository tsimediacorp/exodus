import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_drawer.dart';
import 'chat_screen.dart';
import 'coaching_screen.dart';
import 'devotional_screen.dart';
import 'memory_screen.dart';
import 'together_screen.dart';

/// Root navigation after the splash. Modes (Counsel / Coaching / Devotional)
/// live in the left drawer; an IndexedStack keeps each mode's state alive. The
/// drawer's chats section drives the Counsel conversation list.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _mode = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  static const int _counselMode = 0;
  static const int _devotionalMode = 2;

  @override
  void initState() {
    super.initState();
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
      setState(() => _mode = _devotionalMode);
      NotificationService.instance.openDevotionalRequested.value = false;
    }
  }

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // Refresh the drawer's chat list / current-highlight each time it opens.
      onDrawerChanged: (isOpen) {
        if (isOpen) setState(() {});
      },
      drawer: AppDrawer(
        currentMode: _mode,
        onSelectMode: (i) => setState(() => _mode = i),
        conversations: StorageService.instance.loadConversations(),
        currentConversationId: _chatKey.currentState?.currentId,
        onNewConversation: () {
          setState(() => _mode = _counselMode);
          _chatKey.currentState?.newConversation();
        },
        onSelectConversation: (id) {
          setState(() => _mode = _counselMode);
          _chatKey.currentState?.openConversation(id);
        },
        onDeleteConversation: (id) {
          _chatKey.currentState?.deleteConversationById(id);
          setState(() {});
        },
        onOpenMemory: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MemoryScreen()),
        ),
      ),
      body: IndexedStack(
        index: _mode,
        children: [
          ChatScreen(key: _chatKey, onOpenMenu: _openMenu),
          CoachingScreen(onOpenMenu: _openMenu),
          DevotionalScreen(onOpenMenu: _openMenu),
          TogetherScreen(onOpenMenu: _openMenu),
        ],
      ),
    );
  }
}
