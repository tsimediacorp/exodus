import 'package:flutter/material.dart';

import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/page_backdrop.dart';

/// Everything EXODUS can do, in one place.
///
/// The modes have always existed but only ever from the drawer, which meant
/// they were invisible unless you went looking. This is the same set of
/// destinations laid out to be browsed — the drawer keeps working exactly as
/// it did, and both routes select the same live screen.
class ExploreScreen extends StatelessWidget {
  final VoidCallback? onOpenMenu;

  /// Selects a mode by its index in the shell's stack.
  final ValueChanged<int> onOpenMode;

  const ExploreScreen({
    super.key,
    this.onOpenMenu,
    required this.onOpenMode,
  });

  /// Mode index, icon, name, and the one line that says what it is FOR — a
  /// grid of unexplained icons is a menu, not an invitation.
  static const _entries = [
    (mode: 0, icon: Icons.menu_book_rounded, name: 'Counsel',
      blurb: 'Ask anything. Scripture-first answers for what you are actually facing.'),
    (mode: 1, icon: Icons.spatial_audio_off_rounded, name: 'Coaching',
      blurb: 'A live spoken session, out loud, together.'),
    (mode: 2, icon: Icons.wb_sunny_rounded, name: 'Devotional',
      blurb: 'A word for today, built around the goal you are working on.'),
    (mode: 3, icon: Icons.school_rounded, name: 'Bible Study',
      blurb: 'An exercise to work through — not a passage to skim.'),
    (mode: 4, icon: Icons.lock_rounded, name: 'Confessional',
      blurb: 'Say it plainly. It stays on this device, and you are prayed for.'),
    (mode: 5, icon: Icons.favorite_rounded, name: 'Together',
      blurb: 'Pair with your spouse: a shared thread and a prayer wall.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('Explore',
                  style: TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 6),
              const Text('Six ways to walk this out.',
                  style:
                      TextStyle(color: ExodusTheme.ironMist, fontSize: 15)),
              const SizedBox(height: 22),
              Arrival(
                step: const Duration(milliseconds: 70),
                children: [
                  for (final e in _entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _card(e.mode, e.icon, e.name, e.blurb),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int mode, IconData icon, String name, String blurb) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onOpenMode(mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.72),
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ExodusTheme.slate,
                border: Border.all(
                    color: ExodusTheme.brass.withValues(alpha: 0.30)),
              ),
              child: Icon(icon, size: 21, color: ExodusTheme.brass),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                        fontFamily: ExodusTheme.serif,
                        color: ExodusTheme.parchment,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Text(blurb,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist,
                          fontSize: 13,
                          height: 1.45)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 6, top: 12),
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: ExodusTheme.ironMist),
            ),
          ],
        ),
      ),
    );
  }
}
