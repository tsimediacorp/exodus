import 'dart:async';

import 'package:flutter/material.dart';

import '../services/progress.dart';
import '../theme/exodus_theme.dart';

/// Live status for a long-running operation: what EXODUS is doing right now,
/// how long it has been at it, which step it's on, and whether it is retrying.
///
/// Replaces the bare spinner-plus-static-label pattern. The elapsed clock is
/// the part that matters most — a spinner with no clock is indistinguishable
/// from a hang, and the wait here can legitimately reach ~90 seconds.
class ProgressView extends StatefulWidget {
  final ProgressController controller;

  /// Shown when nothing is in flight (usually nothing at all).
  final Widget? idle;

  /// Vertical padding around the block.
  final double padding;

  /// Optional cancel affordance — a wait the user can't escape is its own
  /// kind of dead end.
  final VoidCallback? onCancel;

  const ProgressView({
    super.key,
    required this.controller,
    this.idle,
    this.padding = 40,
    this.onCancel,
  });

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Drives the elapsed readout. One second is enough to feel alive without
    // rebuilding needlessly.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.value != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsedLabel(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgressSnapshot?>(
      valueListenable: widget.controller,
      builder: (context, snap, _) {
        if (snap == null) return widget.idle ?? const SizedBox.shrink();

        final elapsed = DateTime.now().difference(snap.startedAt);
        // Long-running is normal here (retries plus a 30s timeout), so say so
        // rather than letting the user conclude it has died.
        final slow = elapsed.inSeconds >= 20;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: widget.padding, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: snap.fraction,
                  backgroundColor: ExodusTheme.steel,
                  valueColor: AlwaysStoppedAnimation(
                      snap.isRetrying ? ExodusTheme.crimson : ExodusTheme.brass),
                ),
              ),
              const SizedBox(height: 18),
              // The live stage. AnimatedSwitcher so stage changes read as
              // motion — visible evidence something is happening.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Text(
                  snap.message,
                  key: ValueKey(snap.message),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _detail(snap, elapsed),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: snap.isRetrying
                      ? ExodusTheme.crimson
                      : ExodusTheme.ironMist,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              if (slow) ...[
                const SizedBox(height: 10),
                const Text(
                  'This can take a minute on a slow connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ExodusTheme.ironMist, fontSize: 11),
                ),
              ],
              if (widget.onCancel != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: ExodusTheme.ironMist,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The supporting line: step counter, retry notice, and elapsed time.
  String _detail(ProgressSnapshot snap, Duration elapsed) {
    final parts = <String>[];
    if (snap.hasSteps) parts.add('Step ${snap.step} of ${snap.totalSteps}');
    if (snap.isRetrying) {
      parts.add('Retrying — attempt ${snap.attempt} of ${snap.maxAttempts}');
    }
    parts.add(_elapsedLabel(elapsed));
    return parts.join(' · ');
  }
}

/// The same status as a compact single line, for placing inside a bar, a
/// button row, or above a list where a full block would be too heavy.
class ProgressStrip extends StatefulWidget {
  final ProgressController controller;
  const ProgressStrip({super.key, required this.controller});

  @override
  State<ProgressStrip> createState() => _ProgressStripState();
}

class _ProgressStripState extends State<ProgressStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.value != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgressSnapshot?>(
      valueListenable: widget.controller,
      builder: (context, snap, _) {
        if (snap == null) return const SizedBox.shrink();
        final elapsed = DateTime.now().difference(snap.startedAt);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ExodusTheme.midnight,
            border: Border.all(
                color: snap.isRetrying
                    ? ExodusTheme.crimson.withValues(alpha: 0.5)
                    : ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: snap.fraction,
                  backgroundColor: ExodusTheme.steel,
                  valueColor: AlwaysStoppedAnimation(
                      snap.isRetrying ? ExodusTheme.crimson : ExodusTheme.brass),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    snap.message,
                    key: ValueKey(snap.message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                elapsed.inSeconds < 60
                    ? '${elapsed.inSeconds}s'
                    : '${elapsed.inMinutes}m',
                style: const TextStyle(
                    color: ExodusTheme.ironMist,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        );
      },
    );
  }
}
