import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/action_plan_service.dart';
import '../services/follow_ups.dart';
import '../services/key_scripture.dart';
import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// One conversation in a list: Home's recent threads, the full list, and
/// the list pane beside the thread when the Duo is open.
///
/// Swipe it left to delete it. There is no confirmation dialog: the row
/// goes at once and the caller offers Undo, which is how Mail and Messages
/// behave and why nobody hesitates to tidy up there. A dialog on every
/// swipe is what made deleting feel dangerous.
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onOpen;

  /// Null where a row cannot be deleted; the swipe is then not offered.
  final VoidCallback? onDelete;

  /// The thread open beside this list.
  final bool selected;

  /// No avatar and tighter padding, for the narrow pane beside the thread,
  /// where every point of width goes to the title instead.
  final bool dense;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onOpen,
    this.onDelete,
    this.selected = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final conv = conversation;
    final preview = conv.messages.isEmpty
        ? 'No messages yet'
        : ActionPlanService.strip(KeyScripture.strip(
                FollowUps.strip(conv.messages.last.content)))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final card = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          padding: EdgeInsets.all(dense ? 12 : 14),
          decoration: BoxDecoration(
            color: selected
                ? ExodusTheme.brass.withValues(alpha: 0.10)
                : ExodusTheme.midnight.withValues(alpha: 0.72),
            border: Border.all(
                color: selected
                    ? ExodusTheme.brass.withValues(alpha: 0.55)
                    : ExodusTheme.steel),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!dense) ...[
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ExodusTheme.slate,
                    border: Border.all(
                        color: ExodusTheme.brass.withValues(alpha: 0.30)),
                  ),
                  child: const ExodusShield(size: 20, glow: false),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(conv.title,
                              maxLines: dense ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? ExodusTheme.parchment
                                    : ExodusTheme.porcelain,
                                fontSize: dense ? 14.5 : 15,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                        const SizedBox(width: 8),
                        Text(when(conv.updatedAt),
                            style: const TextStyle(
                                color: ExodusTheme.ironMist, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ExodusTheme.ironMist,
                            fontSize: 13,
                            height: 1.4)),
                  ],
                ),
              ),
              if (!dense)
                const Padding(
                  padding: EdgeInsets.only(left: 6, top: 12),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: ExodusTheme.ironMist),
                ),
            ],
          ),
        ),
      ),
    );

    final delete = onDelete;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: delete == null
          ? card
          : Semantics(
              customSemanticsActions: {
                const CustomSemanticsAction(label: 'Delete'): delete,
              },
              child: Dismissible(
                key: ValueKey('dismiss-${conv.id}'),
                direction: DismissDirection.endToStart,
                // Past a third of the row it commits; a short drag springs
                // back, so a scroll that wanders sideways never deletes.
                dismissThresholds: const {DismissDirection.endToStart: 0.33},
                background: const _DeleteBackground(),
                onUpdate: (d) {
                  if (d.reached && !d.previousReached) {
                    HapticFeedback.mediumImpact();
                  }
                },
                onDismissed: (_) => delete(),
                child: card,
              ),
            ),
    );
  }

  /// Clock time today, weekday this week, date beyond.
  static String when(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final days = today.difference(that).inDays;

    if (days == 0) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            ExodusTheme.crimson.withValues(alpha: 0.25),
            ExodusTheme.crimson.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Delete',
              style: TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              )),
          SizedBox(width: 8),
          Icon(Icons.delete_outline_rounded, color: ExodusTheme.porcelain),
        ],
      ),
    );
  }
}
