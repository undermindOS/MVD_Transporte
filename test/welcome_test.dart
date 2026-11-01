// The welcome of the first launch: its four steps on the LED board, the
// app's code and the quick unlock chosen there, Back, the privacy policy,
// a welcome started over with a code, and the app itself (HomePage) not
// built until «Empezar», which the welcome shows only once.
//
// Runs the real app with a fake system prompt (DeviceAuth) and Hive in a
// temp directory. The code's hash is worked out in one round (the real one
// runs in an isolate, which does not finish inside testWidgets). The lock
// and the welcome write their settings without awaiting the disk, so these
// tests can run in any order (see test/app_lock_test.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/main.dart';
import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/app_lock.dart';
import 'package:stm_app/ui/home_page.dart';
import 'package:stm_app/ui/lock_screen.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';

import 'support/layout.dart';

const _sinCuentas = 'SIN CUENTAS\nNI REGISTROS';

void main() {
  late Directory hiveDir;
  late _FakeAuth auth;
  late DateTime now;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_welcome_test');
    await CacheService.init(path: hiveDir.path);
    AppPasscode.derive =
        (code, salt, n) async => pbkdf2Sha256(utf8.encode(code), salt, 1);
  });

  setUp(() {
    // A first launch. Not awaited: in memory at once (see the header)
    for (final key in [
      CacheService.keyWelcomeDone,
      CacheService.keyLockCode,
      CacheService.keyLockFailures,
      CacheService.keyLockWaitFrom,
      CacheService.keyLockBiometric,
      CacheService.keyBiometricEnabled,
    ]) {
      unawaited(CacheService.remove(key));
    }
    auth = _FakeAuth();
    now = DateTime(2026, 10, 29, 9);
    AppLock.clock = () => now;
  });

  tearDown(() => AppLock.clock = DateTime.now);

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(MiTransporteMVDApp(deviceAuth: auth));
    await tester.pump();
  }

  /// The cross-fade to the next step, a page pushed or popped.
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
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  AppLockState lockOf(WidgetTester tester) =>
      tester.state<AppLockState>(find.byType(AppLock));

  final home = find.byType(HomePage, skipOffstage: false);

  testWidgets('a code and huella: four steps, then the app', (tester) async {
    auth.kind = BiometricKind.fingerprint;
    await pumpApp(tester);

    expect(find.text('HOLA'), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 1 de 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Hola'), findsOneWidget);
    expect(
        find.text('Timbre MVD te muestra los ómnibus de Montevideo como el '
            'cartel de la parada.'),
        findsOneWidget);
    for (final row in ['Mis paradas', 'Mapa', 'Estoy esperando']) {
      expect(find.text(row), findsOneWidget);
    }
    expect(find.textContaining('App no oficial'), findsOneWidget);
    // Nothing of the app: no tabs, no polling
    expect(home, findsNothing);
    expect(find.byType(NavigationBar, skipOffstage: false), findsNothing);
    await tapText(tester, 'Continuar');

    expect(find.text(_sinCuentas), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 2 de 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Sin cuentas ni registros'), findsOneWidget);
    expect(find.textContaining('No tenés que crear una cuenta'),
        findsOneWidget);
    expect(home, findsNothing);
    await tapText(tester, 'Continuar');

    expect(find.text('TU CÓDIGO'), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 3 de 4'), findsOneWidget);
    expect(find.text('Elegí 4 cifras para abrir la app.'), findsOneWidget);
    await type(tester, '2580');
    expect(find.text('REPETILO'), findsOneWidget);
    await type(tester, '2580');

    // Saved, and no lock until the next trip to the background
    final lock = lockOf(tester);
    expect(lock.hasCode, isTrue);
    expect(lock.locked, isFalse);
    expect(await AppPasscode.check('2580'), CodeCheck.ok);
    expect(find.text('HUELLA'), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 3 de 4'), findsOneWidget);
    expect(
        find.text(
            'Abrí Timbre MVD con tu huella. Si no funciona, usás el código.'),
        findsOneWidget);
    expect(home, findsNothing);
    await tapText(tester, 'Usar huella');
    expect(auth.reasons, ['Confirmá para abrir Timbre MVD con tu huella']);
    expect(auth.biometricOnly, [true]);

    expect(find.text('LISTO'), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 4 de 4'), findsOneWidget);
    expect(find.byType(LedLock), findsOneWidget);
    expect(find.text('La app pide tu código al abrirse.'), findsOneWidget);
    expect(find.text('También se abre con tu huella.'), findsOneWidget);
    expect(find.text('Podés cambiarlo cuando quieras en Ajustes.'),
        findsOneWidget);
    expect(home, findsNothing);
    await tapText(tester, 'Empezar');

    expect(home, findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('LISTO'), findsNothing);
    expect(CacheService.get<bool>(CacheService.keyWelcomeDone), isTrue);
    expect(lock.biometric, isTrue);
  });

  testWidgets('«Ahora no» on the code: no lock, the older one neither',
      (tester) async {
    // The older lock opens first; the welcome turns it off
    unawaited(CacheService.set(CacheService.keyBiometricEnabled, true));
    await pumpApp(tester);
    expect(auth.reasons, ['Autenticate para acceder a Timbre MVD']);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Ahora no');

    expect(find.text('LISTO'), findsOneWidget);
    expect(find.byType(LedLock), findsNothing);
    expect(find.text('La app se abre sin código.'), findsOneWidget);
    expect(find.text('Podés cambiarlo cuando quieras en Ajustes.'),
        findsOneWidget);
    expect(find.text('La app pide tu código al abrirse.'), findsNothing);
    final lock = lockOf(tester);
    expect(lock.enabled, isFalse);
    expect(CacheService.get<bool>(CacheService.keyBiometricEnabled), isNull);
    await tapText(tester, 'Empezar');
    expect(home, findsOneWidget);

    // A trip to the background opens straight into the app
    now = now.add(const Duration(minutes: 1));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(lock.locked, isFalse);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(CodeLockScreen), findsNothing);
    expect(auth.reasons, hasLength(1));
  });

  testWidgets('two different codes: «No coinciden», then the code again',
      (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await type(tester, '1234');
    await type(tester, '4321');

    expect(find.text('TU CÓDIGO'), findsOneWidget);
    expect(find.text('No coinciden. Elegí el código de nuevo.'),
        findsOneWidget);
    expect(AppPasscode.isSet, isFalse);

    await type(tester, '4321');
    await type(tester, '4321');
    expect(AppPasscode.isSet, isTrue);
  });

  testWidgets('no fingerprint or face on the phone: no «Huella»',
      (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await type(tester, '9876');
    await type(tester, '9876');

    expect(find.text('HUELLA'), findsNothing);
    expect(find.text('LISTO'), findsOneWidget);
    expect(find.byType(LedLock), findsOneWidget);
    expect(find.text('La app pide tu código al abrirse.'), findsOneWidget);
    expect(find.textContaining('También se abre'), findsNothing);
    expect(auth.reasons, isEmpty);
  });

  testWidgets('a cancelled prompt stays on «Huella», without an error',
      (tester) async {
    auth.kind = BiometricKind.touchId;
    auth.answers.add(false);
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await type(tester, '1111');
    await type(tester, '1111');

    expect(find.text('TOUCH ID'), findsOneWidget);
    expect(find.bySemanticsLabel('Touch ID'), findsOneWidget);
    await tapText(tester, 'Usar Touch ID');
    expect(auth.reasons, ['Confirmá para abrir Timbre MVD con Touch ID']);
    expect(find.text('TOUCH ID'), findsOneWidget);
    expect(lockOf(tester).biometric, isFalse);

    await tapText(tester, 'Ahora no');
    expect(find.text('LISTO'), findsOneWidget);
    expect(find.textContaining('También se abre'), findsNothing);
  });

  testWidgets('«Leer la política de privacidad» opens Privacidad',
      (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Leer la política de privacidad');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('PRIVACIDAD'), findsOneWidget); // the page title

    await back(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('PRIVACIDAD'), findsNothing);
    expect(find.text(_sinCuentas), findsOneWidget);
  });

  testWidgets('Back: a step back until the code is saved, then nothing',
      (tester) async {
    auth.kind = BiometricKind.faceId;
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await back(tester);
    expect(find.text('HOLA'), findsOneWidget);

    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    expect(find.text('TU CÓDIGO'), findsOneWidget);
    await back(tester);
    expect(find.text(_sinCuentas), findsOneWidget);

    await tapText(tester, 'Continuar');
    await type(tester, '1357');
    await back(tester); // also on «REPETILO»
    expect(find.text(_sinCuentas), findsOneWidget);
    expect(AppPasscode.isSet, isFalse);

    await tapText(tester, 'Continuar');
    await type(tester, '1357');
    await type(tester, '1357');
    expect(find.text('FACE ID'), findsOneWidget);
    expect(find.text('Abrí Timbre MVD con Face ID. Si no funciona, usás el '
        'código.'), findsOneWidget);
    await back(tester);
    expect(find.text('FACE ID'), findsOneWidget);

    await tapText(tester, 'Ahora no');
    expect(find.text('LISTO'), findsOneWidget);
    await back(tester);
    expect(find.text('LISTO'), findsOneWidget);
    expect(home, findsNothing);
    expect(auth.reasons, isEmpty);
  });

  testWidgets('a welcome started over with a code skips «Tu código»',
      (tester) async {
    // The app was closed on «Listo»: the code and the quick unlock are on
    await AppPasscode.set('2468');
    unawaited(CacheService.set(CacheService.keyLockBiometric, true));
    auth.kind = BiometricKind.fingerprint;
    await pumpApp(tester);
    // The quick unlock opened the app, then the welcome
    expect(auth.reasons, ['Desbloqueá Timbre MVD']);
    expect(find.text('HOLA'), findsOneWidget);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');

    expect(find.text('TU CÓDIGO'), findsNothing);
    expect(find.text('HUELLA'), findsNothing); // on already
    expect(find.text('LISTO'), findsOneWidget);
    expect(find.text('También se abre con tu huella.'), findsOneWidget);
    await back(tester);
    expect(find.text('LISTO'), findsOneWidget);
    expect(await AppPasscode.check('2468'), CodeCheck.ok);
  });

  testWidgets('started over with a code but no quick unlock: «Huella»',
      (tester) async {
    auth.kind = BiometricKind.fingerprint;
    await pumpApp(tester);
    // A code saved before the app was closed
    await lockOf(tester).setCode('8642');
    await tester.pump();
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');

    expect(find.text('TU CÓDIGO'), findsNothing);
    expect(find.text('HUELLA'), findsOneWidget);
    await back(tester);
    expect(find.text('HUELLA'), findsOneWidget);
  });

  testWidgets('the welcome is shown once', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Ahora no');
    await tapText(tester, 'Empezar');
    expect(CacheService.get<bool>(CacheService.keyWelcomeDone), isTrue);

    // The next launch
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    expect(find.text('HOLA'), findsNothing);
    expect(home, findsOneWidget);
  });

  testWidgets('steps cross-fade in 200 ms', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The new step half in, over the old one
    final fade = tester.widget<Opacity>(find
        .ancestor(of: find.text(_sinCuentas), matching: find.byType(Opacity))
        .first);
    expect(fade.opacity, closeTo(0.5, 0.05));
    expect(find.text('HOLA'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('HOLA'), findsNothing);
  });

  testWidgets('steps change at once with reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump();
    // No old step fading out under the new one
    expect(find.text('HOLA'), findsNothing);
    expect(find.text(_sinCuentas), findsOneWidget);
  });

  // Last: it takes over the platform channel
  testWidgets('Back on «Hola» leaves the app', (tester) async {
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls, contains('SystemNavigator.pop'));
  });
}

/// The system prompt. [answers] are the next prompts' answers in order (a
/// bool, or an error to throw); then every prompt says yes.
class _FakeAuth implements DeviceAuth {
  final reasons = <String>[];
  final biometricOnly = <bool>[];
  final answers = <Object>[];

  /// What the phone has enrolled for the quick unlock.
  BiometricKind? kind;

  /// The phone has a screen lock.
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind?> biometrics() async => kind;

  @override
  Future<bool> authenticate(String reason,
      {bool biometricOnly = false, bool sticky = true}) async {
    reasons.add(reason);
    this.biometricOnly.add(biometricOnly);
    final answer = answers.isEmpty ? true : answers.removeAt(0);
    if (answer is bool) return answer;
    throw answer;
  }
}
