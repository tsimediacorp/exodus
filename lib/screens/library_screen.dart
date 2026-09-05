import 'package:flutter/material.dart';

import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/page_backdrop.dart';
import 'bible_screen.dart';
import 'journeys_screen.dart';
import 'letters_screen.dart';
import 'memory_screen.dart';
import 'saved_verses_screen.dart';
import 'study_history_screen.dart';

/// Everything EXODUS has written or kept.
///
/// These all existed already, buried in a collapsed drawer section most people
/// never opened. Nothing here is new behaviour — it is the same screens given
/// a place you can find them.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <({IconData icon, String name, String blurb, Widget page})>[
      (
        icon: Icons.menu_book_rounded,
        name: 'Bible',
        blurb: 'Read in KJV, BSB, ASV or YLT.',
        page: const BibleScreen(),
      ),
      (
        icon: Icons.bookmark_rounded,
        name: 'Saved verses',
        blurb: 'Passages you kept.',
        page: const SavedVersesScreen(),
      ),
      (
        icon: Icons.school_rounded,
        name: 'Past exercises',
        blurb: 'Bible studies you have worked through.',
        page: const StudyHistoryScreen(),
      ),
      (
        icon: Icons.route_rounded,
        name: 'Journeys',
        blurb: 'Guided paths through a season.',
        page: const JourneysScreen(),
      ),
      (
        icon: Icons.mail_outline_rounded,
        name: 'Weekly letter',
        blurb: 'What EXODUS wrote to you both.',
        page: const LettersScreen(),
      ),
      (
        icon: Icons.psychology_outlined,
        name: 'Memory',
        blurb: 'What EXODUS remembers, and what to forget.',
        page: const MemoryScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              const Text('Library',
                  style: TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 6),
              const Text('Everything kept and written.',
                  style: TextStyle(color: ExodusTheme.ironMist, fontSize: 15)),
              const SizedBox(height: 22),
              Arrival(
                step: const Duration(milliseconds: 70),
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _row(context, e.icon, e.name, e.blurb, e.page),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String name, String blurb,
      Widget page) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.72),
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: ExodusTheme.brass),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 3),
                  Text(blurb,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: ExodusTheme.ironMist),
          ],
        ),
      ),
    );
  }
}
