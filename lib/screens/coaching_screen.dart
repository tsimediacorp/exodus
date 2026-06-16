import 'package:flutter/material.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import 'coaching_session_screen.dart';

/// Entry screen for voice coaching: pick a session length, then start a live
/// session. (Saved-session history can layer in here later.)
class CoachingScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const CoachingScreen({super.key, this.onOpenMenu});

  @override
  State<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends State<CoachingScreen> {
  int _minutes = 10;
  static const _options = [5, 10, 15];

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoachingSessionScreen(minutes: _minutes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coaching'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Center(child: ExodusShield(size: 72)),
              const SizedBox(height: 24),
              const Text(
                'Live coaching, together.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sit together, put the phone between you, and talk it through. '
                'EXODUS listens and coaches you in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ExodusTheme.ironMist,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Session length',
                style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final m in _options) ...[
                    Expanded(child: _lengthChip(m)),
                    if (m != _options.last) const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 36),
              FilledButton.icon(
                onPressed: _start,
                style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.covenantBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.mic_none_rounded, color: ExodusTheme.porcelain),
                label: const Text(
                  'Start session',
                  style: TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lengthChip(int m) {
    final selected = m == _minutes;
    return GestureDetector(
      onTap: () => setState(() => _minutes = m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? ExodusTheme.covenantBlue.withValues(alpha: 0.18) : ExodusTheme.midnight,
          border: Border.all(
            color: selected ? ExodusTheme.covenantGlow : ExodusTheme.steel,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$m',
              style: TextStyle(
                color: selected ? ExodusTheme.porcelain : ExodusTheme.ironMist,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text('min', style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
