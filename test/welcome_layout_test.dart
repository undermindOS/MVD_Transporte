// The welcome's steps on the LED board, with real fonts on a phone screen:
// at 1×, 1.3× and 2× every word stays whole (no line cut short, nothing
// ending in «…», nothing past the screen's edges), the signs never drop
// below 19 px nor run past the board, the buttons keep their size, and at
// 1× each step fits without scrolling. «Listo» in its three states: with a
// code and the quick unlock, with a code, without one. Any overflow fails
// the test.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/app_lock.dart';
import 'package:stm_app/ui/theme/timbre_text.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/welcome/welcome_page.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/led_board.dart';

import 'support/layout.dart';

Widget _app(DeviceAuth auth, double scale) => MaterialApp(
      theme: buildTimbreTheme(),
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AppLock(deviceAuth: auth, child: navigator!),
      ),
      home: WelcomePage(onDone: () {}),
    );

/// Every word on the step whole and on the screen, the sign at 19 px or
/// more and inside the board, the buttons at their size; at 1× the board
/// does not scroll.
void _fits(WidgetTester tester, double scale, String sign) {
  final board = find.byType(LedBoard);
  expect(board, findsOneWidget, reason: 'one step on screen');
  for (final text in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: board, matching: find.byType(RichText)))) {
    final plain = text.text.toPlainText();
    expect(text.didExceedMaxLines, isFalse, reason: plain);
    final rect = MatrixUtils.transformRect(
        text.getTransformTo(null), Offset.zero & text.size);
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: plain);
    expect(rect.right, lessThanOrEqualTo(390.5), reason: plain);
  }

  final signRect = tester.getRect(find.text(sign));
  final lines = '\n'.allMatches(sign).length + 1;
  expect(signRect.height / lines,
      greaterThanOrEqualTo(TimbreFonts.dotoMinSize - 0.01),
      reason: sign);
  expect(signRect.width, lessThanOrEqualTo(390 - 2 * 24 + 0.5), reason: sign);

  for (final button in tester.widgetList<FilledButton>(
      find.descendant(of: board, matching: find.byType(FilledButton)))) {
    final size = tester.getSize(find.byWidget(button));
    expect(size.width, greaterThanOrEqualTo(220));
    expect(size.height, greaterThanOrEqualTo(56));
  }
  for (final button in tester.widgetList<TextButton>(
      find.descendant(of: board, matching: find.byType(TextButton)))) {
    expect(tester.getSize(find.byWidget(button)).height,
        greaterThanOrEqualTo(TimbreSpace.touch));
  }
  expect(find.byType(CartelCompacto), findsOneWidget);

  if (scale == 1) {
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: board, matching: find.byType(Scrollable)).first);
    expect(scroll.position.maxScrollExtent, 0, reason: '$sign scrolls at 1x');
  }
}

void main() {
  late Directory hiveDir;
  late _FakeAuth auth;

  setUpAll(() async {
    await loadBundledFonts();
    hiveDir = await Directory.systemTemp.createTemp('mvd_welcome_layout');
    await CacheService.init(path: hiveDir.path);
    AppPasscode.derive =
        (code, salt, n) async => pbkdf2Sha256(utf8.encode(code), salt, 1);
  });

  setUp(() {
    // Not awaited: in memory at once (see test/welcome_test.dart)
    for (final key in [
      CacheService.keyLockCode,
      CacheService.keyLockFailures,
      CacheService.keyLockWaitFrom,
      CacheService.keyLockBiometric,
      CacheService.keyBiometricEnabled,
    ]) {
      unawaited(CacheService.remove(key));
    }
    auth = _FakeAuth();
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, double scale) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(_app(auth, scale));
    await tester.pump();
  }

  /// Past the cross-fade.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String code) async {
    for (final digit in code.split('')) {
      await tester.ensureVisible(find.text(digit));
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await settle(tester);
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Text at ${scale}x: every step, «Listo» with code and huella',
        (tester) async {
      auth.kind = BiometricKind.fingerprint;
      await pump(tester, scale);
      _fits(tester, scale, 'HOLA');
      await tapText(tester, 'Continuar');
      _fits(tester, scale, 'SIN CUENTAS\nNI REGISTROS');
      await tapText(tester, 'Continuar');
      _fits(tester, scale, 'TU CÓDIGO');
      await type(tester, '1234');
      _fits(tester, scale, 'REPETILO');
      // Two different codes: the first step again, with the error
      await type(tester, '4321');
      expect(find.text('No coinciden. Elegí el código de nuevo.'),
          findsOneWidget);
      _fits(tester, scale, 'TU CÓDIGO');
      await type(tester, '1234');
      await type(tester, '1234');
      _fits(tester, scale, 'HUELLA');
      await tapText(tester, 'Usar huella');
      expect(find.text('También se abre con tu huella.'), findsOneWidget);
      // The lock's boot is over: as it stays
      await tester.pump(const Duration(seconds: 2));
      _fits(tester, scale, 'LISTO');
    });

    testWidgets('Text at ${scale}x: «TOUCH ID», «Listo» with a code',
        (tester) async {
      auth.kind = BiometricKind.touchId;
      await pump(tester, scale);
      await tapText(tester, 'Continuar');
      await tapText(tester, 'Continuar');
      await type(tester, '5555');
      await type(tester, '5555');
      expect(find.text('Usar Touch ID'), findsOneWidget);
      _fits(tester, scale, 'TOUCH ID');
      await tapText(tester, 'Ahora no');
      expect(find.text('La app pide tu código al abrirse.'), findsOneWidget);
      expect(find.textContaining('También se abre'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      _fits(tester, scale, 'LISTO');
    });

    testWidgets('Text at ${scale}x: «Listo» without a code', (tester) async {
      await pump(tester, scale);
      await tapText(tester, 'Continuar');
      await tapText(tester, 'Continuar');
      await tapText(tester, 'Ahora no');
      expect(find.text('La app se abre sin código.'), findsOneWidget);
      _fits(tester, scale, 'LISTO');
    });
  }
}

class _FakeAuth implements DeviceAuth {
  BiometricKind? kind;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricKind?> biometrics() async => kind;

  @override
  Future<bool> authenticate(String reason,
          {bool biometricOnly = false, bool sticky = true}) async =>
      true;
}
