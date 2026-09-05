import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// Asks for notification permission, with a reason, once.
///
/// Android gives an app ONE chance at the system dialog: dismiss it and the
/// OS will not show it again, and the only route back is Settings. Firing it
/// cold at startup — which is what the app did — spends that one chance before
/// the couple has any idea what EXODUS would notify them about, and a reflexive
/// "no thanks" permanently disables the thing that lets EXODUS follow up.
///
/// So this explains first and asks second, and only the couple saying yes
/// reaches the system prompt. Declining here costs nothing: the OS dialog is
/// never spent, and it can be asked for again from Settings.
class NotificationPrimer extends StatelessWidget {
  const NotificationPrimer({super.key});

  /// Show it if it is worth showing: permission not already granted, and not
  /// already asked. Returns whether permission ended up granted.
  static Future<bool> maybeShow(BuildContext context) async {
    final service = NotificationService.instance;
    final storage = StorageService.instance;

    final already = await service.areEnabled();
    if (already == true) return true;
    // Asked once and declined — never nag. Settings has the way back.
    if (storage.notificationPrimerShown) return false;
    if (!context.mounted) return false;

    final accepted = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => const NotificationPrimer(),
        ) ??
        false;

    await storage.setNotificationPrimerShown(true);
    if (!accepted) return false;

    final granted = await service.requestPermission();
    if (granted) await service.scheduleDailyDevotional();
    return granted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ExodusTheme.midnight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: ExodusShield(size: 52)),
              const SizedBox(height: 20),
              const Text(
                'Let EXODUS come back to you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.parchment,
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'When you tell EXODUS something that matters — a struggle, a '
                'decision you are weighing — it will ask you about it later, '
                'unprompted, in the evening. It also sends the morning '
                'devotional.\n\nA few a week at most. Never a marketing '
                'message.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: ExodusTheme.brass,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Allow notifications',
                      style: TextStyle(
                        color: ExodusTheme.obsidian,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      )),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now',
                    style:
                        TextStyle(color: ExodusTheme.ironMist, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
