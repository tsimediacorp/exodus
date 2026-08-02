import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/devotional.dart';
import '../models/journey.dart';
import '../services/journey_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/devotional_content.dart';

/// One day of a guided plan. Generates the day on first open, then reads it
/// back from storage — so a plan the couple has walked stays readable offline.
class JourneyDayScreen extends StatefulWidget {
  final Journey journey;
  final int day;

  const JourneyDayScreen({super.key, required this.journey, required this.day});

  @override
  State<JourneyDayScreen> createState() => _JourneyDayScreenState();
}

class _JourneyDayScreenState extends State<JourneyDayScreen> {
  final StorageService _storage = StorageService.instance;
  final JourneyService _service = JourneyService();

  late int _day = widget.day;
  late JourneyProgress _progress;
  Devotional? _content;
  bool _busy = false;
  String? _error;

  /// Same supersede guard as the Devotional tab: moving between days while a
  /// generation is in flight must not let the old day's result land on the new.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _progress = _storage.journeyProgress(widget.journey.id) ??
        JourneyProgress(journeyId: widget.journey.id);
    _loadDay();
  }

  @override
  void dispose() {
    _generation++;
    TtsService.instance.stop();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadDay() async {
    final existing = _progress.days[_day];
    if (existing != null) {
      setState(() {
        _content = existing;
        _error = null;
      });
      return;
    }
    await _generate();
  }

  Future<void> _generate() async {
    final gen = ++_generation;
    final targetDay = _day;
    setState(() {
      _busy = true;
      _error = null;
      _content = null;
    });
    final day = await _service.generateDay(
      journey: widget.journey,
      dayNumber: targetDay,
      progress: _progress,
    );
    if (gen != _generation || !mounted) return;
    if (day == null) {
      setState(() {
        _busy = false;
        _error = _service.lastError ?? 'Could not write this day.';
      });
      return;
    }
    _progress.days[targetDay] = day;
    await _storage.saveJourneyProgress(_progress);
    if (gen != _generation || !mounted) return;
    setState(() {
      _content = day;
      _busy = false;
    });
  }

  Future<void> _markDoneAndAdvance() async {
    HapticFeedback.mediumImpact();
    _progress.completed.add(_day);
    final finished = _progress.isComplete(widget.journey.totalDays);
    if (finished) _progress.finishedAt = DateTime.now();
    await _storage.saveJourneyProgress(_progress);
    if (!mounted) return;

    if (finished) {
      await _showFinished();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final next = _progress.nextDay(widget.journey.totalDays);
    if (next == null) {
      Navigator.of(context).pop();
      return;
    }
    TtsService.instance.stop();
    setState(() => _day = next);
    await _loadDay();
  }

  Future<void> _showFinished() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ExodusTheme.midnight,
          title: Row(
            children: [
              const Icon(Icons.verified_rounded, color: ExodusTheme.brass),
              const SizedBox(width: 10),
              Expanded(child: Text('${widget.journey.title} complete')),
            ],
          ),
          content: Text(
              'You walked all ${widget.journey.totalDays} days together. '
              'Keep the verses you kept, and let what you learned hold.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.covenantBlue),
              child: const Text('Amen'),
            ),
          ],
        ),
      );

  void _goToDay(int day) {
    if (day < 1 || day > widget.journey.totalDays || day == _day) return;
    TtsService.instance.stop();
    setState(() => _day = day);
    _loadDay();
  }

  @override
  Widget build(BuildContext context) {
    final done = _progress.completed.contains(_day);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.journey.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: LinearProgressIndicator(
            value: _progress.completed.length / widget.journey.totalDays,
            minHeight: 2,
            backgroundColor: ExodusTheme.steel,
            valueColor: const AlwaysStoppedAnimation(ExodusTheme.brass),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _dayStrip(),
                  const SizedBox(height: 20),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: ExodusTheme.brass),
                          SizedBox(height: 16),
                          Text('Writing this day for you…',
                              style: TextStyle(
                                  color: ExodusTheme.ironMist, fontSize: 13)),
                        ],
                      ),
                    )
                  else if (_error != null)
                    _errorCard()
                  else if (_content != null)
                    DevotionalContent(
                      devotional: _content!,
                      source: widget.journey.title,
                    ),
                ],
              ),
            ),
            if (_content != null && !_busy) _footer(done),
          ],
        ),
      ),
    );
  }

  /// Day numbers across the top — completed, current, and still to come.
  Widget _dayStrip() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.journey.totalDays,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final day = i + 1;
          final isDone = _progress.completed.contains(day);
          final isCurrent = day == _day;
          return Semantics(
            button: true,
            selected: isCurrent,
            label: 'Day $day${isDone ? ', done' : ''}',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _goToDay(day),
              child: Container(
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? ExodusTheme.covenantBlue.withValues(alpha: 0.25)
                      : Colors.transparent,
                  border: Border.all(
                    color: isCurrent
                        ? ExodusTheme.covenantGlow
                        : isDone
                            ? ExodusTheme.brass
                            : ExodusTheme.steel,
                    width: isCurrent ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: isDone && !isCurrent
                    ? const Icon(Icons.check,
                        size: 16, color: ExodusTheme.brass)
                    : Text('$day',
                        style: TextStyle(
                          color: isCurrent
                              ? ExodusTheme.porcelain
                              : ExodusTheme.ironMist,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.crimson.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Couldn\'t write day.',
              style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_error!,
              style: const TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _generate,
            style: FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _footer(bool done) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: ExodusTheme.obsidian,
        border: Border(top: BorderSide(color: ExodusTheme.steel)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: done
            ? OutlinedButton(
                onPressed: _day < widget.journey.totalDays
                    ? () => _goToDay(_day + 1)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ExodusTheme.ironMist,
                  side: const BorderSide(color: ExodusTheme.steel),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(_day < widget.journey.totalDays
                    ? 'Day ${_day + 1}'
                    : 'Plan complete'),
              )
            : FilledButton(
                onPressed: _markDoneAndAdvance,
                style: FilledButton.styleFrom(
                  backgroundColor: ExodusTheme.covenantBlue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(
                  _day == widget.journey.totalDays
                      ? 'Finish the plan'
                      : 'Done — next day',
                  style: const TextStyle(
                      color: ExodusTheme.porcelain,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
      ),
    );
  }
}
