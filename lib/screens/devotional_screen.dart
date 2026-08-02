import 'dart:async';
import 'package:flutter/material.dart';
import '../models/devotional.dart';
import '../services/devotional_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/devotional_content.dart';
import '../widgets/exodus_shield.dart';
import 'devotional_goal_screen.dart';
import 'journeys_screen.dart';
import 'saved_verses_screen.dart';

/// Morning local-notification hour (24h, device local time).
const int _kMorningHour = 7;

class DevotionalScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const DevotionalScreen({super.key, this.onOpenMenu});

  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen> {
  final StorageService _storage = StorageService.instance;
  final DevotionalService _devo = DevotionalService();

  DevotionalGoal? _goal;
  Devotional? _today;
  bool _busy = false;
  String? _error;

  /// Bumped every time a new generation supersedes an older one (goal change,
  /// manual refresh). A run whose token no longer matches [_generation] has
  /// been superseded and must not write its result into the UI — that's what
  /// keeps a slow generation for the OLD goal from clobbering the new one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Abandon any in-flight generation: its token can never match again.
    _generation++;
    TtsService.instance.stop();
    _devo.dispose();
    super.dispose();
  }

  /// Consecutive days, counting back from today, on which the couple ticked
  /// off the devotional's together-action. Yesterday still counts as alive so
  /// the streak doesn't look broken before they've opened the app today.
  int get _streak {
    final days = _storage.loadActionDays();
    if (days.isEmpty) return 0;
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(Devotional.keyFor(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(Devotional.keyFor(cursor))) return 0;
    }
    var count = 0;
    while (days.contains(Devotional.keyFor(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  Future<void> _load() async {
    final goal = _storage.loadDevotionalGoal();
    final stored = _storage.devotionalForDay(DateTime.now());
    setState(() {
      _goal = goal;
      _today = stored;
    });
    if (goal == null) return;
    // Keep the recurring morning reminder alive on every open — independent
    // of whether today's devotional is already generated.
    unawaited(_ensureDailyReminder());
    if (Devotional.needsGeneration(stored, goal.text)) await _ensureToday();
  }

  /// Ensure permission + the repeating daily devotional notification are set.
  /// Best-effort: never allowed to block or break the devotional itself.
  Future<void> _ensureDailyReminder() async {
    try {
      await NotificationService.instance.requestPermission();
      await NotificationService.instance
          .scheduleDailyDevotional(hour: _kMorningHour);
    } catch (_) {
      // Notifications are a nicety; the tab works fine without them.
    }
  }

  Future<void> _ensureToday() async {
    final goal = _goal;
    if (goal == null) return;
    // Claim this run. Any earlier run still in flight is now superseded and
    // will discard its result when it finishes.
    final gen = ++_generation;

    // Show a real devotional INSTANTLY (no spinner, never blank) — then quietly
    // upgrade to a fresh AI-generated one if/when it arrives.
    setState(() {
      _busy = true;
      _error = null;
      if (Devotional.needsGeneration(_today, goal.text)) {
        _today = _devo.fallbackFor(DateTime.now(), goal.text);
      }
    });

    try {
      final d = await _devo.generate(goal: goal.text, recentRefs: _recentRefs());
      if (gen != _generation) return; // superseded — don't clobber the new goal
      await _storage.saveDevotional(d);
      if (!mounted) return;
      setState(() {
        _today = d;
        _error = d.isFallback ? _devo.lastGenerateError : null;
      });
    } catch (e) {
      // generate() never throws, so this is a persistence hiccup. Keep the
      // instantly-shown devotional and surface that something went wrong.
      if (gen != _generation) return;
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      // Always release the UI, even when superseded — a newer run owns the
      // flag from here, and it sets _busy itself.
      if (mounted && gen == _generation) setState(() => _busy = false);
    }

    // Tomorrow's pre-generation is background work: the user is waiting on
    // TODAY, so it runs outside the busy window (it used to double the worst-
    // case stall) and never blocks or fails the visible flow.
    if (gen == _generation) unawaited(_scheduleTomorrow(goal.text));
  }

  /// Pre-generate tomorrow's devotional and schedule the morning notification
  /// to carry it (no backend — generated while the app is open).
  /// Scripture refs used in the most recent devotionals, so the model avoids
  /// repeating them. Newest first, capped.
  List<String> _recentRefs() => _storage
      .loadDevotionals()
      .map((d) => d.scriptureRef)
      .where((r) => r.trim().isNotEmpty)
      .take(10)
      .toList();

  /// Pre-generate tomorrow's devotional so the morning open is instant. The
  /// reminder notification itself is a separate recurring schedule (see
  /// _ensureDailyReminder), so it fires daily regardless of this.
  Future<void> _scheduleTomorrow(String goal) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    // Regenerate when tomorrow is missing, was a fallback, or was written for
    // an older goal — otherwise a goal change today still served the OLD
    // goal's devotional tomorrow morning.
    if (!Devotional.needsGeneration(_storage.devotionalForDay(tomorrow), goal)) return;
    try {
      final d = await _devo.generate(
          goal: goal, forDay: tomorrow, recentRefs: _recentRefs());
      await _storage.saveDevotional(d);
    } catch (_) {
      // Tomorrow can still be generated on next open; don't block today.
    }
  }

  Future<void> _setOrShiftGoal() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DevotionalGoalScreen(currentGoal: _goal?.text),
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    await _storage.saveDevotionalGoal(DevotionalGoal(text: result.trim()));
    if (!mounted) return;
    setState(() {
      _goal = _storage.loadDevotionalGoal();
      _today = null; // regenerate for the new goal
    });
    // Regenerate first — the permission prompt used to sit between saving the
    // goal and refreshing the UI, so if it stalled the screen kept showing the
    // OLD goal and old devotional with the new goal already persisted.
    await _ensureToday();
    unawaited(_ensureDailyReminder());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devotional'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
        actions: [
          if (_goal != null)
            TextButton(
              onPressed: _busy ? null : _setOrShiftGoal,
              // Colour via foregroundColor, NOT a hardcoded colour on the
              // child Text — that defeated Flutter's disabled greying, so a
              // dead button rendered as fully enabled.
              style: TextButton.styleFrom(
                foregroundColor: ExodusTheme.covenantGlow,
                disabledForegroundColor: ExodusTheme.steel,
              ),
              child: const Text('Change goal'),
            ),
        ],
      ),
      body: SafeArea(
        child: _goal == null ? _buildIntro() : _buildDevotional(),
      ),
    );
  }

  Widget _buildIntro() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const ExodusShield(size: 80),
          const SizedBox(height: 24),
          const Text('Daily devotionals, built around you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 22,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text(
            'Tell EXODUS what you want God to grow in your marriage, and you\'ll '
            'get a fresh devotional each morning — scripture, reflection, prayer, '
            'and one thing to do together.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ExodusTheme.ironMist, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _setOrShiftGoal,
              style: FilledButton.styleFrom(
                backgroundColor: ExodusTheme.covenantBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Set your goal',
                  style: TextStyle(
                      color: ExodusTheme.porcelain,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevotional() {
    return RefreshIndicator(
      // _load is awaited now (it used to be `void`, so the spinner vanished
      // instantly and nothing regenerated).
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        // Always scrollable so pull-to-refresh works even on a short page.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _goalCard(),
          const SizedBox(height: 12),
          _shortcuts(),
          const SizedBox(height: 20),
          // The error shows as a banner ABOVE whatever content we have — when
          // generation falls back we still render a devotional, and hiding the
          // failure behind it is what made this look like it "just worked".
          if (_error != null) ...[
            _errorCard(),
            const SizedBox(height: 20),
          ],
          if (_busy && _today == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: ExodusTheme.brass)),
            )
          else if (_today != null)
            _devotionalCard(_today!),
        ],
      ),
    );
  }

  /// Pull-to-refresh: force a fresh generation attempt rather than just
  /// re-reading storage, so a fallback day can recover once the network is up.
  Future<void> _refresh() async {
    if (_goal == null) {
      await _load();
      return;
    }
    await _ensureToday();
  }

  Widget _goalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, color: ExodusTheme.brass, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR GOAL',
                    style: TextStyle(
                        color: ExodusTheme.ironMist,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_goal!.text,
                    style: const TextStyle(
                        color: ExodusTheme.porcelain, fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Journeys, kept verses, and the together-streak — the things that turn a
  /// one-off daily reading into something with continuity.
  Widget _shortcuts() {
    final streak = _streak;
    final verseCount = _storage.loadSavedVerses().length;
    return Row(
      children: [
        Expanded(
          child: _shortcutTile(
            icon: Icons.route_rounded,
            label: 'Journeys',
            detail: 'Guided plans',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JourneysScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _shortcutTile(
            icon: Icons.bookmark_rounded,
            label: 'Verses',
            detail: verseCount == 0 ? 'None kept' : '$verseCount kept',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedVersesScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _shortcutTile(
            icon: Icons.local_fire_department_rounded,
            label: streak == 0 ? '—' : '$streak day${streak == 1 ? '' : 's'}',
            detail: 'Together',
            highlight: streak > 0,
          ),
        ),
      ],
    );
  }

  Widget _shortcutTile({
    required IconData icon,
    required String label,
    required String detail,
    VoidCallback? onTap,
    bool highlight = false,
  }) {
    final accent = highlight ? ExodusTheme.brass : ExodusTheme.ironMist;
    return Material(
      color: ExodusTheme.midnight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(
                color: highlight ? ExodusTheme.brass : ExodusTheme.steel),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: highlight
                          ? ExodusTheme.brass
                          : ExodusTheme.porcelain,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: ExodusTheme.ironMist, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    final showingFallback = _today?.isFallback ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.crimson.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined,
              color: ExodusTheme.crimson, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showingFallback
                      ? 'Showing a stand-in devotional — EXODUS couldn\'t write '
                          'a fresh one just now.'
                      : 'Couldn\'t generate today\'s devotional.',
                  style: const TextStyle(
                      color: ExodusTheme.porcelain, fontSize: 14, height: 1.4),
                ),
                if (_error != null && _error!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: const TextStyle(
                          color: ExodusTheme.ironMist, fontSize: 12)),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _ensureToday,
                  style: TextButton.styleFrom(
                    foregroundColor: ExodusTheme.covenantGlow,
                    disabledForegroundColor: ExodusTheme.steel,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  child: Text(_busy ? 'Trying…' : 'Try again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shared with journey days — same shape, same actions (listen, keep the
  /// verse, share it), so neither screen carries its own copy.
  Widget _devotionalCard(Devotional d) => DevotionalContent(
        devotional: d,
        source: 'Daily devotional',
        showActionToggle: true,
      );
}
