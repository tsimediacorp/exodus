import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Stops a screen staying squeezed after the keyboard has gone.
///
/// Every Scaffold shrinks its body by `MediaQuery.viewInsets.bottom`, which is
/// the platform's report of how much of the window the keyboard covers. That
/// report is occasionally wrong: when the keyboard is dismissed by something
/// other than the text field giving up focus — a photo picker or a permission
/// dialog presented over it, the app going to the background with it open —
/// the "keyboard hidden" update can be missed, and the last inset is left in
/// place. Nothing then corrects it, so the page sits in the top half of the
/// screen above an empty gap until the keyboard is opened and closed again.
///
/// The keyboard cannot be up unless a text field holds focus. So the inset is
/// believed only while one does, and treated as zero otherwise. A stale value
/// then has nothing to act on, on every screen at once, without any of them
/// knowing this exists.
class KeyboardInsetGuard extends StatefulWidget {
  final Widget child;
  const KeyboardInsetGuard({super.key, required this.child});

  /// Whether a text field currently holds focus.
  static bool get textFieldFocused {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard>
    with WidgetsBindingObserver {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _editing = KeyboardInsetGuard.textFieldFocused;
    FocusManager.instance.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onFocusChanged() {
    // Focus also changes while a route is being torn down, mid-frame, when
    // the tree cannot be inspected or rebuilt. Wait for the frame to finish.
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _sync());
      return;
    }
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final editing = KeyboardInsetGuard.textFieldFocused;
    if (editing != _editing) setState(() => _editing = editing);
  }

  /// Leaving the app with the keyboard up is the commonest way to come back
  /// to a stale inset, and a field that is still focused would keep it
  /// believed. Letting go of focus on the way out means the app always
  /// returns at full height; one tap brings the keyboard back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Always the same wrapper, whether or not it changes anything: swapping
    // between "wrapped" and "not wrapped" would remount the whole app beneath
    // it every time a text field gained or lost focus.
    return MediaQuery(
      data: _editing
          ? media
          : media.copyWith(viewInsets: media.viewInsets.copyWith(bottom: 0)),
      child: widget.child,
    );
  }
}
