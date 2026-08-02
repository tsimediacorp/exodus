import 'dart:async';
import 'package:flutter/material.dart';
import '../models/coaching_session.dart';
import '../services/memory_service.dart';
import '../services/realtime_voice_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';

/// The live coaching session: connects to the realtime coach, runs a countdown
/// for the chosen length, shows who's speaking + live captions, and saves a
/// transcript when it ends.
class CoachingSessionScreen extends StatefulWidget {
  final int minutes;
  const CoachingSessionScreen({super.key, required this.minutes});

  @override
  State<CoachingSessionScreen> createState() => _CoachingSessionScreenState();
}

class _CoachingSessionScreenState extends State<CoachingSessionScreen> {
  late final CoachingSession _session;
  late final RealtimeVoiceService _voice;
  Timer? _ticker;
  late int _remaining; // seconds
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _session = CoachingSession.start(widget.minutes);
    _remaining = widget.minutes * 60;
    _voice = RealtimeVoiceService(
      onTurn: (t) => _session.transcript.add(t),
    );
    _voice.state.addListener(_onStateChanged);
    _connect();
  }

  Future<void> _connect() async {
    await _voice.connect(minutes: widget.minutes);
    if (_voice.state.value == VoiceState.error) return;
    // The greeting is sent automatically once the data channel opens.
    _startTimer();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _startTimer() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _end();
    });
  }

  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    _ticker?.cancel();
    await _voice.hangUp();
    _session.endedAt = DateTime.now();
    await StorageService.instance.addCoachingSession(_session);
    // Distill durable memory from the session (fire-and-forget, best-effort).
    // Detached: it outlives this screen, and closes its own http client when
    // done — an inline MemoryService() leaked one client per session.
    if (_session.transcript.isNotEmpty) {
      unawaited(MemoryService.captureCoachingDetached(_session.transcript));
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Confirm before killing a live session — it's a single tap next to the
  /// clock, and there's no way to resume once it ends.
  Future<void> _confirmEnd() async {
    if (_ended) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('End this session?'),
        content: const Text(
            'The session will finish and be saved to your history. You can\'t '
            'resume it afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End session',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed == true) await _end();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _voice.state.removeListener(_onStateChanged);
    _voice.dispose();
    super.dispose();
  }

  String get _clock {
    final m = (_remaining ~/ 60).toString();
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  ({String label, Color color}) get _status {
    switch (_voice.state.value) {
      case VoiceState.connecting:
        return (label: 'Connecting…', color: ExodusTheme.ironMist);
      case VoiceState.speaking:
        return (label: 'EXODUS is speaking', color: ExodusTheme.brass);
      case VoiceState.listening:
      case VoiceState.connected:
        return (label: 'Listening…', color: ExodusTheme.covenantGlow);
      case VoiceState.error:
        return (label: 'Connection error', color: ExodusTheme.crimson);
      default:
        return (label: '—', color: ExodusTheme.ironMist);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isError = _voice.state.value == VoiceState.error;
    final progress =
        1 - (_remaining / (widget.minutes * 60)).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _confirmEnd,
                  icon: const Icon(Icons.close, color: ExodusTheme.ironMist, size: 18),
                  label: const Text('End', style: TextStyle(color: ExodusTheme.ironMist)),
                ),
              ),
              const Spacer(),
              // The ring grows with the text scale so the clock inside it
              // doesn't clip when the user has large type turned on.
              Builder(builder: (context) {
                final scale =
                    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
                final ring = 220.0 * scale;
                return SizedBox(
                  width: ring,
                  height: ring,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: ring,
                        height: ring,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          backgroundColor: ExodusTheme.steel,
                          valueColor: AlwaysStoppedAnimation(_status.color),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _clock,
                            style: const TextStyle(
                              color: ExodusTheme.porcelain,
                              fontSize: 44,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(_status.label,
                              style: TextStyle(
                                  color: _status.color, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 36),
              if (isError)
                Text(
                  _voice.error.value ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ExodusTheme.crimson, fontSize: 13),
                )
              else
                ValueListenableBuilder<String>(
                  valueListenable: _voice.liveCaption,
                  builder: (_, caption, __) => Text(
                    caption,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ExodusTheme.ironMist,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              const Spacer(),
              if (isError)
                FilledButton(
                  onPressed: _end,
                  style: FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
                  child: const Text('Close', style: TextStyle(color: ExodusTheme.porcelain)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
