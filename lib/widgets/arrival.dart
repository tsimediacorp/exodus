import 'package:flutter/material.dart';

/// A reply settling onto the page rather than appearing on it.
///
/// Each child fades up and rises a few pixels, staggered by [step], so the
/// speaker rule lands first, then the prose, then the scripture, then whatever
/// follows. The interval is what does the work: simultaneous is a flicker, and
/// anything past ~150ms apart reads as slow.
///
/// [enabled] is false for everything except a reply that has just arrived.
/// Replaying this while scrolling back through a long conversation would be
/// unbearable, and it is why the parent decides rather than the widget.
class Arrival extends StatefulWidget {
  final List<Widget> children;
  final bool enabled;
  final Duration step;
  final Duration duration;
  final CrossAxisAlignment crossAxisAlignment;

  const Arrival({
    super.key,
    required this.children,
    this.enabled = true,
    this.step = const Duration(milliseconds: 110),
    this.duration = const Duration(milliseconds: 620),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  State<Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<Arrival> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final total = widget.duration +
        widget.step * (widget.children.length - 1).clamp(0, 10);
    _controller = AnimationController(vsync: this, duration: total);
    if (widget.enabled) {
      _controller.forward();
    } else {
      // Already settled: no animation, no frame cost.
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(Arrival old) {
    super.didUpdateWidget(old);
    // A reply that streams in grows its children as it goes. Restarting on
    // every rebuild would make the whole thing shudder, so once it has run it
    // stays run.
    if (!old.enabled && widget.enabled && _controller.value == 1) return;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        children: widget.children,
      );
    }

    final total = _controller.duration!.inMilliseconds;
    final span = widget.duration.inMilliseconds / total;

    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          AnimatedBuilder(
            animation: _controller,
            builder: (_, child) {
              final begin =
                  (widget.step.inMilliseconds * i / total).clamp(0.0, 1.0);
              final t = CurvedAnimation(
                parent: _controller,
                // easeOutQuint: fast out of the gate and a long settle, which
                // is what reads as weight rather than as a slide.
                curve: Interval(begin, (begin + span).clamp(0.0, 1.0),
                    curve: Curves.easeOutQuint),
              ).value;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 14),
                  child: child,
                ),
              );
            },
            child: widget.children[i],
          ),
      ],
    );
  }
}
