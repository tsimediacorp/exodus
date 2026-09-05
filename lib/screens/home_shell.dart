import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/exodus_bottom_nav.dart';
import 'chat_screen.dart';
import 'coaching_screen.dart';
import 'confessional_screen.dart';
import 'devotional_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'memory_screen.dart';
import 'profile_screen.dart';
import 'study_screen.dart';
import 'together_screen.dart';

/// Root navigation after the splash.
///
/// Two ways in, one set of screens. The bottom bar carries the four places you
/// return to — Home, Explore, Library, Profile — while the drawer still
/// switches the six modes exactly as it always did. Both select entries in the
/// SAME IndexedStack, so a mode opened from the drawer and one opened from
/// Explore are the same live screen with the same state, not two copies.
///
/// The stack is ordered tabs-then-modes and the two index spaces are kept
/// separate on purpose: [_modeBase] is the only place that relationship is
/// written down, and AppDrawer's mode list is indexed from zero independently.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Index into the IndexedStack below — tabs 0..3, then modes.
  int _index = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  /// Where the drawer's modes begin in the stack. Mode N lives at
  /// _modeBase + N, matching AppDrawer's own list order.
  static const int _modeBase = 4;

  static const int _counselMode = 0;
  static const int _devotionalMode = 2;
  static const int _togetherMode = 5;

  int get _counselIndex => _modeBase + _counselMode;

  /// The bottom bar shows no selection while a mode is open — none of its four
  /// tabs is where you are, and lighting one would be a lie.
  int? get _selectedTab => _index < _modeBase ? _index : null;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.openDevotionalRequested
        .addListener(_onOpenDevotional);
    NotificationService.instance.openCheckInRequested
        .addListener(_onOpenCheckIn);
  }

  @override
  void dispose() {
    NotificationService.instance.openDevotionalRequested
        .removeListener(_onOpenDevotional);
    NotificationService.instance.openCheckInRequested
        .removeListener(_onOpenCheckIn);
    super.dispose();
  }

  void _onOpenDevotional() {
    if (NotificationService.instance.openDevotionalRequested.value && mounted) {
      setState(() => _index = _modeBase + _devotionalMode);
      NotificationService.instance.openDevotionalRequested.value = false;
    }
  }

  /// EXODUS followed up and the couple tapped it: go straight into Counsel on
  /// that specific thing, rather than dropping them on a home screen to hunt
  /// for what the notification meant.
  void _onOpenCheckIn() {
    final id = NotificationService.instance.openCheckInRequested.value;
    if (id == null || !mounted) return;
    NotificationService.instance.openCheckInRequested.value = null;
    setState(() => _index = _counselIndex);
    // After the frame, so ChatScreen exists in the stack before it is asked
    // to open anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatKey.currentState?.openCheckInById(id);
    });
  }

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  void _goToMode(int mode) => setState(() => _index = _modeBase + mode);

  void _goToTab(int tab) {
    setState(() => _index = tab);
    // Times and previews go stale while you are away in a conversation.
    if (tab == ExodusBottomNav.home) _homeKey.currentState?.refresh();
  }

  void _newConversation() {
    setState(() => _index = _counselIndex);
    _chatKey.currentState?.newConversation();
  }

  void _openConversation(String id) {
    setState(() => _index = _counselIndex);
    _chatKey.currentState?.openConversation(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      // Refresh the drawer's chat list / current-highlight each time it opens.
      onDrawerChanged: (isOpen) {
        if (isOpen) setState(() {});
      },
      drawer: AppDrawer(
        currentMode: _index >= _modeBase ? _index - _modeBase : -1,
        onSelectMode: _goToMode,
        conversations: StorageService.instance.loadConversations(),
        currentConversationId: _chatKey.currentState?.currentId,
        onNewConversation: _newConversation,
        onSelectConversation: _openConversation,
        onDeleteConversation: (id) {
          _chatKey.currentState?.deleteConversationById(id);
          setState(() {});
        },
        onOpenMemory: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MemoryScreen()),
        ),
      ),
      bottomNavigationBar: ExodusBottomNav(
        selected: _selectedTab,
        onSelect: _goToTab,
        onNewChat: _newConversation,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          // ---- Tabs 0..3 ----
          HomeScreen(
            key: _homeKey,
            onOpenMenu: _openMenu,
            onOpenConversation: _openConversation,
            onNewConversation: _newConversation,
            onSeeAll: _openMenu,
          ),
          ExploreScreen(onOpenMenu: _openMenu, onOpenMode: _goToMode),
          const LibraryScreen(),
          ProfileScreen(onOpenTogether: () => _goToMode(_togetherMode)),

          // ---- Modes, from _modeBase. Order must match AppDrawer._modes. ----
          ChatScreen(key: _chatKey, onOpenMenu: _openMenu),
          CoachingScreen(onOpenMenu: _openMenu),
          DevotionalScreen(onOpenMenu: _openMenu),
          StudyScreen(
              onOpenMenu: _openMenu,
              isActive: _index == _modeBase + 3),
          ConfessionalScreen(onOpenMenu: _openMenu),
          TogetherScreen(onOpenMenu: _openMenu),
        ],
      ),
    );
  }
}
