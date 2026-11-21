import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/exodus_layout.dart';
import '../models/action_plan.dart';
import '../services/action_plan_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/page_backdrop.dart';
import '../widgets/plan_card.dart';

/// One Active Steps plan, whole: the goal, a ring for how far along, and
/// every day as a path you can see the end of.
class ActiveStepsScreen extends StatelessWidget {
  final String planId;

  /// Back to the conversation the plan came from.
  final ValueChanged<String>? onOpenConversation;

  const ActiveStepsScreen({
    super.key,
    required this.planId,
    this.onOpenConversation,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActionPlanService.instance,
      builder: (context, _) {
        final plan = ActionPlanService.instance.byId(planId);
        if (plan == null) {
          return const Scaffold(
              body: Center(child: Text('This plan is no longer here.')));
        }
        return _PlanView(plan: plan, onOpenConversation: onOpenConversation);
      },
    );
  }
}

class _PlanView extends StatelessWidget {
  final ActionPlan plan;
  final ValueChanged<String>? onOpenConversation;

  const _PlanView({required this.plan, this.onOpenConversation});

  @override
  Widget build(BuildContext context) {
    final current = plan.currentStep(DateTime.now());
    final wide = ExodusLayout.isExpanded(context);
    final convId = plan.conversationId;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _Ring(plan: plan)),
        const SizedBox(height: 22),
        Text(plan.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: ExodusTheme.serif,
              color: ExodusTheme.parchment,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.15,
            )),
        const SizedBox(height: 10),
        if (plan.goal.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: ExodusTheme.midnight.withValues(alpha: 0.7),
              border:
                  Border.all(color: ExodusTheme.brass.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('THE GOAL',
                    style: TextStyle(
                      color: ExodusTheme.brass,
                      fontSize: 10.5,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 6),
                Text(plan.goal,
                    style: const TextStyle(
                      fontFamily: ExodusTheme.serif,
                      color: ExodusTheme.porcelain,
                      fontSize: 17,
                      height: 1.45,
                    )),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (convId != null && onOpenConversation != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: ExodusTheme.brass,
                side: BorderSide(
                    color: ExodusTheme.brass.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Talk it through with EXODUS'),
              onPressed: () {
                Navigator.of(context).pop();
                onOpenConversation!(convId);
              },
            ),
          ),
      ],
    );

    final path = Column(
      children: [
        for (var i = 0; i < plan.steps.length; i++)
          _PathStep(
            plan: plan,
            step: plan.steps[i],
            isCurrent: identical(plan.steps[i], current),
            isFirst: i == 0,
            isLast: i == plan.steps.length - 1,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: ExodusTheme.obsidian,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('ACTIVE STEPS',
            style: TextStyle(
              color: ExodusTheme.brass,
              fontSize: 13,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            )),
        actions: [
          if (plan.isActive)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded,
                  color: ExodusTheme.ironMist),
              color: ExodusTheme.midnight,
              onSelected: (_) => _confirmEnd(context),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'end', child: Text('End this plan')),
              ],
            ),
        ],
      ),
      body: PageBackdrop(
        child: SafeArea(
          child: wide
              // Unfolded: the goal on one page, the path on the facing one,
              // with the fold between them.
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(32, 12,
                            ExodusLayout.centreGutter, 32),
                        children: [header],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                            ExodusLayout.centreGutter, 12, 32, 32),
                        children: [path],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [header, const SizedBox(height: 26), path],
                ),
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('End this plan?'),
        content: const Text(
            'Your progress is kept, but EXODUS will stop reminding you and '
            'stop asking about it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End plan',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (ok == true) await ActionPlanService.instance.end(plan);
  }
}

/// How far along, as an arc that fills when a step is checked off.
class _Ring extends StatelessWidget {
  final ActionPlan plan;
  const _Ring({required this.plan});

  @override
  Widget build(BuildContext context) {
    final reduce = ExodusLayout.reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: plan.progress),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 150,
        height: 150,
        child: CustomPaint(
          painter: _RingPainter(v),
          child: Center(
            child: plan.isComplete
                ? const ExodusShield(size: 54)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${plan.doneCount}',
                          style: const TextStyle(
                            fontFamily: ExodusTheme.serif,
                            color: ExodusTheme.parchment,
                            fontSize: 44,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          )),
                      Text('of ${plan.length} steps',
                          style: const TextStyle(
                              color: ExodusTheme.ironMist, fontSize: 12)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = ExodusTheme.steel);
    if (value <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    final sweep = 2 * math.pi * value;
    // Glow under the arc, then the arc.
    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = ExodusTheme.brass.withValues(alpha: 0.18));
    canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: -math.pi / 2 + 2 * math.pi,
            colors: [ExodusTheme.brass, ExodusTheme.brassGlow],
            transform: GradientRotation(-math.pi / 2),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// A day on the path: a node on a line, then the step.
class _PathStep extends StatelessWidget {
  final ActionPlan plan;
  final PlanStep step;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;

  const _PathStep({
    required this.plan,
    required this.step,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor =
        step.done ? ExodusTheme.brass.withValues(alpha: 0.6) : ExodusTheme.steel;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                    width: 2,
                    height: 14,
                    color: isFirst ? Colors.transparent : lineColor),
                StepCheck(plan: plan, step: step),
                Expanded(
                  child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : lineColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: isCurrent ? const EdgeInsets.all(14) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isCurrent
                      ? ExodusTheme.brass.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: isCurrent
                      ? Border.all(
                          color: ExodusTheme.brass.withValues(alpha: 0.4))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isCurrent ? 'DAY ${step.day} · NEXT' : 'DAY ${step.day}',
                        style: TextStyle(
                          color: isCurrent || step.done
                              ? ExodusTheme.brass
                              : ExodusTheme.ironMist,
                          fontSize: 10.5,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Text(step.title,
                        style: TextStyle(
                          fontFamily: ExodusTheme.serif,
                          color: step.done
                              ? ExodusTheme.ironMist
                              : ExodusTheme.parchment,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        )),
                    if (step.action.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(step.action,
                          style: TextStyle(
                            color: step.done
                                ? ExodusTheme.ironMist.withValues(alpha: 0.7)
                                : ExodusTheme.porcelain.withValues(alpha: 0.86),
                            fontSize: 14.5,
                            height: 1.5,
                          )),
                    ],
                    if (step.scripture.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: ExodusTheme.brass.withValues(alpha: 0.35)),
                        ),
                        child: Text(step.scripture,
                            style: const TextStyle(
                              color: ExodusTheme.brass,
                              fontSize: 12,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
