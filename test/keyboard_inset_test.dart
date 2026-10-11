import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exodus/widgets/keyboard_inset_guard.dart';

/// The screen sometimes stayed squeezed after the keyboard had gone: the
/// platform's last report of the keyboard's height outlived the keyboard, and
/// every Scaffold kept making room for it.
void main() {
  double? seen;
  final focus = FocusNode();

  Widget app({required double inset}) => MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: inset),
        ),
        child: MaterialApp(
          // Mirrors main.dart: the guard sits above every route.
          builder: (context, child) => KeyboardInsetGuard(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus),
                Builder(builder: (context) {
                  seen = MediaQuery.viewInsetsOf(context).bottom;
                  return const SizedBox();
                }),
              ],
            ),
          ),
        ),
      );

  testWidgets('a keyboard inset with no text field focused is not believed',
      (tester) async {
    await tester.pumpWidget(app(inset: 336));
    expect(focus.hasFocus, isFalse);

    // The Scaffold has already consumed the inset for its body, so what the
    // body sees is whether the Scaffold was given one to consume.
    final full = tester.getSize(find.byType(Scaffold)).height;
    expect(tester.getSize(find.byType(Column)).height, full,
        reason: 'the page should be full height');
    expect(seen, 0);
  });

  testWidgets('the same inset is honoured while typing', (tester) async {
    await tester.pumpWidget(app(inset: 336));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final full = tester.getSize(find.byType(Scaffold)).height;
    expect(tester.getSize(find.byType(Column)).height, full - 336);

    // And released the moment the field lets go, whatever the platform says.
    focus.unfocus();
    await tester.pump();
    expect(tester.getSize(find.byType(Column)).height, full);
  });

  testWidgets('gaining focus does not rebuild the app from scratch',
      (tester) async {
    await tester.pumpWidget(app(inset: 0));
    await tester.enterText(find.byType(TextField), 'kept');
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    // If the guard swapped its wrapper in and out, the field underneath would
    // be a new one and the text gone.
    expect(find.text('kept'), findsOneWidget);
  });

  testWidgets('leaving the app lets go of the keyboard', (tester) async {
    await tester.pumpWidget(app(inset: 336));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(focus.hasFocus, isFalse);

    // Back the way it came, so the binding is left as the next test expects.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
