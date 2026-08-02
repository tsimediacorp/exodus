import 'package:flutter/material.dart';
import '../config/journey_catalog.dart';
import '../models/journey.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import 'journey_day_screen.dart';

/// The guided-plan catalog. Shows anything in progress at the top, then the
/// plans still on offer.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  final StorageService _storage = StorageService.instance;
  Map<String, JourneyProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _progress = _storage.loadJourneys());

  Future<void> _open(Journey journey) async {
    var progress = _progress[journey.id];
    if (progress == null) {
      progress = JourneyProgress(journeyId: journey.id);
      await _storage.saveJourneyProgress(progress);
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JourneyDayScreen(
        journey: journey,
        day: progress!.nextDay(journey.totalDays) ?? journey.totalDays,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _confirmRestart(Journey journey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ExodusTheme.midnight,
        title: const Text('Start over?'),
        content: Text('Your progress through "${journey.title}" will be '
            'cleared, along with the days already written for you.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start over',
                  style: TextStyle(color: ExodusTheme.crimson))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteJourneyProgress(journey.id);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = JourneyCatalog.all
        .where((j) => _progress.containsKey(j.id))
        .toList();
    final fresh = JourneyCatalog.all
        .where((j) => !_progress.containsKey(j.id))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Journeys')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              'Guided plans you walk through together, a day at a time. Each '
              'day is written for the two of you.',
              style: TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (active.isNotEmpty) ...[
              _sectionLabel('IN PROGRESS'),
              for (final j in active) _card(j, _progress[j.id]),
              const SizedBox(height: 12),
            ],
            if (fresh.isNotEmpty) ...[
              _sectionLabel(active.isEmpty ? 'CHOOSE A PLAN' : 'MORE PLANS'),
              for (final j in fresh) _card(j, null),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
      );

  Widget _card(Journey journey, JourneyProgress? progress) {
    final done = progress?.completed.length ?? 0;
    final complete = progress?.isComplete(journey.totalDays) ?? false;
    final started = progress != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: ExodusTheme.midnight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(journey),
          onLongPress: started ? () => _confirmRestart(journey) : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                  color: complete ? ExodusTheme.brass : ExodusTheme.steel),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(journey.title,
                          style: const TextStyle(
                              color: ExodusTheme.porcelain,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (complete)
                      const Icon(Icons.verified_rounded,
                          color: ExodusTheme.brass, size: 20)
                    else
                      Text('${journey.totalDays} days',
                          style: const TextStyle(
                              color: ExodusTheme.ironMist, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(journey.subtitle,
                    style: const TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 13,
                        height: 1.4)),
                if (started) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: done / journey.totalDays,
                      minHeight: 5,
                      backgroundColor: ExodusTheme.steel,
                      valueColor: AlwaysStoppedAnimation(
                          complete ? ExodusTheme.brass : ExodusTheme.covenantGlow),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    complete
                        ? 'Finished — long-press to walk it again'
                        : '$done of ${journey.totalDays} days done',
                    style: const TextStyle(
                        color: ExodusTheme.ironMist, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
