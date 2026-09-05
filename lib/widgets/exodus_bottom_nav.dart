import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/exodus_theme.dart';

/// The five-slot bottom bar: Home, Explore, New Chat, Library, Profile.
///
/// New Chat is the raised brass button in the middle and is an ACTION, not a
/// tab — it never becomes the selected slot, because starting a conversation
/// takes you to Counsel rather than to a fifth place you can come back to.
/// [selected] is null while a mode opened from the drawer is on screen, so the
/// bar honestly shows that none of its tabs is where you are.
class ExodusBottomNav extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onNewChat;

  const ExodusBottomNav({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNewChat,
  });

  static const home = 0;
  static const explore = 1;
  static const library = 2;
  static const profile = 3;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          // A five-slot bar has nowhere to grow. Beyond ~1.2 the labels push
          // the raised button out of its own row; clamping keeps the bar
          // usable at large type instead of overflowing, and the destinations
          // it leads to all honour the user's real setting.
          maxScaleFactor: 1.2,
          child: SizedBox(
            height: 74,
            child: Row(
            children: [
              _tab(home, Icons.home_rounded, Icons.home_outlined, 'Home'),
              _tab(explore, Icons.explore_rounded, Icons.explore_outlined,
                  'Explore'),
              Expanded(child: _newChat()),
              _tab(library, Icons.menu_book_rounded, Icons.menu_book_outlined,
                  'Library'),
              _tab(profile, Icons.person_rounded, Icons.person_outline_rounded,
                  'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData active, IconData idle, String label) {
    final isOn = selected == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isOn,
        label: label,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(index);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isOn ? active : idle,
                  size: 22,
                  color: isOn ? ExodusTheme.brass : ExodusTheme.ironMist),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: isOn ? ExodusTheme.brass : ExodusTheme.ironMist,
                    fontSize: 11,
                    fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                  )),
              const SizedBox(height: 3),
              // The underline marks the tab you are on without moving anything
              // else, so the row does not shift as you switch.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: 2,
                width: isOn ? 20 : 0,
                decoration: BoxDecoration(
                  color: ExodusTheme.brass,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _newChat() {
    return Semantics(
      button: true,
      label: 'New conversation',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.mediumImpact();
              onNewChat();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ExodusTheme.obsidian,
                border: Border.all(color: ExodusTheme.brass, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: ExodusTheme.brass.withValues(alpha: 0.28),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  size: 25, color: ExodusTheme.brass),
            ),
          ),
          const SizedBox(height: 4),
          const Text('New Chat',
              maxLines: 1,
              style: TextStyle(color: ExodusTheme.ironMist, fontSize: 11)),
        ],
      ),
    );
  }
}
