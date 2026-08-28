import 'package:flutter/material.dart';

import '../models/study_exercise.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/scripture_link.dart';

/// Every exercise this device has been served, newest first.
///
/// The point is the record: an exercise you worked through and wrote against
/// is worth being able to find again, and the run of ticks is the only place
/// the habit is visible.
class StudyHistoryScreen extends StatelessWidget {
  const StudyHistoryScreen({super.key});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateLabel(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final all = StorageService.instance.loadStudyExercises();
    final done = all.where((e) => e.isComplete).length;

    return Scaffold(
      appBar: AppBar(title: const Text('PAST EXERCISES')),
      body: SafeArea(
        child: all.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Nothing here yet. Today\'s exercise will be the first.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: ExodusTheme.ironMist, fontSize: 14),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: all.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _summary(all.length, done);
                  return _tile(context, all[i - 1]);
                },
              ),
      ),
    );
  }

  Widget _summary(int total, int done) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        '$done of $total worked through',
        style: const TextStyle(
          color: ExodusTheme.ironMist,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, StudyExercise e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: ExodusTheme.midnight,
          border: Border.all(color: ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Theme(
          // ExpansionTile draws its own dividers over the card's border.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: ExodusTheme.ironMist,
            collapsedIconColor: ExodusTheme.ironMist,
            title: Text(e.title,
                style: const TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                )),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(_dateLabel(e.day),
                      style: const TextStyle(
                          color: ExodusTheme.ironMist, fontSize: 11)),
                  if (e.scriptureRef.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(e.scriptureRef,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: ExodusTheme.brass, fontSize: 11)),
                    ),
                  ],
                  if (e.isComplete) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_rounded,
                        size: 13, color: ExodusTheme.brass),
                  ],
                ],
              ),
            ),
            children: [
              if (e.premise.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(e.premise,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist,
                          fontSize: 13,
                          height: 1.5)),
                ),
              for (var i = 0; i < e.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${i + 1}.  ${e.steps[i]}',
                      style: const TextStyle(
                          color: ExodusTheme.porcelain,
                          fontSize: 14,
                          height: 1.5)),
                ),
              if (e.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ExodusTheme.slate,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WHAT YOU WROTE',
                          style: TextStyle(
                            color: ExodusTheme.ironMist,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          )),
                      const SizedBox(height: 8),
                      Text(e.notes,
                          style: const TextStyle(
                              color: ExodusTheme.porcelain,
                              fontSize: 14,
                              height: 1.5)),
                    ],
                  ),
                ),
              ],
              if (e.scriptureRef.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => openScriptureRef(context, e.scriptureRef),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book_rounded,
                              size: 14, color: ExodusTheme.brass),
                          const SizedBox(width: 7),
                          Text('Open ${e.scriptureRef}',
                              style: const TextStyle(
                                color: ExodusTheme.brass,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
