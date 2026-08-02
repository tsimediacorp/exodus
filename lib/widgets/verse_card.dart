import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/exodus_theme.dart';
import 'exodus_shield.dart';

/// A shareable card for a single passage. Rendered as a real widget and
/// captured to a PNG, so what gets shared is exactly what's on screen.
class VerseCard extends StatelessWidget {
  final String reference;
  final String text;

  const VerseCard({super.key, required this.reference, required this.text});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // 4:5 — the portrait ratio social apps crop least aggressively.
      aspectRatio: 4 / 5,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [ExodusTheme.obsidian, ExodusTheme.midnight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -30,
              right: -30,
              child: Opacity(
                opacity: 0.05,
                child: ExodusShield(size: 200, glow: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 34, 30, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 3,
                    decoration: BoxDecoration(
                      color: ExodusTheme.brass,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    flex: 8,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          '“$text”',
                          style: const TextStyle(
                            color: ExodusTheme.porcelain,
                            fontSize: 21,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    reference.toUpperCase(),
                    style: const TextStyle(
                      color: ExodusTheme.brass,
                      fontSize: 13,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const ExodusShield(size: 20, glow: false),
                      const SizedBox(width: 8),
                      Text(
                        'EXODUS',
                        style: TextStyle(
                          color: ExodusTheme.ironMist.withValues(alpha: 0.7),
                          fontSize: 11,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that previews the card and shares or copies it.
class VerseCardSheet extends StatefulWidget {
  final String reference;
  final String text;

  const VerseCardSheet({super.key, required this.reference, required this.text});

  @override
  State<VerseCardSheet> createState() => _VerseCardSheetState();
}

class _VerseCardSheetState extends State<VerseCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  /// Rasterise the previewed card at 3x so it stays crisp when a social app
  /// scales it up.
  Future<Uint8List?> _capture() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Anchor the share sheet on iPad, where an unanchored popover is
      // centred rather than pointing at what was tapped. Captured before the
      // first await so the render object is read while the tree is current.
      final box = context.findRenderObject() as RenderBox?;

      final bytes = await _capture();
      if (bytes == null) throw Exception('Could not render the card.');

      // systemTemp maps to NSTemporaryDirectory on iOS — no path_provider
      // dependency needed for a file the OS is free to clean up.
      final file = File(
          '${Directory.systemTemp.path}/exodus-verse-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: widget.reference,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not share: ${'$e'.replaceFirst('Exception: ', '')}'),
          backgroundColor: ExodusTheme.steel,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(
        text: '"${widget.text}"\n— ${widget.reference}'));
    HapticFeedback.selectionClick();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Verse copied'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ExodusTheme.steel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: VerseCard(
                      reference: widget.reference, text: widget.text),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _copyText,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ExodusTheme.ironMist,
                      side: const BorderSide(color: ExodusTheme.steel),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy text'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    style: FilledButton.styleFrom(
                      backgroundColor: ExodusTheme.covenantBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ExodusTheme.porcelain),
                          )
                        : const Icon(Icons.ios_share_rounded,
                            size: 18, color: ExodusTheme.porcelain),
                    label: const Text('Share card',
                        style: TextStyle(color: ExodusTheme.porcelain)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
