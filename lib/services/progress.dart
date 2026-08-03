import 'package:flutter/foundation.dart';

/// One moment in a long-running operation.
@immutable
class ProgressSnapshot {
  /// What is happening right now, in plain language.
  final String message;

  /// 1-based step and total, when the work has countable stages.
  final int? step;
  final int? totalSteps;

  /// Retry attempt, surfaced so a slow retry reads as "still working" rather
  /// than "frozen". 1 = first try.
  final int attempt;
  final int maxAttempts;

  /// When the whole operation began — drives the elapsed-time readout.
  final DateTime startedAt;

  const ProgressSnapshot({
    required this.message,
    required this.startedAt,
    this.step,
    this.totalSteps,
    this.attempt = 1,
    this.maxAttempts = 1,
  });

  bool get isRetrying => attempt > 1;
  bool get hasSteps => step != null && totalSteps != null && totalSteps! > 1;

  /// Fraction complete when the work has countable steps, else null so the
  /// indicator stays indeterminate rather than inventing a percentage.
  double? get fraction =>
      hasSteps ? (step! - 1).clamp(0, totalSteps!) / totalSteps! : null;
}

/// Carries live status from a service to whatever is showing it.
///
/// Services own one of these and call [stage] as they actually move through
/// work — reaching the provider, retrying a dropped connection, receiving a
/// reply. Nothing here is on a timer: if the UI says "retrying", a retry is
/// genuinely happening. That honesty is the point; a spinner that narrates
/// fictional progress is worse than one that says nothing.
class ProgressController extends ValueNotifier<ProgressSnapshot?> {
  ProgressController() : super(null);

  DateTime? _startedAt;

  /// Begin an operation, resetting the clock.
  void begin(String message, {int? step, int? totalSteps}) {
    _startedAt = DateTime.now();
    value = ProgressSnapshot(
      message: message,
      startedAt: _startedAt!,
      step: step,
      totalSteps: totalSteps,
    );
  }

  /// Move to a new stage, keeping the elapsed clock running.
  void stage(
    String message, {
    int? step,
    int? totalSteps,
    int attempt = 1,
    int maxAttempts = 1,
  }) {
    _startedAt ??= DateTime.now();
    value = ProgressSnapshot(
      message: message,
      startedAt: _startedAt!,
      step: step ?? value?.step,
      totalSteps: totalSteps ?? value?.totalSteps,
      attempt: attempt,
      maxAttempts: maxAttempts,
    );
  }

  /// Clear the indicator — the work finished or failed.
  void done() {
    _startedAt = null;
    value = null;
  }
}
