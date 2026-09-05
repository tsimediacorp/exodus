import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/arrival.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/page_backdrop.dart';
import 'settings_screen.dart';

/// The account and the state of things.
///
/// Deliberately thin: EXODUS has no profile to speak of beyond what is on the
/// device, and inventing an avatar, a display name and a stats dashboard would
/// be filling a tab rather than serving anyone. It shows what is true —
/// how much is stored here — and the way through to Settings and Together.
class ProfileScreen extends StatelessWidget {
  /// Opens the Together mode, where pairing and the account live.
  final VoidCallback onOpenTogether;

  const ProfileScreen({super.key, required this.onOpenTogether});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService.instance;
    final conversations = storage.loadConversations();
    final verses = storage.loadSavedVerses().length;
    final exercises = storage.loadStudyExercises().length;

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Arrival(
                step: const Duration(milliseconds: 80),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: ExodusShield(size: 64)),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text('Walking in His design.',
                        style: TextStyle(
                          fontFamily: ExodusTheme.serif,
                          color: ExodusTheme.parchment,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _stat('${conversations.length}', 'conversations'),
                      const SizedBox(width: 10),
                      _stat('$verses', 'verses kept'),
                      const SizedBox(width: 10),
                      _stat('$exercises', 'exercises'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _row(context, Icons.favorite_rounded, 'Together',
                      'Pair with your spouse', onOpenTogether),
                  const SizedBox(height: 10),
                  _row(
                    context,
                    Icons.settings_outlined,
                    'Settings',
                    'Model, check-ins, notifications',
                    () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: ExodusTheme.midnight.withValues(alpha: 0.72),
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.brass,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ExodusTheme.ironMist, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String name, String blurb,
      VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
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
