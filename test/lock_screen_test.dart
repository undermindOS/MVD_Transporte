// The lock screens are the LED board. The older lock: what it shows, that
// it asks the system prompt once at a time, and that it can stand still.
// The code lock: the keypad, the quick unlock key and «¿Olvidaste el
// código?» reach the lock; while a system prompt is open the lock scans and
// every key waits; a phone without a screen lock gets its note (Android,
// iOS) as a live region; reduced motion stills it. The new code after a
// forgotten one: both steps and «Ahora no». With real fonts on a phone
// screen every word stays whole at 1×, 1.3× and 2× and the keys keep their
// size; at 1× neither scrolls. Any overflow fails the test.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/lock_screen.dart';
import 'package:stm_app/ui/passcode_entry.dart';
import 'package:stm_app/ui/theme/timbre_text.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/led_board.dart';
import 'package:stm_app/ui/widgets/led_keypad.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';

import 'support/layout.dart';

const _androidNote = 'Tu teléfono no tiene bloqueo de pantalla, así que no '
    'puede confirmar que sos vos. Para entrar sin el código, borrá los datos '
    'de Timbre MVD en los ajustes del teléfono: se borran tus paradas y '
    'rutas.';
const _iosNote = 'Tu teléfono no tiene bloqueo de pantalla, así que no puede '
    'confirmar que sos vos. Para entrar sin el código, borrá Timbre MVD y '
    'volvé a instalarla: se borran tus paradas y rutas.';

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

CodeLockScreen _codeLock({
  Future<PasscodeFeedback?> Function(String code)? onCode,
  Future<void> Function()? onForgot,
  PasscodeBiometric? biometric,
  bool scanning = false,
  bool noScreenLock = false,
}) =>
    CodeLockScreen(
      onCode: onCode ?? (_) async => null,
      onForgot: onForgot ?? () async {},
      biometric: biometric,
      scanning: scanning,
      noScreenLock: noScreenLock,
    );

PasscodeBiometric _fingerprint([VoidCallback? onPressed]) => PasscodeBiometric(
    kind: BiometricKind.fingerprint, onPressed: onPressed ?? () {});

Future<void> _type(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await tester.ensureVisible(find.text(digit));
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

Matcher _key({required bool on}) =>
    isSemantics(isButton: true, hasEnabledState: true, isEnabled: on);

/// Every word on the board whole, every key at its size, the sign at 19 px
/// or more and within the board; at 1× the board does not scroll.
void _fits(WidgetTester tester, double scale, String sign) {
  for (final text in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: find.byType(LedBoard), matching: find.byType(Text)))) {
    expect(text.didExceedMaxLines, isFalse, reason: text.text.toPlainText());
  }
  for (final label in ['0', '5', '9']) {
    final key = tester.getRect(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    expect(key.width, closeTo(LedKeypad.keyWidth, 0.01), reason: label);
    expect(key.height, closeTo(LedKeypad.keyHeight, 0.01), reason: label);
  }
  final signRect = tester.getRect(find.text(sign));
  expect(signRect.height, greaterThanOrEqualTo(TimbreFonts.dotoMinSize));
  expect(signRect.width, lessThanOrEqualTo(390 - 2 * 24 + 0.5));
  if (scale == 1) {
    final board = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(board.position.maxScrollExtent, 0, reason: 'scrolls at 1x');
  }
  expect(find.byType(CartelCompacto), findsOneWidget);
}

void main() {
  setUpAll(loadBundledFonts);

  group('the older lock', () {
    testWidgets('lock, BLOQUEADA and the unlock button', (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(LockScreen(onUnlock: () async {})));

      expect(find.byType(LedBoard), findsOneWidget);
      expect(find.byType(LedLock), findsOneWidget);
      expect(find.text('BLOQUEADA'), findsOneWidget);
      expect(find.bySemanticsLabel('Aplicación bloqueada'), findsOneWidget);
      expect(find.text('Tus paradas y rutas guardadas están protegidas'),
          findsOneWidget);
      expect(find.text('Desbloquear'), findsOneWidget);
      expect(find.byType(CartelCompacto), findsOneWidget);
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
  });

  group('the code lock', () {
    testWidgets('the board: a smaller lock, BLOQUEADA, the keypad and '
        '«¿Olvidaste el código?»', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_codeLock()));

      expect(find.byType(LedBoard), findsOneWidget);
      expect(tester.widget<LedLock>(find.byType(LedLock)).pitch, 6);
      expect(tester.widget<LedLock>(find.byType(LedLock)).scanning, isFalse);
      expect(find.text('BLOQUEADA'), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel('Aplicación bloqueada')),
          isSemantics(isHeader: true));
      expect(find.text('Ingresá tu código'), findsOneWidget);
      expect(find.byType(LedKeypad), findsOneWidget);
      expect(find.text('¿Olvidaste el código?'), findsOneWidget);
      expect(find.byType(CartelCompacto), findsOneWidget);
      // No quick unlock key without it, no note
      expect(find.bySemanticsLabel(RegExp('^Desbloquear con')), findsNothing);
      expect(find.text(_androidNote), findsNothing);
    });

    testWidgets('the keypad, the quick unlock key and «¿Olvidaste el '
        'código?» reach the lock', (tester) async {
      usePhoneScreen(tester);
      final codes = <String>[];
      var quick = 0;
      var forgot = 0;
      await tester.pumpWidget(_app(_codeLock(
        onCode: (code) async {
          codes.add(code);
          return const PasscodeError('Código incorrecto');
        },
        onForgot: () async => forgot++,
        biometric: _fingerprint(() => quick++),
      )));

      await _type(tester, '2580');
      expect(codes, ['2580']);
      expect(find.text('Código incorrecto'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.bySemanticsLabel('Desbloquear con huella'));
      await tester.pump();
      expect(quick, 1);

      await tester.tap(find.text('¿Olvidaste el código?'));
      await tester.pump();
      expect(forgot, 1);
    });

    testWidgets('a system prompt open: the lock scans and every key waits, '
        '«¿Olvidaste el código?» too', (tester) async {
      usePhoneScreen(tester);
      final codes = <String>[];
      Widget screen({required bool scanning}) => _app(_codeLock(
            onCode: (code) async {
              codes.add(code);
              return null;
            },
            biometric: _fingerprint(),
            scanning: scanning,
          ));
      await tester.pumpWidget(screen(scanning: true));

      expect(tester.widget<LedLock>(find.byType(LedLock)).scanning, isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: false));
      expect(tester.getSemantics(find.bySemanticsLabel('Desbloquear con huella')),
          _key(on: false));
      expect(
          tester
              .widget<TextButton>(find.ancestor(
                  of: find.text('¿Olvidaste el código?'),
                  matching: find.byType(TextButton)))
              .onPressed,
          isNull);
      await _type(tester, '1234');
      expect(codes, isEmpty);

      // The prompt closed: the same screen, keys on again
      await tester.pumpWidget(screen(scanning: false));
      expect(tester.widget<LedLock>(find.byType(LedLock)).scanning, isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Desbloquear con huella')),
          _key(on: true));
      await _type(tester, '1234');
      expect(codes, ['1234']);
    });

    testWidgets('a phone without a screen lock: the note under the keypad, '
        'as a live region', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_codeLock(noScreenLock: true)));

      expect(find.text(_androidNote), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel(_androidNote)),
          isSemantics(isLiveRegion: true));
      expect(tester.getRect(find.text(_androidNote)).top,
          greaterThan(tester.getRect(find.byType(LedKeypad)).bottom));
      // Still a lock: the keypad and «¿Olvidaste el código?» stay
      expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: true));
      expect(find.text('¿Olvidaste el código?'), findsOneWidget);
    });

    testWidgets('a phone without a screen lock, on iOS: reinstall',
        (tester) async {
      usePhoneScreen(tester);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(_app(_codeLock(noScreenLock: true)));

      expect(find.text(_iosNote), findsOneWidget);
      expect(find.text(_androidNote), findsNothing);
      expect(tester.getSemantics(find.bySemanticsLabel(_iosNote)),
          isSemantics(isLiveRegion: true));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('boots like the older lock; reduced motion: still, also '
        'while it scans', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_codeLock()));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(_app(_codeLock(), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      // A scan would repeat forever: settling means the lock stays still
      // (the button's own short fade to disabled is the framework's)
      await tester.pumpWidget(_app(_codeLock(scanning: true), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(tester.widget<LedLock>(find.byType(LedLock)).scanning, isTrue);
      expect(tester.hasRunningAnimations, isFalse);
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Text at ${scale}x: the keypad, the quick unlock key and '
          'the note fit', (tester) async {
        usePhoneScreen(tester);
        await tester.pumpWidget(
            _app(_codeLock(biometric: _fingerprint()), textScale: scale));
        await _type(tester, '12');
        _fits(tester, scale, 'BLOQUEADA');

        await tester.pumpWidget(_app(
            _codeLock(biometric: _fingerprint(), noScreenLock: true),
            textScale: scale));
        expect(find.text(_androidNote), findsOneWidget);
        _fits(tester, scale, 'BLOQUEADA');
      });
    }
  });

  group('a new code after a forgotten one', () {
    testWidgets('the same code twice goes to the lock; «Ahora no» skips',
        (tester) async {
      usePhoneScreen(tester);
      final created = <String>[];
      var skipped = 0;
      await tester.pumpWidget(_app(NewCodeScreen(
        onCreated: (code) async => created.add(code),
        onSkip: () => skipped++,
      )));

      expect(find.text('CÓDIGO NUEVO'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Código nuevo')),
          isSemantics(isHeader: true));
      expect(find.text('Elegí 4 cifras nuevas para abrir la app.'),
          findsOneWidget);
      await _type(tester, '9137');
      expect(find.text('REPETILO'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      await _type(tester, '9137');
      expect(created, ['9137']);
      expect(skipped, 0);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(NewCodeScreen(
        onCreated: (code) async => created.add(code),
        onSkip: () => skipped++,
      )));
      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      expect(skipped, 1);
      expect(created, ['9137']);
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Text at ${scale}x: both steps fit', (tester) async {
        usePhoneScreen(tester);
        await tester.pumpWidget(_app(
            NewCodeScreen(onCreated: (_) async {}, onSkip: () {}),
            textScale: scale));
        expect(find.text('Ahora no'), findsOneWidget);
        _fits(tester, scale, 'CÓDIGO NUEVO');

        await _type(tester, '1234');
        expect(find.text('Volver'), findsOneWidget);
        _fits(tester, scale, 'REPETILO');
      });
    }
  });
}
