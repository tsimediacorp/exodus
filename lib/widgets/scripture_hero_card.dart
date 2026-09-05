import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bible_ref.dart';
import '../models/saved_verse.dart';
import '../services/bible_service.dart';
import '../services/storage_service.dart';
import '../theme/exodus_theme.dart';
import 'scripture_background.dart';
import 'scripture_link.dart';

/// The passage a reply is built on, given its own card.
///
/// One per reply at most, and only when EXODUS marked a genuine anchor. A
/// card on every reply would make the card mean nothing — the whole point is
/// that seeing one tells the couple THIS is the verse to carry, while the
/// supporting references stay as quiet citations underneath.
class ScriptureHeroCard extends StatefulWidget {
  final BibleRef reference;

  const ScriptureHeroCard({super.key, required this.reference});

  @override
  State<ScriptureHeroCard> createState() => _ScriptureHeroCardState();
}

class _ScriptureHeroCardState extends State<ScriptureHeroCard> {
  late String _label;
  late String _text;
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(ScriptureHeroCard old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) _read();
  }

  void _read() {
    final bible = BibleService.instance;
    _label = bible.label(widget.reference);
    _text = bible.textFor(widget.reference);
    _saved = StorageService.instance.isVerseSaved(_label);
  }

  Future<void> _toggleSaved() async {
    HapticFeedback.mediumImpact();
    final storage = StorageService.instance;
    if (_saved) {
      await storage.removeVerse(_label);
    } else {
      await storage.saveVerse(SavedVerse(
        reference: _label,
        text: _text,
        source: '${BibleService.translation} · from a conversation',
      ));
    }
    if (mounted) setState(() => _saved = !_saved);
  }

  @override
  Widget build(BuildContext context) {
    // Without the translation loaded there is no verse to set, and a card
    // showing only a reference is worse than the plain citation it replaced.
    if (_text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Semantics(
        button: true,
        label: 'Open $_label in the Bible',
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openScripture(context, widget.reference),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: ExodusTheme.brass.withValues(alpha: 0.42)),
            ),
            child: Stack(
              children: [
                // Seeded on the reference, so this passage always looks like
                // itself rather than reshuffling as the thread rebuilds.
                Positioned.fill(child: ScriptureBackground(seed: _label)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('SCRIPTURE FOR YOU',
                                style: TextStyle(
                                  color: ExodusTheme.brass,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.2,
                                )),
                            const SizedBox(height: 14),
                            Text(
                              '“$_text”',
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: ExodusTheme.serif,
                                color: Color(0xFFF3EFE6),
                                fontSize: 19,
                                height: 1.45,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The brass rule from the design, marking the
                                // citation as separate from the verse.
                                Container(
                                  width: 3,
                                  height: 15,
                                  color: ExodusTheme.brass,
                                ),
                                const SizedBox(width: 10),
                                Text(_label.toUpperCase(),
                                    style: const TextStyle(
                                      color: ExodusTheme.brass,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2,
                                    )),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Semantics(
                        button: true,
                        label: _saved ? 'Remove from saved verses' : 'Save this verse',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _toggleSaved,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ExodusTheme.obsidian.withValues(alpha: 0.42),
                              border: Border.all(
                                  color: ExodusTheme.brass
                                      .withValues(alpha: 0.55)),
                            ),
                            child: Icon(
                              _saved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 21,
                              color: ExodusTheme.brass,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
