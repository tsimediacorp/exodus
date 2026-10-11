import 'dart:async';

import 'package:flutter/material.dart';

import '../services/voice_input_service.dart';
import '../theme/exodus_theme.dart';

/// What the composer becomes while EXODUS is listening.
///
/// Takes the place of the text field rather than sitting over it, so the pill
/// stays one object: cancel on the left where attach was, the live waveform
/// and the clock where the words will go, and on the right the two ways out —
/// put it in the composer to read over, or send it as spoken.
class DictationBar extends StatefulWidget {
  final VoiceInputService voice;

  /// True once recording has stopped and the words are on their way back.
  final bool transcribing;

  final VoidCallback onCancel;

  /// Stop and place the transcript in the composer.
  final VoidCallback onDone;

  /// Stop and send the transcript straight away.
  final VoidCallback onSend;

  const DictationBar({
    super.key,
    required this.voice,
    required this.transcribing,
    required this.onCancel,
    required this.onDone,
    required this.onSend,
  });

  @override
  State<DictationBar> createState() => _DictationBarState();
}

class _DictationBarState extends State<DictationBar>
    with SingleTickerProviderStateMixin {
  Timer? _clock;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && !widget.transcribing) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  static String clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final remaining = VoiceInputService.maxDuration - widget.voice.elapsed;
    final nearlyOut = remaining <= const Duration(seconds: 20);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded, size: 21),
            color: ExodusTheme.ironMist,
            tooltip: 'Cancel recording',
            onPressed: widget.onCancel,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 40,
            child: widget.transcribing
                ? const _Transcribing()
                : Row(
                    children: [
                      // Breathing, not blinking: a hard blink reads as an
                      // alarm, and this is someone being listened to.
                      FadeTransition(
                        opacity:
                            Tween(begin: 0.35, end: 1.0).animate(_pulse),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: ExodusTheme.crimson,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ValueListenableBuilder<List<double>>(
                          valueListenable: widget.voice.levels,
                          builder: (_, levels, __) => CustomPaint(
                            size: const Size(double.infinity, 30),
                            painter: WaveformPainter(levels),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        nearlyOut
                            ? '${remaining.inSeconds.clamp(0, 99)}s left'
                            : clock(widget.voice.elapsed),
                        style: TextStyle(
                          color: nearlyOut
                              ? ExodusTheme.brassGlow
                              : ExodusTheme.ironMist,
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
          ),
        ),
        if (!widget.transcribing) ...[
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.check_rounded, size: 22),
              color: ExodusTheme.porcelain,
              tooltip: 'Stop and review',
              onPressed: widget.onDone,
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: 'Stop and send',
            child: GestureDetector(
              onTap: widget.onSend,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [ExodusTheme.brassGlow, ExodusTheme.brass],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ExodusTheme.brass.withValues(alpha: 0.34),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_upward,
                    color: ExodusTheme.obsidian, size: 20),
              ),
            ),
          ),
        ] else
          const SizedBox(width: 8),
      ],
    );
  }
}

class _Transcribing extends StatelessWidget {
  const _Transcribing();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 1.8, color: ExodusTheme.brass),
        ),
        SizedBox(width: 12),
        Text(
          'Writing down what you said…',
          style: TextStyle(
            fontFamily: ExodusTheme.serif,
            color: ExodusTheme.ironMist,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// The last few seconds of someone's voice, as bars.
///
/// Right-aligned and scrolling left, so the newest sound is always beside the
/// clock and the bar reads as time passing rather than as a meter.
class WaveformPainter extends CustomPainter {
  final List<double> levels;
  WaveformPainter(this.levels);

  static const double _bar = 2.5;
  static const double _gap = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_bar + _gap)).floor();
    if (count <= 0) return;
    final mid = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      // i == count - 1 is the newest sample.
      final at = levels.length - (count - i);
      final level = at >= 0 && at < levels.length ? levels[at] : 0.0;
      // Never fully flat: silence still draws a row of dots, so the bar looks
      // like it is listening rather than broken.
      final h = 2.0 + level * (size.height - 2.0);
      final x = i * (_bar + _gap) + _bar / 2;
      // Older sound fades toward the left edge.
      final age = i / count;
      paint
        ..strokeWidth = _bar
        ..color = Color.lerp(
          ExodusTheme.steel,
          ExodusTheme.brass,
          (0.25 + 0.75 * age) * (0.35 + 0.65 * level),
        )!;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) => !identical(old.levels, levels);
}
