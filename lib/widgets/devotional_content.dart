import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/devotional.dart';
import '../models/saved_verse.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../theme/exodus_theme.dart';
import 'scripture_link.dart';
import 'verse_card.dart';

/// Renders one devotional or journey day — title, scripture, reflection,
/// prayer, and the together-action — plus the actions that go with it
/// (listen aloud, keep the verse, share it as a card).
///
/// Shared by the Devotional tab and journey days: both are the same shape,
/// and the daily devotional's own card used to be a private method on its
/// screen, so journey days would have duplicated it.
class DevotionalContent extends StatefulWidget {
  final Devotional devotional;

  /// Context stored alongside a kept verse ("Daily devotional", a plan title).
  final String source;

  /// Whether the together-action can be ticked off. Journey days track
  /// completion themselves, so they turn this off.
  final bool showActionToggle;

  const DevotionalContent({
    super.key,
    required this.devotional,
    required this.source,
    this.showActionToggle = false,
  });

  @override
  State<DevotionalContent> createState() => _DevotionalContentState();
}

class _DevotionalContentState extends State<DevotionalContent> {
  final StorageService _storage = StorageService.instance;

  /// Stable key for the TTS service so the play/stop state follows this
  /// devotional rather than whatever spoke last.
  String get _ttsKey => 'devotional:${widget.devotional.dayKey}';

  bool get _hasVerse =>
      widget.devotional.scriptureRef.trim().isNotEmpty &&
      widget.devotional.scriptureText.trim().isNotEmpty;

  bool get _verseSaved =>
      _storage.isVerseSaved(widget.devotional.scriptureRef.trim());

  bool get _actionDone =>
      _storage.loadActionDays().contains(widget.devotional.dayKey);

  /// Everything read aloud, in the order it appears on screen.
  String get _spokenText {
    final d = widget.devotional;
    return [
      d.title,
      if (d.scriptureRef.isNotEmpty) d.scriptureRef,
      if (d.scriptureText.isNotEmpty) d.scriptureText,
      if (d.reflection.isNotEmpty) d.reflection,
      if (d.prayer.isNotEmpty) 'Let us pray. ${d.prayer}',
      if (d.action.isNotEmpty) 'Together today: ${d.action}',
    ].join('\n\n');
  }

  Future<void> _toggleVerse() async {
    HapticFeedback.selectionClick();
    final ref = widget.devotional.scriptureRef.trim();
    if (_verseSaved) {
      await _storage.removeVerse(ref);
    } else {
      await _storage.saveVerse(SavedVerse(
        reference: ref,
        text: widget.devotional.scriptureText.trim(),
        source: widget.source,
      ));
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleAction() async {
    HapticFeedback.selectionClick();
    await _storage.setActionDone(widget.devotional.dayKey, !_actionDone);
    if (mounted) setState(() {});
  }

  void _shareVerse() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VerseCardSheet(
        reference: widget.devotional.scriptureRef,
        text: widget.devotional.scriptureText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.devotional;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.title,
            style: const TextStyle(
                color: ExodusTheme.porcelain,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2)),
        const SizedBox(height: 14),
        _actionRow(),
        const SizedBox(height: 18),
        if (_hasVerse) _scriptureSection(d.scriptureRef, d.scriptureText),
        if (d.reflection.isNotEmpty) _section('Reflection', d.reflection),
        if (d.prayer.isNotEmpty) _section('Prayer', d.prayer, italic: true),
        if (d.action.isNotEmpty) _actionSection(d.action),
      ],
    );
  }

  Widget _actionRow() {
    return ValueListenableBuilder<String?>(
      valueListenable: TtsService.instance.speakingKey,
      builder: (_, speakingKey, __) {
        final speaking = speakingKey == _ttsKey;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill(
              icon: speaking ? Icons.stop_rounded : Icons.headphones_rounded,
              label: speaking ? 'Stop' : 'Listen',
              highlight: speaking,
              onTap: () => TtsService.instance.toggle(_ttsKey, _spokenText),
            ),
            if (_hasVerse)
              _pill(
                icon: _verseSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: _verseSaved ? 'Kept' : 'Keep verse',
                highlight: _verseSaved,
                onTap: _toggleVerse,
              ),
            if (_hasVerse)
              _pill(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: _shareVerse,
              ),
          ],
        );
      },
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    final color = highlight ? ExodusTheme.brass : ExodusTheme.ironMist;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: highlight ? ExodusTheme.brass : ExodusTheme.steel),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The scripture block, with its reference tappable so the couple can read
  /// the passage in context in the in-app Bible.
  Widget _scriptureSection(String reference, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScriptureLink(reference: reference),
          const SizedBox(height: 4),
          SelectableText(body,
              style: const TextStyle(
                  color: ExodusTheme.porcelain,
                  fontSize: 15,
                  height: 1.55,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Read $reference in context',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openScriptureRef(context, reference),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 15, color: ExodusTheme.covenantGlow),
                    SizedBox(width: 7),
                    Text('Read it in context',
                        style: TextStyle(
                            color: ExodusTheme.covenantGlow,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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

  /// The together-action, optionally tickable so it can drive a streak.
  Widget _actionSection(String body) {
    if (!widget.showActionToggle) {
      return _section('Together today', body);
    }
    final done = _actionDone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: done
              ? ExodusTheme.brass.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(color: done ? ExodusTheme.brass : ExodusTheme.steel),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TOGETHER TODAY',
                style: TextStyle(
                    color: ExodusTheme.brass,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SelectableText(body,
                style: const TextStyle(
                    color: ExodusTheme.porcelain, fontSize: 15, height: 1.55)),
            const SizedBox(height: 10),
            Semantics(
              button: true,
              checked: done,
              label: 'Mark today\'s action done',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleAction,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: done ? ExodusTheme.brass : ExodusTheme.ironMist,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        done ? 'Done together' : 'Mark as done',
                        style: TextStyle(
                          color:
                              done ? ExodusTheme.brass : ExodusTheme.ironMist,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
