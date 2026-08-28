import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/coaching_session.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import 'coaching_session_screen.dart';

/// Entry screen for voice coaching: pick a session length, start a live
/// session, and read back past sessions.
class CoachingScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const CoachingScreen({super.key, this.onOpenMenu});

  @override
  State<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends State<CoachingScreen> {
  int _minutes = 10;
  static const _options = [5, 10, 15];

  List<CoachingSession> _past = const [];

  @override
  void initState() {
    super.initState();
    _loadPast();
  }

  void _loadPast() =>
      setState(() => _past = StorageService.instance.loadCoachingSessions());

  Future<void> _start() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoachingSessionScreen(minutes: _minutes),
      ),
    );
    // The session just ended and was saved — pick it up.
    if (mounted) _loadPast();
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
                icon: const Icon(Icons.mic_none_rounded,
                    color: ExodusTheme.porcelain),
                label: const Text(
                  'Start session',
                  style: TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_past.isNotEmpty) ...[
                const SizedBox(height: 40),
                const Text(
                  'PAST SESSIONS',
                  style: TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final s in _past) _sessionTile(s),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(CoachingSession s) {
    final turns = s.transcript.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ExodusTheme.midnight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: turns == 0
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _CoachingTranscriptScreen(session: s))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: ExodusTheme.steel),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq_rounded,
                    color: ExodusTheme.brass, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: const TextStyle(
                              color: ExodusTheme.porcelain, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        turns == 0
                            ? 'No transcript recorded'
                            : '$turns ${turns == 1 ? 'line' : 'lines'}',
                        style: const TextStyle(
                            color: ExodusTheme.ironMist, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (turns > 0)
                  const Icon(Icons.chevron_right,
                      color: ExodusTheme.ironMist, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lengthChip(int m) {
    final selected = m == _minutes;
    return Semantics(
      button: true,
      selected: selected,
      label: '$m minute session',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _minutes = m);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected
                ? ExodusTheme.covenantBlue.withValues(alpha: 0.18)
                : ExodusTheme.midnight,
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
                  color:
                      selected ? ExodusTheme.porcelain : ExodusTheme.ironMist,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text('min',
                  style: TextStyle(color: ExodusTheme.ironMist, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-back view for a finished coaching session.
class _CoachingTranscriptScreen extends StatelessWidget {
  final CoachingSession session;
  const _CoachingTranscriptScreen({required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(session.title)),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          itemCount: session.transcript.length,
          itemBuilder: (_, i) {
            final turn = session.transcript[i];
            final isCoach = turn.speaker == 'exodus';
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCoach ? 'EXODUS' : 'YOU',
                    style: TextStyle(
                      color: isCoach ? ExodusTheme.brass : ExodusTheme.ironMist,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    turn.text,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain,
                        fontSize: 15,
                        height: 1.5),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
