import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/study_exercise.dart';
import '../services/progress.dart';
import '../services/storage_service.dart';
import '../services/study_service.dart';
import '../theme/exodus_theme.dart';
import '../widgets/exodus_shield.dart';
import '../widgets/progress_view.dart';
import '../widgets/scripture_link.dart';
import 'study_history_screen.dart';

/// The daily Bible study exercise — something to do, not something to read.
class StudyScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;

  /// Whether this is the mode currently on screen.
  ///
  /// HomeShell keeps every mode alive in an IndexedStack, which builds all of
  /// them at launch — so without this the app would generate an exercise on
  /// every cold start, for every user, whether or not they ever open the tab.
  /// It would also do it alongside the devotional's generation and the
  /// check-in scan, three AI calls racing each other into the same rate limit.
  final bool isActive;

  const StudyScreen({super.key, this.onOpenMenu, this.isActive = false});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final StorageService _storage = StorageService.instance;
  final StudyService _study = StudyService();
  final ProgressController _status = ProgressController();
  final TextEditingController _notes = TextEditingController();

  StudyExercise? _today;
  bool _busy = false;
  String? _error;

  /// Bumped every time a new generation supersedes an older one, so a slow
  /// run that has been replaced discards its result instead of clobbering the
  /// newer one. Same guard the devotional uses.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StudyScreen old) {
    super.didUpdateWidget(old);
    // Generate the first time the tab is actually opened, not before.
    if (!old.isActive && widget.isActive) _load();
  }

  @override
  void dispose() {
    // Abandon any in-flight generation: its token can never match again.
    _generation++;
    _notes.dispose();
    _study.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stored = _storage.studyExerciseForDay(DateTime.now());
    setState(() {
      _today = stored;
      _notes.text = stored?.notes ?? '';
    });
    // Reading what is stored is free and keeps the tab instant when opened.
    // Generating is not, so it waits until someone is actually looking.
    if (!widget.isActive) return;
    if (StudyExercise.needsGeneration(stored)) await _ensureToday();
  }

  /// The last fortnight of titles and forms, so the model is told what it has
  /// already done rather than rediscovering its three favourite practices.
  ({List<String> titles, List<String> forms}) _recent() {
    final recent = _storage.loadStudyExercises().take(14);
    return (
      titles: [
        for (final e in recent)
          if (e.title.trim().isNotEmpty) e.title
      ],
      forms: [
        for (final e in recent)
          if (e.form.trim().isNotEmpty) e.form
      ],
    );
  }

  Future<void> _ensureToday({bool force = false}) async {
    final gen = ++_generation;
    final recent = _recent();

    // Show a real exercise INSTANTLY (never a blank tab), then quietly upgrade
    // to the generated one when it lands.
    setState(() {
      _busy = true;
      _error = null;
      if (force || StudyExercise.needsGeneration(_today)) {
        _today = _study.fallbackFor(DateTime.now());
        _notes.text = '';
      }
    });

    final fresh = await _study.generate(
      recentTitles: recent.titles,
      recentForms: recent.forms,
      progress: _status,
    );
    if (!mounted || gen != _generation) return;

    setState(() {
      _busy = false;
      _error = _study.lastGenerateError;
      _today = fresh;
      _notes.text = fresh.notes;
    });
    await _storage.saveStudyExercise(fresh);
  }

  Future<void> _saveNotes() async {
    final today = _today;
    if (today == null) return;
    today.notes = _notes.text;
    await _storage.saveStudyExercise(today);
  }

  Future<void> _toggleComplete() async {
    final today = _today;
    if (today == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      today.completedAt = today.isComplete ? null : DateTime.now();
      today.notes = _notes.text;
    });
    await _storage.saveStudyExercise(today);
  }

  /// Replacing an exercise someone has worked through would throw away their
  /// notes, so ask first when there is anything to lose.
  Future<void> _requestNew() async {
    final today = _today;
    final hasWork =
        today != null && (today.isComplete || _notes.text.trim().isNotEmpty);
    if (hasWork) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ExodusTheme.midnight,
          title: const Text('Replace today\'s exercise?'),
          content: const Text(
              'What you have written against this one will be lost.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep it')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace',
                    style: TextStyle(color: ExodusTheme.crimson))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _ensureToday(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    return Scaffold(
      appBar: AppBar(
        title: const Text('STUDY'),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: ExodusTheme.ironMist),
          tooltip: 'Menu',
          onPressed: widget.onOpenMenu,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded,
                color: ExodusTheme.ironMist),
            tooltip: 'Past exercises',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const StudyHistoryScreen()));
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: ExodusTheme.ironMist),
            tooltip: 'A different exercise',
            onPressed: _busy ? null : _requestNew,
          ),
        ],
      ),
      body: SafeArea(
        child: today == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ProgressStrip(controller: _status),
                    ),
                  Expanded(child: _exercise(today)),
                ],
              ),
      ),
    );
  }

  Widget _exercise(StudyExercise e) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _header(e),
        const SizedBox(height: 20),
        if (e.scriptureText.trim().isNotEmpty) ...[
          _scripture(e),
          const SizedBox(height: 24),
        ],
        _sectionLabel('THE PRACTICE'),
        const SizedBox(height: 12),
        for (var i = 0; i < e.steps.length; i++) _step(i + 1, e.steps[i]),
        if (e.question.trim().isNotEmpty) ...[
          const SizedBox(height: 26),
          _sectionLabel('SIT WITH THIS'),
          const SizedBox(height: 12),
          Text(e.question,
              style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w500,
              )),
          const SizedBox(height: 14),
          _notesField(),
        ],
        if (e.closingPrayer.trim().isNotEmpty) ...[
          const SizedBox(height: 26),
          _prayer(e.closingPrayer),
        ],
        const SizedBox(height: 26),
        _completeButton(e),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _fallbackNotice(),
        ],
      ],
    );
  }

  Widget _header(StudyExercise e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ExodusShield(size: 18, glow: false),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                e.form.trim().isEmpty
                    ? 'TODAY\'S EXERCISE'
                    : e.form.trim().toUpperCase(),
                style: const TextStyle(
                  color: ExodusTheme.brass,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            if (e.isComplete)
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: ExodusTheme.brass),
          ],
        ),
        const SizedBox(height: 12),
        Text(e.title,
            style: const TextStyle(
              color: ExodusTheme.porcelain,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.3,
            )),
        if (e.premise.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(e.premise,
              style: const TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 14,
                height: 1.5,
              )),
        ],
      ],
    );
  }

  Widget _scripture(StudyExercise e) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.brass.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.scriptureText,
              style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 15,
                height: 1.6,
                fontStyle: FontStyle.italic,
              )),
          if (e.scriptureRef.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            // Opens the in-app Bible at the passage, same as everywhere else.
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openScriptureRef(context, e.scriptureRef),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded,
                        size: 14, color: ExodusTheme.brass),
                    const SizedBox(width: 7),
                    Text(e.scriptureRef,
                        style: const TextStyle(
                          color: ExodusTheme.brass,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ExodusTheme.slate,
              border: Border.all(color: ExodusTheme.steel),
              shape: BoxShape.circle,
            ),
            child: Text('$number',
                style: const TextStyle(
                  color: ExodusTheme.covenantGlow,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text,
                  style: const TextStyle(
                    color: ExodusTheme.porcelain,
                    fontSize: 15,
                    height: 1.6,
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesField() {
    return TextField(
      controller: _notes,
      maxLines: 6,
      minLines: 3,
      style: const TextStyle(color: ExodusTheme.porcelain, fontSize: 15),
      // Written on the device and nowhere else; saved when focus leaves so
      // there's no Save button to forget.
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(_saveNotes());
      },
      onEditingComplete: () => unawaited(_saveNotes()),
      decoration: const InputDecoration(
        hintText: 'Write your answer here…',
      ),
    );
  }

  Widget _prayer(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CLOSE WITH THIS',
              style: TextStyle(
                color: ExodusTheme.ironMist,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              )),
          const SizedBox(height: 10),
          Text(text,
              style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 15,
                height: 1.6,
              )),
        ],
      ),
    );
  }

  Widget _completeButton(StudyExercise e) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _toggleComplete,
        icon: Icon(
            e.isComplete
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20),
        label: Text(e.isComplete ? 'Done today' : 'Mark this done',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        style: FilledButton.styleFrom(
          backgroundColor:
              e.isComplete ? ExodusTheme.slate : ExodusTheme.covenantBlue,
          foregroundColor:
              e.isComplete ? ExodusTheme.brass : ExodusTheme.porcelain,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: e.isComplete ? ExodusTheme.steel : Colors.transparent),
          ),
        ),
      ),
    );
  }

  /// Says plainly that this is canned content, rather than passing a fallback
  /// off as a fresh exercise.
  Widget _fallbackNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ExodusTheme.midnight,
        border: Border.all(color: ExodusTheme.steel),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: ExodusTheme.ironMist),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a built-in exercise — $_error Tap refresh above to try '
              'for a fresh one.',
              style: const TextStyle(
                  color: ExodusTheme.ironMist, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
        color: ExodusTheme.ironMist,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ));
}
