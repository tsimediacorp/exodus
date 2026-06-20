import 'package:flutter/material.dart';
import '../models/devotional.dart';
import '../services/devotional_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import 'devotional_goal_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _devo.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _goal = _storage.loadDevotionalGoal();
      _today = _storage.devotionalForDay(DateTime.now());
    });
    if (_goal != null) {
      // Keep the recurring morning reminder alive on every open — independent
      // of whether today's devotional is already generated.
      _ensureDailyReminder();
      if (_today == null) _ensureToday();
    }
  }

  /// Ensure permission + the repeating daily devotional notification are set.
  Future<void> _ensureDailyReminder() async {
    await NotificationService.instance.requestPermission();
    await NotificationService.instance
        .scheduleDailyDevotional(hour: _kMorningHour);
  }

  Future<void> _ensureToday() async {
    final goal = _goal;
    if (goal == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await _devo.generate(goal: goal.text, recentRefs: _recentRefs());
      await _storage.saveDevotional(d);
      await _scheduleTomorrow(goal.text);
      if (mounted) setState(() => _today = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (_storage.devotionalForDay(tomorrow) != null) return;
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
    await NotificationService.instance.requestPermission();
    setState(() {
      _goal = _storage.loadDevotionalGoal();
      _today = null; // regenerate for the new goal
    });
    await _ensureToday();
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
              child: const Text('Change goal',
                  style: TextStyle(color: ExodusTheme.covenantGlow)),
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
      onRefresh: () async => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _goalCard(),
          const SizedBox(height: 20),
          if (_busy && _today == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: ExodusTheme.brass)),
            )
          else if (_error != null && _today == null)
            _errorCard()
          else if (_today != null)
            _devotionalCard(_today!),
        ],
      ),
    );
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

  Widget _errorCard() {
    return Column(
      children: [
        Text('Could not generate today\'s devotional.\n${_error ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ExodusTheme.crimson, fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _ensureToday,
          style: FilledButton.styleFrom(backgroundColor: ExodusTheme.steel),
          child: const Text('Try again'),
        ),
      ],
    );
  }

  Widget _devotionalCard(Devotional d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.title,
            style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2)),
        const SizedBox(height: 16),
        if (d.scriptureRef.isNotEmpty || d.scriptureText.isNotEmpty)
          _section(d.scriptureRef, d.scriptureText, italic: true, accent: true),
        if (d.reflection.isNotEmpty) _section('Reflection', d.reflection),
        if (d.prayer.isNotEmpty) _section('Prayer', d.prayer, italic: true),
        if (d.action.isNotEmpty) _section('Together today', d.action),
      ],
    );
  }

  Widget _section(String label, String body,
      {bool italic = false, bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(label.toUpperCase(),
                  style: TextStyle(
                      color: accent ? ExodusTheme.brass : ExodusTheme.ironMist,
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700)),
            ),
          SelectableText(body,
              style: TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  height: 1.55,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
        ],
      ),
    );
  }
}
