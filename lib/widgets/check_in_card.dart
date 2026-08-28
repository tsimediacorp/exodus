import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/check_in.dart';
import '../services/check_in_service.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// EXODUS coming back to something it remembered.
///
/// Deliberately dismissible and low-pressure: an unprompted question the
/// couple can't wave away stops reading as care very quickly.
class CheckInCard extends StatelessWidget {
  final CheckIn checkIn;

  /// Take it into Counsel and talk it through.
  final VoidCallback onOpen;

  /// Refresh the host after snooze/dismiss.
  final VoidCallback onChanged;

  const CheckInCard({
    super.key,
    required this.checkIn,
    required this.onOpen,
    required this.onChanged,
  });

  IconData get _icon => switch (checkIn.topic) {
        'conflict' => Icons.handshake_outlined,
        'money' => Icons.savings_outlined,
        'intimacy' => Icons.favorite_outline,
        'prayer' => Icons.volunteer_activism_outlined,
        'family' => Icons.family_restroom_outlined,
        'work' => Icons.work_outline,
        'faith' => Icons.auto_stories_outlined,
        'health' => Icons.healing_outlined,
        _ => Icons.chat_bubble_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ExodusShield(size: 22, glow: false),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'EXODUS REMEMBERED',
                  style: TextStyle(
                    color: ExodusTheme.brass,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(_icon, size: 16, color: ExodusTheme.ironMist),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            checkIn.question,
            style: const TextStyle(
              color: ExodusTheme.porcelain,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          if (checkIn.because.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Because you mentioned: ${checkIn.because}',
              style: const TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onOpen();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: ExodusTheme.covenantBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Let's talk",
                      style: TextStyle(
                          color: ExodusTheme.porcelain,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              _secondary(
                label: 'Later',
                onTap: () async {
                  await CheckInService.instance.snooze(checkIn);
                  onChanged();
                },
              ),
              _secondary(
                label: 'Not this',
                onTap: () async {
                  await CheckInService.instance.dismiss(checkIn);
                  onChanged();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _secondary({required String label, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}
