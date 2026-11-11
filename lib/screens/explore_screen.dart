import 'package:flutter/material.dart';

import '../layout/exodus_layout.dart';
import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/page_backdrop.dart';

/// Everything EXODUS can do, in one place.
///
/// The modes used to live only in the drawer, which meant they were invisible
/// unless you went looking for them. This is now the only way in, and the one
/// place that says what each mode is FOR — a grid of unexplained icons is a
/// menu, not an invitation.
class ExploreScreen extends StatelessWidget {
  /// Selects a mode by its index in the shell's stack.
  final ValueChanged<int> onOpenMode;

  const ExploreScreen({super.key, required this.onOpenMode});

  /// Mode index, icon, name, and the one line that says what it is FOR — a
  /// grid of unexplained icons is a menu, not an invitation.
  static const _entries = [
    (
      mode: 0,
      icon: Icons.menu_book_rounded,
      name: 'Counsel',
      blurb:
          'Ask anything. Scripture-first answers for what you are actually facing.'
    ),
    (
      mode: 1,
      icon: Icons.spatial_audio_off_rounded,
      name: 'Coaching',
      blurb: 'A live spoken session, out loud, together.'
    ),
    (
      mode: 2,
      icon: Icons.wb_sunny_rounded,
      name: 'Devotional',
      blurb: 'A word for today, built around the goal you are working on.'
    ),
    (
      mode: 3,
      icon: Icons.school_rounded,
      name: 'Bible Study',
      blurb: 'An exercise to work through — not a passage to skim.'
    ),
    (
      mode: 4,
      icon: Icons.lock_rounded,
      name: 'Confessional',
      blurb: 'Say it plainly. It stays on this device, and you are prayed for.'
    ),
    (
      mode: 5,
      icon: Icons.favorite_rounded,
      name: 'Together',
      blurb: 'Pair with your spouse: a shared thread and a prayer wall.'
    ),
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
                  style: TextStyle(color: ExodusTheme.ironMist, fontSize: 15)),
              const SizedBox(height: 22),
              if (ExodusLayout.isExpanded(context))
                // Unfolded: two columns, three rows. An even column count
                // divides cleanly about the fold, as Apple recommends for
                // grids on this screen.
                Arrival(
                  step: const Duration(milliseconds: 70),
                  children: [
                    for (var row = 0; row < _entries.length; row += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = row; i < row + 2; i++) ...[
                                if (i > row)
                                  const SizedBox(
                                      width: ExodusLayout.centreGutter),
                                Expanded(
                                  child: i < _entries.length
                                      ? _card(
                                          _entries[i].mode,
                                          _entries[i].icon,
                                          _entries[i].name,
                                          _entries[i].blurb,
                                          tall: true)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              else
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

  Widget _card(int mode, IconData icon, String name, String blurb,
      {bool tall = false}) {
    if (tall) return _tallCard(mode, icon, name, blurb);
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

  /// The unfolded card: icon above, name and line below, with a brass
  /// glow that rises under the finger. Taller and quieter than the folded
  /// row, because in a grid the cards are read as a set, not a list.
  Widget _tallCard(int mode, IconData icon, String name, String blurb) {
    return _GlowCard(
      onTap: () => onOpenMode(mode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                ExodusTheme.brass.withValues(alpha: 0.22),
                ExodusTheme.slate,
              ]),
              border:
                  Border.all(color: ExodusTheme.brass.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 22, color: ExodusTheme.brass),
          ),
          const SizedBox(height: 16),
          Text(name,
              style: const TextStyle(
                fontFamily: ExodusTheme.serif,
                color: ExodusTheme.parchment,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 6),
          Text(blurb,
              style: const TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }
}

/// A card that warms when pressed: the brass glow rises from underneath and
/// the card lifts a fraction, then settles back when released.
class _GlowCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _GlowCard({required this.onTap, required this.child});

  @override
  State<_GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<_GlowCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.975 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ExodusTheme.midnight.withValues(alpha: 0.85),
                  ExodusTheme.obsidian.withValues(alpha: 0.85),
                ],
              ),
              border: Border.all(
                  color: _down
                      ? ExodusTheme.brass.withValues(alpha: 0.6)
                      : ExodusTheme.steel),
              boxShadow: [
                BoxShadow(
                  color: ExodusTheme.brass.withValues(alpha: _down ? 0.22 : 0),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
