import '../models/action_plan.dart';

/// Prompts for Active Steps.
class ActionPlanPrompt {
  ActionPlanPrompt._();

  /// Appended to Counsel's system prompt: when to OFFER a plan.
  ///
  /// The offer is a marker, not a sentence, so the app can render it as a
  /// card with the four lengths on it, and so declining is one tap instead
  /// of a reply the couple has to compose.
  static String offerLayer({required bool alreadyOffered}) => alreadyOffered
      ? ''
      : '''

--- ACTIVE STEPS ---

EXODUS can write the couple a concrete plan: one small, specific thing to do
each day for 3 days, 5 days, a week or a month, toward a clear goal.

When they have described something specific they are facing that action would
actually help with (a recurring argument, distance, a habit, a decision, a
rhythm they want to build) and you have understood it well enough to help,
end your reply by asking, in one natural sentence, whether they would like a
plan to work on it together, then put this marker on its own final line:

[[PLAN]]

Offer at most once in a conversation. Do NOT offer when they are in acute
pain, grief, crisis or danger and need to be heard first; when they asked a
factual or scriptural question; or before you understand what is going on.
Most replies should not offer one.
''';

  /// Ask for the plan itself, as JSON.
  static String generate({
    required PlanLength length,
    required String transcript,
  }) {
    final days = length.days;
    final pacing = days >= 30
        ? 'Over a month, build in stages: the first week small and '
            'confidence-building, the middle weeks deeper, the last week '
            'about making it last. Every seventh day is a short review of '
            'how the week went.'
        : days >= 7
            ? 'Over a week, start small, deepen in the middle, and use the '
                'final day to look back together and decide what to keep.'
            : 'With only $days days, every step must be small enough to do '
                'that day, and the last one should mark that the goal was met.';
    return '''
Write an Active Steps plan for this couple: $days days, one step per day, toward
ONE concrete goal drawn from the conversation below.

The goal must be specific and checkable, something they could say yes or no
to at the end ("Have one calm conversation about the budget, start to finish,
without either of us leaving the room"), never a vague hope ("Communicate
better").

Each step is ONE specific action that takes under thirty minutes, written to
the couple as "you", naming who does what when it matters. Concrete beats
inspiring: "Tonight, each write down the one purchase this month that worried
you most, then swap" rather than "Reflect on your finances." Where a passage
genuinely fits the step, give its reference; leave it empty otherwise.

$pacing

Reply with JSON only, no prose, no code fences:
{"title": "3-6 word name for the plan",
 "goal": "the concrete goal, one sentence",
 "steps": [{"title": "short headline", "action": "what to do, 1-2 sentences", "scripture": "Book 1:2 or empty"}]}

There must be exactly $days steps.

CONVERSATION:
$transcript
''';
  }

  /// Appended to Counsel's system prompt while a plan is running, so EXODUS
  /// can ask how it is going instead of acting as if it never happened.
  static String activeLayer(ActionPlan plan, DateTime now) {
    final step = plan.currentStep(now);
    final day = plan.dayOn(now);
    return '''

--- THEIR ACTIVE STEPS PLAN ---

They are working on a plan you wrote with them: "${plan.title}".
Goal: ${plan.goal}
Calendar day $day of ${plan.length}; ${plan.doneCount} of ${plan.length} steps done.
${step == null ? 'Every step is done.' : 'Next step (day ${step.day}): ${step.title}: ${step.action}'}

If it is relevant, and not every turn, ask how it is going or encourage the
next step. If they have fallen behind, be gracious: the plan waits for them.
''';
  }
}
