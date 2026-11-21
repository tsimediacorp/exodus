import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/exodus_layout.dart';
import '../models/action_plan.dart';
import '../services/action_plan_service.dart';
import '../theme/exodus_theme.dart';

/// EXODUS asking whether a plan would help, with the four lengths on it.
///
/// Shown under the reply that offered. One tap answers; nothing to type.
class PlanOfferCard extends StatefulWidget {
  final ValueChanged<PlanLength> onChoose;
  final VoidCallback onDecline;

  /// True while the plan is being written.
  final bool working;

  const PlanOfferCard({
    super.key,
    required this.onChoose,
    required this.onDecline,
    this.working = false,
  });

  @override
  State<PlanOfferCard> createState() => _PlanOfferCardState();
}

class _PlanOfferCardState extends State<PlanOfferCard> {
  PlanLength? _chosen;

  @override
  Widget build(BuildContext context) {
    final reduce = ExodusLayout.reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: _Frame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('ACTIVE STEPS'),
            const SizedBox(height: 10),
            const Text('Turn this into a plan?',
                style: TextStyle(
                  fontFamily: ExodusTheme.serif,
                  color: ExodusTheme.parchment,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 4),
            const Text(
              'One concrete goal, and one small thing to do each day until '
              'you reach it. Choose how long.',
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in PlanLength.values)
                  _LengthChip(
                    label: l.label,
                    chosen: _chosen == l,
                    working: widget.working && _chosen == l,
                    enabled: !widget.working,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _chosen = l);
                      widget.onChoose(l);
                    },
                  ),
              ],
            ),
            if (!widget.working)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(top: 8),
                    foregroundColor: ExodusTheme.ironMist,
                  ),
                  onPressed: widget.onDecline,
                  child: const Text('Not now'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LengthChip extends StatelessWidget {
  final String label;
  final bool chosen;
  final bool working;
  final bool enabled;
  final VoidCallback onTap;

  const _LengthChip({
    required this.label,
    required this.chosen,
    required this.working,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: chosen
                ? const LinearGradient(
                    colors: [ExodusTheme.brassGlow, ExodusTheme.brass])
                : null,
            color: chosen ? null : ExodusTheme.slate.withValues(alpha: 0.7),
            border: Border.all(
                color: chosen
                    ? ExodusTheme.brass
                    : ExodusTheme.brass.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (working) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.6, color: ExodusTheme.obsidian),
                ),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: TextStyle(
                    color: chosen ? ExodusTheme.obsidian : ExodusTheme.brass,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// A running plan: goal, progress, and today's step with its checkbox.
///
/// The same card sits in the thread the plan came from and on Home, so the
/// step is one tap from wherever they happen to be.
class PlanCard extends StatelessWidget {
  final ActionPlan plan;
  final VoidCallback onOpen;

  const PlanCard({super.key, required this.plan, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final step = plan.currentStep(DateTime.now());
    return Semantics(
      container: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        child: _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Eyebrow(plan.isComplete
                      ? 'GOAL REACHED'
                      : 'ACTIVE STEPS · ${plan.length} DAYS'),
                  const Spacer(),
                  Text('${plan.doneCount}/${plan.length}',
                      style: const TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                ],
              ),
              const SizedBox(height: 10),
              Text(plan.title,
                  style: const TextStyle(
                    fontFamily: ExodusTheme.serif,
                    color: ExodusTheme.parchment,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  )),
              if (plan.goal.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(plan.goal,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 13.5,
                        height: 1.45)),
              ],
              const SizedBox(height: 14),
              PlanProgress(plan: plan),
              if (step != null) ...[
                const SizedBox(height: 14),
                StepRow(
                  plan: plan,
                  step: step,
                  highlight: true,
                ),
              ],
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Whole plan',
                        style: TextStyle(
                            color: ExodusTheme.brass,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right_rounded,
                        color: ExodusTheme.brass, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress as a row of days: a bead per day up to a week, a filling bar
/// beyond that (thirty beads is a barcode, not a progress view).
class PlanProgress extends StatelessWidget {
  final ActionPlan plan;
  const PlanProgress({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    if (plan.length > 7) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: plan.progress),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            minHeight: 6,
            backgroundColor: ExodusTheme.steel,
            color: ExodusTheme.brass,
          ),
        ),
      );
    }
    return Row(
      children: [
        for (final s in plan.steps) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: s.done ? ExodusTheme.brass : ExodusTheme.steel,
                boxShadow: s.done
                    ? [
                        BoxShadow(
                          color: ExodusTheme.brass.withValues(alpha: 0.45),
                          blurRadius: 6,
                        )
                      ]
                    : null,
              ),
            ),
          ),
          if (s != plan.steps.last) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

/// One step with a check you can tap. Checking it fills with brass and
/// gives a firm haptic: finishing a step should feel like something.
class StepRow extends StatelessWidget {
  final ActionPlan plan;
  final PlanStep step;
  final bool highlight;

  const StepRow({
    super.key,
    required this.plan,
    required this.step,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? ExodusTheme.obsidian.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: highlight
            ? Border.all(color: ExodusTheme.brass.withValues(alpha: 0.22))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepCheck(plan: plan, step: step),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAY ${step.day}',
                    style: const TextStyle(
                      color: ExodusTheme.brass,
                      fontSize: 10.5,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text(step.title,
                    style: TextStyle(
                      color: step.done
                          ? ExodusTheme.ironMist
                          : ExodusTheme.porcelain,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration:
                          step.done ? TextDecoration.lineThrough : null,
                      decorationColor: ExodusTheme.ironMist,
                    )),
                if (step.action.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(step.action,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist,
                          fontSize: 13.5,
                          height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StepCheck extends StatelessWidget {
  final ActionPlan plan;
  final PlanStep step;
  const StepCheck({super.key, required this.plan, required this.step});

  @override
  Widget build(BuildContext context) {
    final done = step.done;
    return Semantics(
      button: true,
      checked: done,
      label: 'Day ${step.day}: ${step.title}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          done ? HapticFeedback.selectionClick() : HapticFeedback.heavyImpact();
          ActionPlanService.instance.toggleStep(plan, step);
        },
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: done
                  ? const LinearGradient(
                      colors: [ExodusTheme.brassGlow, ExodusTheme.brass],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              border: Border.all(
                  color: done ? ExodusTheme.brass : ExodusTheme.ironMist,
                  width: 1.5),
              boxShadow: done
                  ? [
                      BoxShadow(
                        color: ExodusTheme.brass.withValues(alpha: 0.5),
                        blurRadius: 12,
                      )
                    ]
                  : null,
            ),
            child: AnimatedScale(
              scale: done ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check_rounded,
                  size: 18, color: ExodusTheme.obsidian),
            ),
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(ExodusTheme.midnight, ExodusTheme.brass, 0.10)!,
            ExodusTheme.midnight,
          ],
        ),
        border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: ExodusTheme.brass.withValues(alpha: 0.08),
            blurRadius: 24,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flag_rounded, size: 14, color: ExodusTheme.brass),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
              color: ExodusTheme.brass,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}
