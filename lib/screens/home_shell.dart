import 'package:flutter/material.dart';
import '../layout/exodus_layout.dart';
import '../services/action_plan_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/analytics.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_bottom_nav.dart';
import '../widgets/exodus_nav_rail.dart';
import '../widgets/notification_primer.dart';
import '../widgets/page_backdrop.dart';
import '../widgets/unfold_reveal.dart';
import 'active_steps_screen.dart';
import 'chat_screen.dart';
import 'conversations_screen.dart';
import 'coaching_screen.dart';
import 'confessional_screen.dart';
import 'devotional_screen.dart';
import 'explore_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'study_screen.dart';
import 'together_screen.dart';

/// Root navigation after the splash.
///
/// One way in. The bottom bar carries the four places you return to — Home,
/// Explore, Library, Profile — and everything the drawer used to hold now has
/// a place in them: the modes are Explore, the library links are Library,
/// Settings is Profile, and the conversation list is Home plus its "See all".
///
/// The drawer is gone deliberately. It was a second, parallel navigation for
/// the same destinations, and two routes to one screen is how a mode ends up
/// reachable but undiscoverable.
///
/// The stack is ordered tabs-then-modes: [_modeBase] is the only place that
/// relationship is written down.
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
  /// _modeBase + N, matching the order ExploreScreen lists them in.
  static const int _modeBase = 4;

  static const int _counselMode = 0;
  static const int _devotionalMode = 2;
  static const int _togetherMode = 5;

  int get _counselIndex => _modeBase + _counselMode;

  /// The bottom bar shows no selection while a mode is open — none of its four
  /// tabs is where you are, and lighting one would be a lie.
  int? get _selectedTab => _index < _modeBase ? _index : null;

  /// The open mode, for the rail, which can show modes as well as tabs.
  int? get _selectedMode => _index >= _modeBase ? _index - _modeBase : null;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.openDevotionalRequested
        .addListener(_onOpenDevotional);
    NotificationService.instance.openCheckInRequested
        .addListener(_onOpenCheckIn);
    NotificationService.instance.openPlanRequested.addListener(_onOpenPlan);
    // The reminder window moves forward one day at a time; keep it current.
    ActionPlanService.instance.refreshReminders();
    NotificationService.instance.openConversationRequested
        .addListener(_onOpenConversationFromPush);
    // Ask once the app is actually on screen, with a reason, rather than
    // firing the one system dialog Android allows before the couple has seen
    // anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationPrimer.maybeShow(context);
    });
  }

  @override
  void dispose() {
    NotificationService.instance.openDevotionalRequested
        .removeListener(_onOpenDevotional);
    NotificationService.instance.openCheckInRequested
        .removeListener(_onOpenCheckIn);
    NotificationService.instance.openPlanRequested
        .removeListener(_onOpenPlan);
    NotificationService.instance.openConversationRequested
        .removeListener(_onOpenConversationFromPush);
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

  /// An Active Steps reminder was tapped: open that plan.
  void _onOpenPlan() {
    final id = NotificationService.instance.openPlanRequested.value;
    if (id == null || !mounted) return;
    NotificationService.instance.openPlanRequested.value = null;
    if (ActionPlanService.instance.byId(id) == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveStepsScreen(
        planId: id,
        onOpenConversation: _openConversation,
      ),
    ));
  }

  /// A message the admin panel placed in a thread, tapped from its push.
  ///
  /// Beta scaffolding. DebugSync has already fetched the message by the time
  /// this runs, so the thread opens with it in place rather than appearing a
  /// second later, which would read as a glitch.
  void _onOpenConversationFromPush() {
    final id = NotificationService.instance.openConversationRequested.value;
    if (id == null || !mounted) return;
    NotificationService.instance.openConversationRequested.value = null;
    _openConversation(id);
  }

  /// The shield in a mode's app bar returns to Home. With no drawer there is
  /// nothing to open, and a mode you cannot leave except with the system back
  /// gesture is a dead end.
  void _goHome() => _goToTab(ExodusBottomNav.home);

  void _openConversationsList() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationsScreen(
        onOpen: _openConversation,
        onNew: _newConversation,
        onDelete: _deleteConversation,
      ),
    ));
  }

  /// Delete at once and offer Undo, rather than asking first. The thread is
  /// held in memory until the offer lapses, so Undo puts back exactly what
  /// was there, in the same place in the list.
  void _deleteConversation(String id) {
    final chat = _chatKey.currentState;
    if (chat == null) return;
    final removed = chat.deleteConversationById(id);
    _homeKey.currentState?.refresh();
    setState(() {});
    if (removed == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted “${_short(removed.conversation.title)}”'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: ExodusTheme.brass,
          onPressed: () {
            _chatKey.currentState
                ?.restoreConversation(removed.conversation, removed.index);
            _homeKey.currentState?.refresh();
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  static String _short(String title) =>
      title.length <= 32 ? title : '${title.substring(0, 30).trimRight()}…';

  void _goToMode(int mode) {
    // One call site rather than one per screen: modes are opened from several
    // places, and instrumenting each would double-count some and miss others.
    const events = {
      1: Events.coachingStart,
      2: Events.devotionalOpen,
      3: Events.studyOpen,
    };
    final event = events[mode];
    if (event != null) Analytics.instance.track(event);
    setState(() => _index = _modeBase + mode);
  }

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
    final expanded = ExodusLayout.isExpanded(context);

    // The stack is built once and handed to whichever frame fits, so folding
    // or unfolding the phone never rebuilds a screen from scratch: a half
    // typed message, a scroll position, a Bible page all survive the change.
    // The GlobalKey on the stack is what makes that true across the two
    // different parent trees below.
    final stack = IndexedStack(
      key: _stackKey,
      index: _index,
      children: [
        // ---- Tabs 0..3 ----
        HomeScreen(
          key: _homeKey,
          onOpenMenu: _goHome,
          onOpenConversation: _openConversation,
          onNewConversation: _newConversation,
          onSeeAll: _openConversationsList,
          onDeleteConversation: _deleteConversation,
        ),
        ExploreScreen(onOpenMode: _goToMode),
        const LibraryScreen(),
        ProfileScreen(onOpenTogether: () => _goToMode(_togetherMode)),

        // ---- Modes, from _modeBase. Order must match ExploreScreen. ----
        ChatScreen(key: _chatKey, onOpenMenu: _goHome),
        CoachingScreen(onOpenMenu: _goHome),
        DevotionalScreen(onOpenMenu: _goHome),
        StudyScreen(
            onOpenMenu: _goHome,
            isActive: _index == _modeBase + 3),
        ConfessionalScreen(onOpenMenu: _goHome),
        TogetherScreen(onOpenMenu: _goHome),
      ],
    );

    final side = ExodusLayout.sideColumnWidth(context);
    return UnfoldReveal(
      child: expanded
          ? _expandedFrame(stack)
          : side > 0
              ? _sideColumnFrame(stack, side)
              : _compactFrame(stack),
    );
  }

  final GlobalKey _stackKey = GlobalKey(debugLabel: 'shell-stack');

  /// Folded: exactly the app as it has always been.
  Widget _compactFrame(Widget stack) {
    return Scaffold(
      key: _scaffoldKey,
      bottomNavigationBar: ExodusBottomNav(
        selected: _selectedTab,
        onSelect: _goToTab,
        onNewChat: _newConversation,
      ),
      body: stack,
    );
  }

  /// Folded Duo: navigation in the status column down the right edge.
  ///
  /// The screens underneath still see the column as a right inset, so their
  /// text stays clear of it, but their backgrounds run under it to the
  /// screen's edge. The rail is transparent and sits on that background,
  /// so there is no strip, no seam, and no bar across the bottom.
  Widget _sideColumnFrame(Widget stack, double width) {
    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          Positioned.fill(child: stack),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: ExodusSideRail(
              width: width,
              selected: _selectedTab,
              onSelect: _goToTab,
              onNewChat: _newConversation,
            ),
          ),
        ],
      ),
    );
  }

  /// Unfolded: the rail down the leading edge. With the room for it (the
  /// inner screen held sideways), Counsel also gains its conversation list
  /// beside the thread — list and message together, the way Mail opens up.
  Widget _expandedFrame(Widget stack) {
    final showList = _index == _counselIndex &&
        ExodusLayout.hasRoomForTwoPanes(context);
    return Scaffold(
      key: _scaffoldKey,
      // One wash of light across rail, list and thread. Each pane paints its
      // own slice of it, so the panes meet without a seam.
      body: BackdropFrame(
        child: Row(
        children: [
          _SoftEdge(
            child: ExodusNavRail(
              selectedTab: _selectedTab,
              selectedMode: _selectedMode,
              onSelectTab: _goToTab,
              onSelectMode: _goToMode,
              onNewChat: _newConversation,
            ),
          ),
          // The list slides in from under the rail rather than appearing, so
          // arriving in Counsel reads as the room opening up.
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.centerLeft,
              widthFactor: showList ? 1 : 0,
              duration: ExodusLayout.reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: _listPaneWidth(context),
                child: _SoftEdge(
                  child: ValueListenableBuilder<int>(
                    valueListenable: StorageService.instance.conversationsRevision,
                    builder: (context, _, __) => ConversationsScreen(
                      embedded: true,
                      selectedId: _chatKey.currentState?.currentId,
                      onOpen: _openConversation,
                      onNew: _newConversation,
                      onDelete: _deleteConversation,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: stack),
        ],
        ),
      ),
    );
  }

  /// A third of the room beside the rail, within limits: wide enough that a
  /// title and two lines of preview read without being cut off, narrow
  /// enough that the thread keeps a comfortable measure.
  static double _listPaneWidth(BuildContext context) {
    final room = MediaQuery.sizeOf(context).width - ExodusNavRail.width;
    return (room * 0.36).clamp(280.0, 360.0);
  }
}

/// A pane's trailing edge as a fall of light rather than a ruled line: a
/// hairline that fades out toward the top and bottom of the screen.
class _SoftEdge extends StatelessWidget {
  final Widget child;
  const _SoftEdge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ExodusTheme.steel.withValues(alpha: 0),
                    ExodusTheme.steel,
                    ExodusTheme.brass.withValues(alpha: 0.22),
                    ExodusTheme.steel,
                    ExodusTheme.steel.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.2, 0.5, 0.8, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
