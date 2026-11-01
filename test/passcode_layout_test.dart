// The code keypad on the LED board, with real fonts on a phone screen: the
// lock (LedLock, the quick unlock key, «¿Olvidaste el código?»), its wrong
// code and its wait, and both steps of a new code under the welcome's step
// dots keep every word whole at 1×, 1.3× and 2×, the keys keep their size
// and the sign never drops below 19 px; at 1× each fits without scrolling.
// Any overflow fails the test.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/passcode_entry.dart';
import 'package:stm_app/ui/theme/timbre_text.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/led_board.dart';
import 'package:stm_app/ui/widgets/led_keypad.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';

import 'support/layout.dart';

Widget _app(Widget board, double scale) => MaterialApp(
  theme: buildTimbreTheme(),
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: navigator!,
  ),
  home: board,
);

// The code lock as the lead builds it: the lock with a smaller pitch
Widget _lock({Future<PasscodeFeedback?> Function(String code)? onSubmit}) =>
    LedBoard(
      child: PasscodeEntry(
        sign: 'BLOQUEADA',
        signLabel: 'Aplicación bloqueada',
        message: 'Ingresá tu código',
        onSubmit: onSubmit ?? (_) async => null,
        leading: const LedLock(pitch: 6),
        biometric: PasscodeBiometric(
          kind: BiometricKind.fingerprint,
          onPressed: () {},
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('¿Olvidaste el código?'),
          ),
        ],
      ),
    );

// The welcome's step: four small squares on top
Widget _newCode() => LedBoard(
  header: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 4; i++)
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: i == 2 ? TimbreColors.ambar : TimbreColors.lineaNoche,
        ),
    ],
  ),
  child: PasscodeCreate(
    sign: 'TU CÓDIGO',
    signLabel: 'Tu código',
    message: 'Elegí 4 cifras para abrir la app.',
    actions: [TextButton(onPressed: () {}, child: const Text('Ahora no'))],
    onCreated: (_) async {},
  ),
);

Future<void> _type(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await tester.ensureVisible(find.text(digit));
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

/// Every word on the board whole, every key at its size, the sign at 19 px
/// or more; at 1× the board does not scroll.
void _fits(WidgetTester tester, double scale, String sign) {
  for (final text in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: find.byType(LedBoard), matching: find.byType(Text)),
  )) {
    expect(text.didExceedMaxLines, isFalse, reason: text.text.toPlainText());
  }
  for (final label in ['0', '5', '9']) {
    final key = tester.getRect(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );
    expect(key.width, closeTo(LedKeypad.keyWidth, 0.01), reason: label);
    expect(key.height, closeTo(LedKeypad.keyHeight, 0.01), reason: label);
    // The digit inside its key
    final digit = tester.getRect(find.text(label));
    expect(
      key.contains(digit.topLeft) && key.contains(digit.bottomRight),
      isTrue,
      reason: label,
    );
  }
  expect(
    tester.getRect(find.text(sign)).height,
    greaterThanOrEqualTo(TimbreFonts.dotoMinSize),
  );
  expect(
    tester.getRect(find.text(sign)).width,
    lessThanOrEqualTo(390 - 2 * 24 + 0.5),
  );
  if (scale == 1) {
    final board = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(board.position.maxScrollExtent, 0, reason: 'scrolls at 1x');
  }
  expect(find.byType(CartelCompacto), findsOneWidget);
}

void main() {
  setUpAll(loadBundledFonts);
  tearDown(() => AppPasscode.clock = DateTime.now);

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Text at ${scale}x: the lock keypad fits', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_lock(), scale));
      await _type(tester, '12');
      expect(find.text('¿Olvidaste el código?'), findsOneWidget);
      _fits(tester, scale, 'BLOQUEADA');
    });

    testWidgets('Text at ${scale}x: a wrong code and the wait fit', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final now = DateTime(2026, 10, 29, 12);
      AppPasscode.clock = () => now;
      PasscodeFeedback answer = const PasscodeError('Código incorrecto');
      await tester.pumpWidget(
        _app(_lock(onSubmit: (_) async => answer), scale),
      );

      await _type(tester, '1234');
      expect(find.text('Código incorrecto'), findsOneWidget);
      _fits(tester, scale, 'BLOQUEADA');

      await tester.pump(const Duration(seconds: 1));
      answer = PasscodeWait(now.add(AppPasscode.wait));
      await _type(tester, '1234');
      expect(
        find.text('Demasiados intentos. Probá de nuevo en 30 s'),
        findsOneWidget,
      );
      _fits(tester, scale, 'BLOQUEADA');
    });

    testWidgets('Text at ${scale}x: a new code, both steps, under the step '
        'dots', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(_newCode(), scale));
      expect(find.text('Ahora no'), findsOneWidget);
      _fits(tester, scale, 'TU CÓDIGO');

      await _type(tester, '1234');
      expect(find.text('Volver'), findsOneWidget);
      _fits(tester, scale, 'REPETILO');

      await _type(tester, '4321');
      expect(
        find.text('No coinciden. Elegí el código de nuevo.'),
        findsOneWidget,
      );
      _fits(tester, scale, 'TU CÓDIGO');
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('a 320 × 568 phone at ${scale}x: the keypad shrinks to the '
        'board, its keys stay over the touch size', (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_lock(), scale));

      final keypad = tester.getRect(find.byType(LedKeypad));
      expect(keypad.left, greaterThanOrEqualTo(24 - 0.5));
      expect(keypad.right, lessThanOrEqualTo(320 - 24 + 0.5));
      for (final label in ['1', '3', '0']) {
        final key = tester.getRect(find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first);
        expect(key.width, greaterThanOrEqualTo(TimbreSpace.touch),
            reason: label);
        expect(key.height, greaterThanOrEqualTo(TimbreSpace.touch),
            reason: label);
      }
      // The right column takes its digits
      await _type(tester, '3');
      expect(find.bySemanticsLabel('1 de 4 cifras'), findsOneWidget);
    });
  }

  testWidgets('a small system font: the sign keeps its 30 px', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(_app(_lock(), 0.85));
    expect(tester.getRect(find.text('BLOQUEADA')).height, closeTo(30, 0.01));
  });
}
