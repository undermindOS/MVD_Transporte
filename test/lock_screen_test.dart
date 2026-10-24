// The lock screen is the LED board: what it shows, that it asks the
// system prompt once at a time, and that it can stand still.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/ui/lock_screen.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';

import 'support/layout.dart';

Widget _app(Widget home, {bool reduceMotion = false, double textScale = 1}) =>
    MaterialApp(
      theme: buildTimbreTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    );

void main() {
  setUpAll(loadBundledFonts);

  testWidgets('lock, BLOQUEADA and the unlock button', (tester) async {
    usePhoneScreen(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(LockScreen(onUnlock: () async {})));

    expect(find.byType(LedLock), findsOneWidget);
    expect(find.text('BLOQUEADA'), findsOneWidget);
    expect(find.bySemanticsLabel('Aplicación bloqueada'), findsOneWidget);
    expect(find.text('Desbloquear'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('one prompt at a time: the button waits for the answer',
      (tester) async {
    usePhoneScreen(tester);
    var answer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(_app(LockScreen(onUnlock: () {
      calls++;
      return answer.future;
    })));

    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    await tester.tap(find.text('Desbloquear'), warnIfMissed: false);
    expect(calls, 1);

    answer.complete();
    answer = Completer<void>();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Desbloquear'));
    expect(calls, 2);
  });

  testWidgets('boots, then keeps a scan line going', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(_app(LockScreen(onUnlock: () async {})));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduced motion: a still, closed lock', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(
        _app(LockScreen(onUnlock: () async {}), reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('largest system font: nothing overflows', (tester) async {
    usePhoneScreen(tester);
    await tester
        .pumpWidget(_app(LockScreen(onUnlock: () async {}), textScale: 2));
    await tester.pump(const Duration(seconds: 2));
  });
}
