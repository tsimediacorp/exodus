import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/remote_config.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/page_backdrop.dart';

/// Shown instead of the app when this build is below the minimum.
///
/// No dismiss, no back: that is the point of a hard gate. But it always gives
/// a way forward — if the panel has no update link configured the button is
/// replaced with the reason, because a screen that blocks the app and offers
/// nothing is a brick.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = RemoteConfig.instance;
    final url = config.updateUrl;

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: PageBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExodusShield(size: 62),
                  const SizedBox(height: 28),
                  const Text(
                    'Time to update',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ExodusTheme.serif,
                      color: ExodusTheme.parchment,
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    config.updateMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ExodusTheme.ironMist,
                      fontSize: 15.5,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (url.isEmpty)
                    const Text(
                      'No update link has been set yet. Ask the EXODUS team '
                      'for the latest build.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: ExodusTheme.brass, fontSize: 14, height: 1.55),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ExodusTheme.brass,
                          foregroundColor: ExodusTheme.obsidian,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Get the new build',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
