import 'package:flutter/material.dart';

import '../theme/exodus_theme.dart';

/// A quiet line marking where one day of a conversation ends and the next
/// begins.
///
/// A thread a couple returns to for weeks had no sense of time in it at all:
/// something said in March sat directly above something said this morning,
/// and reading back gave no way to tell an argument from its aftermath.
class DayDivider extends StatelessWidget {
  final DateTime day;
  const DayDivider({super.key, required this.day});

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  /// Whether [a] and [b] fall on the same calendar day.
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// "Today", "Yesterday", a weekday within the last week, then a date.
  static String label(DateTime day, {DateTime? now}) {
    final today = now ?? DateTime.now();
    // Calendar days, not 24-hour spans: 11pm last night is yesterday even
    // though it was two hours ago.
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(day.year, day.month, day.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekdays[day.weekday - 1];
    final date = '${_months[day.month - 1]} ${day.day}';
    return day.year == today.year ? date : '$date, ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rule = Expanded(
      child: Container(
        height: 1,
        color: ExodusTheme.steel.withValues(alpha: 0.55),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label(day).toUpperCase(),
              style: TextStyle(
                color: ExodusTheme.ironMist.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ),
          rule,
        ],
      ),
    );
  }
}
