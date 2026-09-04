import 'package:flutter/material.dart';
import '../services/progress.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// What EXODUS does while it is thinking.
///
/// Replies take upwards of thirty seconds. Three bouncing dots make that feel
/// like a machine stalling; a slow breath makes it feel like someone
/// considering. The shield expands and brightens on a 3.4s cycle — near the
/// pace of resting breath, and deliberately far slower than a loading
/// animation, because the point is patience rather than progress.
///
/// This is the one thing in the app allowed to loop, and only because it stops
/// the instant the first token lands. A reverent app that twitches
/// continuously stops feeling calm.
class ThinkingPresence extends StatefulWidget {
  /// Narration of what is happening ("Searching the scriptures…").
  final ProgressController? progress;

  /// When the request started, for the elapsed count.
  final DateTime startTime;

  const ThinkingPresence({
    super.key,
    required this.startTime,
    this.progress,
  });

  @override
  State<ThinkingPresence> createState() => _ThinkingPresenceState();
}

class _ThinkingPresenceState extends State<ThinkingPresence>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);
    // The sweep is faster than the breath and not a multiple of it, so the two
    // never lock into a visible pulse together.
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    _sweep.dispose();
    super.dispose();
  }

  String _elapsed() {
    final s = DateTime.now().difference(widget.startTime).inSeconds;
    return s < 1 ? '' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _breath,
            builder: (_, child) {
              // Curves.easeInOut, so the turn at each end of the breath is
              // soft rather than a bounce.
              final t = Curves.easeInOut.transform(_breath.value);
              return Opacity(
                opacity: 0.55 + t * 0.45,
                child: Transform.scale(scale: 1 + t * 0.08, child: child),
              );
            },
            child: const ExodusShield(size: 22, glow: false),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.progress != null)
                  ValueListenableBuilder<ProgressSnapshot?>(
                    valueListenable: widget.progress!,
                    builder: (_, snapshot, __) => Text(
                      snapshot?.message.isNotEmpty == true
                          ? snapshot!.message
                          : 'Thinking…',
                      style: const TextStyle(
                        fontFamily: ExodusTheme.serif,
                        color: ExodusTheme.ironMist,
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 9),
                // A sweep of light rather than a filling bar: nothing here
                // knows how far along it is, and a progress bar that invents a
                // position is a small lie told once a minute.
                AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, __) => SizedBox(
                    height: 2,
                    width: 132,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: Stack(
                        children: [
                          Container(
                              color: ExodusTheme.brass.withValues(alpha: 0.14)),
                          Align(
                            alignment: Alignment(-1 + _sweep.value * 2.6, 0),
                            child: Container(
                              width: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  ExodusTheme.brass.withValues(alpha: 0),
                                  ExodusTheme.brass,
                                  ExodusTheme.brass.withValues(alpha: 0),
                                ]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _sweep,
            builder: (_, __) => Text(
              _elapsed(),
              style: const TextStyle(
                color: ExodusTheme.steel,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
