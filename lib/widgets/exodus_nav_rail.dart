import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/exodus_layout.dart';
import '../theme/exodus_theme.dart';
import 'exodus_bottom_nav.dart';
import 'exodus_shield.dart';

/// The unfolded screen's navigation: a rail down the leading edge.
///
/// It carries the same four places as [ExodusBottomNav] plus New Chat, in
/// the same order, so nothing is learned twice — folding the phone moves the
/// destinations, it does not change them. What the extra room buys is the
/// six modes, listed underneath. Folded, they live one level down in
/// Explore; unfolded there is space to keep them one tap away, which is the
/// "one extra level" Apple suggests the inner screen should show.
///
/// Selection is a single brass lamp that slides between rows rather than a
/// highlight that blinks from one to the next, so the eye follows where you
/// went instead of hunting for it.
class ExodusNavRail extends StatelessWidget {
  /// Selected tab (0..3), or null while a mode is open.
  final int? selectedTab;

  /// Selected mode (0..5), or null while a tab is open.
  final int? selectedMode;

  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onSelectMode;
  final VoidCallback onNewChat;

  const ExodusNavRail({
    super.key,
    required this.selectedTab,
    required this.selectedMode,
    required this.onSelectTab,
    required this.onSelectMode,
    required this.onNewChat,
  });

  static const double width = 92;

  /// Row height when there is room; rows shrink toward [_minRowHeight] on a
  /// short screen (the inner screen held sideways is only 669pt tall) so
  /// every destination stays visible instead of scrolling off the bottom.
  static const double _maxRowHeight = 58;
  static const double _minRowHeight = 44;

  /// Everything on the rail that is not a row: shield, New Chat, rule, gaps.
  static const double _fixedHeight = 14 + 35 + 18 + 76 + 18 + 30 + 12;

  static const _tabs = [
    (
      index: ExodusBottomNav.home,
      on: Icons.home_rounded,
      off: Icons.home_outlined,
      label: 'Home'
    ),
    (
      index: ExodusBottomNav.explore,
      on: Icons.explore_rounded,
      off: Icons.explore_outlined,
      label: 'Explore'
    ),
    (
      index: ExodusBottomNav.library,
      on: Icons.menu_book_rounded,
      off: Icons.menu_book_outlined,
      label: 'Library'
    ),
    (
      index: ExodusBottomNav.profile,
      on: Icons.person_rounded,
      off: Icons.person_outline_rounded,
      label: 'Profile'
    ),
  ];

  /// Same order and icons as ExploreScreen, so the two never disagree.
  static const modes = [
    (icon: Icons.forum_rounded, label: 'Counsel'),
    (icon: Icons.spatial_audio_off_rounded, label: 'Coaching'),
    (icon: Icons.wb_sunny_rounded, label: 'Devotional'),
    (icon: Icons.school_rounded, label: 'Study'),
    (icon: Icons.lock_rounded, label: 'Confess'),
    (icon: Icons.favorite_rounded, label: 'Together'),
  ];

  @override
  Widget build(BuildContext context) {
    final reduce = ExodusLayout.reduceMotion(context);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ExodusTheme.midnight, ExodusTheme.obsidian],
        ),
        border: Border(right: BorderSide(color: ExodusTheme.steel)),
      ),
      child: SafeArea(
        right: false,
        child: MediaQuery.withClampedTextScaling(
          // Same reasoning as the bottom bar: a fixed-width rail has nowhere
          // to grow, and the screens it leads to honour the real setting.
          maxScaleFactor: 1.2,
          child: LayoutBuilder(builder: (context, constraints) {
            final rowCount = _tabs.length + modes.length;
            final rowHeight =
                ((constraints.maxHeight - _fixedHeight) / rowCount)
                    .clamp(_minRowHeight, _maxRowHeight)
                    .toDouble();
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      const ExodusShield(size: 30),
                      const SizedBox(height: 18),
                      _NewChatButton(onTap: onNewChat),
                      const SizedBox(height: 18),
                      _Group(
                        selected: selectedTab,
                        reduceMotion: reduce,
                        rowHeight: rowHeight,
                        children: [
                          for (final t in _tabs)
                            _RailItem(
                              icon: selectedTab == t.index ? t.on : t.off,
                              label: t.label,
                              selected: selectedTab == t.index,
                              height: rowHeight,
                              onTap: () => onSelectTab(t.index),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const _Rule(),
                      const SizedBox(height: 10),
                      _Group(
                        selected: selectedMode,
                        reduceMotion: reduce,
                        rowHeight: rowHeight,
                        children: [
                          for (var m = 0; m < modes.length; m++)
                            _RailItem(
                              icon: modes[m].icon,
                              label: modes[m].label,
                              selected: selectedMode == m,
                              height: rowHeight,
                              compact: true,
                              onTap: () => onSelectMode(m),
                            ),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// A run of rail rows sharing one sliding lamp.
class _Group extends StatelessWidget {
  final int? selected;
  final bool reduceMotion;
  final double rowHeight;
  final List<Widget> children;

  const _Group({
    required this.selected,
    required this.reduceMotion,
    required this.rowHeight,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    return Stack(
      children: [
        // The lamp. It slides on a slightly underdamped curve so it arrives
        // with a little settle, like something with weight.
        AnimatedPositioned(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          top: (sel ?? 0) * rowHeight + 6,
          left: 12,
          right: 12,
          height: rowHeight - 12,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: sel == null ? 0 : 1,
            child: const _Lamp(),
          ),
        ),
        Column(children: children),
      ],
    );
  }
}

class _Lamp extends StatelessWidget {
  const _Lamp();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // A brass filament on the leading edge, the brightest point.
        Container(
          width: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: ExodusTheme.brassGlow,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: ExodusTheme.brass.withValues(alpha: 0.7),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  ExodusTheme.brass.withValues(alpha: 0.20),
                  ExodusTheme.brass.withValues(alpha: 0.06),
                ],
              ),
              border:
                  Border.all(color: ExodusTheme.brass.withValues(alpha: 0.28)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final double height;
  final bool compact;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.height,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? ExodusTheme.brassGlow : ExodusTheme.ironMist;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(icon, size: compact ? 20 : 23, color: color),
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 10.5 : 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.2,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          ExodusTheme.brass.withValues(alpha: 0),
          ExodusTheme.brass.withValues(alpha: 0.5),
          ExodusTheme.brass.withValues(alpha: 0),
        ]),
      ),
    );
  }
}

/// New Chat, the same raised brass ring as on the bottom bar, with a slow
/// breathing glow — the one thing on the rail that is an invitation rather
/// than a place.
class _NewChatButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NewChatButton({required this.onTap});

  @override
  State<_NewChatButton> createState() => _NewChatButtonState();
}

class _NewChatButtonState extends State<_NewChatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ExodusLayout.reduceMotion(context)) {
      _breath.stop();
      _breath.value = 0.5;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New conversation',
      excludeSemantics: true,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _breath,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_breath.value);
              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ExodusTheme.obsidian,
                  border: Border.all(color: ExodusTheme.brass, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          ExodusTheme.brass.withValues(alpha: 0.18 + 0.20 * t),
                      blurRadius: 12 + 10 * t,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              },
              child: const Icon(Icons.add_rounded,
                  size: 26, color: ExodusTheme.brass),
            ),
          ),
          const SizedBox(height: 5),
          const Text('New Chat',
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 10.5)),
        ],
      ),
    );
  }
}
