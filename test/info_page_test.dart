// Info: the lock card (the app's code, changing it, the quick unlock) in
// each state, its pages of the code with their snack bars and «¿Olvidaste
// el código?», and the data sources.
//
// Runs Info as the home of a MaterialApp with a real AppLock above the
// Navigator (as in main.dart), a fake system prompt (DeviceAuth) and Hive in
// a temp directory. The code's hash is worked out in one round (the real
// one runs in an isolate, which does not finish inside testWidgets). The
// lock writes its settings without awaiting the disk, so these tests can
// run in any order.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/app_lock.dart';
import 'package:stm_app/ui/code_pages.dart';
import 'package:stm_app/ui/info_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

import 'support/layout.dart';

const _codeRow = 'Código de acceso';
const _change = 'Cambiar código';
const _forgot = '¿Olvidaste el código?';
const _noScreenLockNote = 'Tu teléfono no tiene bloqueo de pantalla, así que '
    'no puede confirmar que sos vos. Sin el código no se puede cambiar ni '
    'desactivar.';

void main() {
  late Directory hiveDir;
  late _FakeAuth auth;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_info_test');
    await CacheService.init(path: hiveDir.path);
    AppPasscode.derive =
        (code, salt, n) async => pbkdf2Sha256(utf8.encode(code), salt, 1);
  });

  setUp(() {
    // Not awaited: in memory at once (see the header)
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

  /// Info with no lock, [olderLock] (from before the app had a code), or
  /// [code] and, with it, the [quickUnlock]. The prompts it took to get
  /// there are forgotten.
  Future<AppLockState> pumpInfo(WidgetTester tester,
      {String? code, bool quickUnlock = false, bool olderLock = false}) async {
    usePhoneScreen(tester);
    if (olderLock) {
      unawaited(CacheService.set(CacheService.keyBiometricEnabled, true));
    }
    await tester.pumpWidget(MaterialApp(
      theme: buildTimbreTheme(),
      navigatorObservers: [AppLock.routeGuard],
      builder: (context, navigator) =>
          AppLock(deviceAuth: auth, child: navigator!),
      home: const InfoPage(),
    ));
    await tester.pump();
    final lock = tester.state<AppLockState>(find.byType(AppLock));
    if (code != null) await lock.setCode(code);
    if (quickUnlock) expect(await lock.setBiometric(true), isTrue);
    // The switches slide to their place
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    auth.reasons.clear();
    auth.biometricOnly.clear();
    return lock;
  }

  /// A push or a pop, and the snack bar coming in.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await settle(tester);
  }

  Finder switchOf(String title) => find.descendant(
      of: find.ancestor(
          of: find.text(title), matching: find.byType(MergeSemantics)),
      matching: find.byType(Switch));

  bool switchValue(WidgetTester tester, String title) =>
      tester.widget<Switch>(switchOf(title)).value;

  Future<void> toggle(WidgetTester tester, String title) async {
    await tester.ensureVisible(switchOf(title));
    await tester.tap(switchOf(title));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String code) async {
    for (final digit in code.split('')) {
      await tester.ensureVisible(find.text(digit));
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    // Past a wrong code's red dots
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('rows', () {
    testWidgets('without a lock: only «Código de acceso», off',
        (tester) async {
      auth.kind = BiometricKind.fingerprint;
      await pumpInfo(tester);
      expect(switchValue(tester, _codeRow), isFalse);
      expect(find.text('Protegé tus paradas y rutas guardadas'),
          findsOneWidget);
      expect(find.text(_change), findsNothing);
      expect(find.text('Desbloquear con huella'), findsNothing);
      // One phrase for screen readers
      expect(
          find.bySemanticsLabel(
              RegExp('Código de acceso.*Protegé tus paradas', dotAll: true)),
          findsOneWidget);
    });

    testWidgets('with a code: on, «Cambiar código», the quick unlock',
        (tester) async {
      auth.kind = BiometricKind.fingerprint;
      await pumpInfo(tester, code: '1234');
      expect(switchValue(tester, _codeRow), isTrue);
      expect(find.text('La app lo pide al abrirse'), findsOneWidget);
      expect(find.text(_change), findsOneWidget);
      // Asked when Info opened: the lock had no code to ask it for
      expect(find.text('Desbloquear con huella'), findsOneWidget);
      expect(find.text('El código queda de respaldo'), findsOneWidget);
      expect(switchValue(tester, 'Desbloquear con huella'), isFalse);
    });

    testWidgets('with a code and nothing enrolled: no quick unlock row',
        (tester) async {
      await pumpInfo(tester, code: '1234');
      expect(find.text(_change), findsOneWidget);
      expect(find.textContaining('Desbloquear con'), findsNothing);
    });

    testWidgets('with a code and Face ID on', (tester) async {
      auth.kind = BiometricKind.faceId;
      await pumpInfo(tester, code: '1234', quickUnlock: true);
      expect(switchValue(tester, 'Desbloquear con Face ID'), isTrue);
    });

    testWidgets('the older lock: on, nothing else', (tester) async {
      auth.kind = BiometricKind.fingerprint;
      final lock = await pumpInfo(tester, olderLock: true);
      expect(lock.enabled, isTrue);
      expect(switchValue(tester, _codeRow), isTrue);
      expect(find.text('La app lo pide al abrirse'), findsOneWidget);
      expect(find.text(_change), findsNothing);
      expect(find.textContaining('Desbloquear con'), findsNothing);
    });
  });

  group('the code', () {
    testWidgets('on: «CÓDIGO NUEVO» twice, «Código activado»',
        (tester) async {
      final lock = await pumpInfo(tester);
      await toggle(tester, _codeRow);
      expect(find.text('CÓDIGO'), findsOneWidget); // the page title
      expect(find.text('CÓDIGO NUEVO'), findsOneWidget);
      expect(find.text('Elegí 4 cifras para abrir la app.'), findsOneWidget);
      await type(tester, '1470');
      expect(find.text('REPETILO'), findsOneWidget);
      await type(tester, '1470');
      await settle(tester);

      expect(find.byType(NewCodePage), findsNothing);
      expect(find.text('Código activado'), findsOneWidget);
      expect(lock.hasCode, isTrue);
      // It locks on the next trip to the background, not now
      expect(lock.locked, isFalse);
      expect(switchValue(tester, _codeRow), isTrue);
      expect(find.text(_change), findsOneWidget);
      expect(await AppPasscode.check('1470'), CodeCheck.ok);
    });

    testWidgets('Back from «CÓDIGO NUEVO» leaves it off', (tester) async {
      final lock = await pumpInfo(tester);
      await toggle(tester, _codeRow);
      await type(tester, '12');
      await tester.pageBack();
      await settle(tester);
      expect(lock.enabled, isFalse);
      expect(switchValue(tester, _codeRow), isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('«Cambiar código»: the code in use, then a new one',
        (tester) async {
      final lock = await pumpInfo(tester, code: '1234');
      await tapText(tester, _change);
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      expect(find.bySemanticsLabel('Tu código'), findsOneWidget);
      expect(find.text('Ingresá tu código actual.'), findsOneWidget);
      await type(tester, '9999');
      expect(find.text('Código incorrecto'), findsOneWidget);
      await type(tester, '1234');
      await settle(tester);

      expect(find.text('CÓDIGO NUEVO'), findsOneWidget);
      await type(tester, '5678');
      await type(tester, '5678');
      await settle(tester);
      expect(find.byType(CodeCheckPage), findsNothing);
      expect(find.text('Código cambiado'), findsOneWidget);
      expect(lock.hasCode, isTrue);
      expect(await AppPasscode.check('1234'), CodeCheck.wrong);
      expect(await AppPasscode.check('5678'), CodeCheck.ok);
    });

    testWidgets('off: the code in use turns every lock off', (tester) async {
      auth.kind = BiometricKind.fingerprint;
      final lock = await pumpInfo(tester, code: '1234', quickUnlock: true);
      await toggle(tester, _codeRow);
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      await type(tester, '1234');
      await settle(tester);

      expect(find.byType(CodeCheckPage), findsNothing);
      expect(find.text('Bloqueo desactivado'), findsOneWidget);
      expect(lock.enabled, isFalse);
      expect(lock.biometric, isFalse);
      expect(AppPasscode.isSet, isFalse);
      expect(CacheService.get<bool>(CacheService.keyLockBiometric), isNull);
      expect(switchValue(tester, _codeRow), isFalse);
      expect(find.text(_change), findsNothing);
      expect(find.textContaining('Desbloquear con'), findsNothing);
      expect(auth.reasons, isEmpty);
    });

    testWidgets('off with «¿Olvidaste el código?»: the phone\'s lock',
        (tester) async {
      final lock = await pumpInfo(tester, code: '1234');
      auth.answers.add(false); // cancelled first
      await toggle(tester, _codeRow);
      await tapText(tester, _forgot);
      expect(auth.reasons,
          ['Usá el bloqueo de tu teléfono para desactivar el código']);
      expect(auth.biometricOnly, [false]);
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      expect(lock.hasCode, isTrue);

      await tapText(tester, _forgot);
      await settle(tester);
      expect(find.byType(CodeCheckPage), findsNothing);
      expect(find.text('Bloqueo desactivado'), findsOneWidget);
      expect(lock.enabled, isFalse);
    });

    testWidgets('«Cambiar código» with «¿Olvidaste el código?»',
        (tester) async {
      await pumpInfo(tester, code: '1234');
      await tapText(tester, _change);
      await tapText(tester, _forgot);
      expect(auth.reasons,
          ['Usá el bloqueo de tu teléfono para cambiar el código']);
      expect(find.text('CÓDIGO NUEVO'), findsOneWidget);
      await type(tester, '2468');
      await type(tester, '2468');
      await settle(tester);
      expect(find.text('Código cambiado'), findsOneWidget);
      expect(await AppPasscode.check('2468'), CodeCheck.ok);
    });

    testWidgets('a phone without a screen lock cannot stand in for the code',
        (tester) async {
      final lock = await pumpInfo(tester, code: '1234');
      auth.available = false;
      await tapText(tester, _change);
      await tapText(tester, _forgot);
      expect(auth.reasons, isEmpty);
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      expect(find.text(_noScreenLockNote), findsOneWidget);
      expect(
          tester
              .widgetList<Semantics>(find.ancestor(
                  of: find.text(_noScreenLockNote),
                  matching: find.byType(Semantics)))
              .any((s) => s.properties.liveRegion ?? false),
          isTrue,
          reason: 'a live region');
      expect(lock.hasCode, isTrue);
    });

    testWidgets('the older lock goes off at once', (tester) async {
      final lock = await pumpInfo(tester, olderLock: true);
      await toggle(tester, _codeRow);
      expect(find.byType(CodeCheckPage), findsNothing);
      expect(find.text('Bloqueo desactivado'), findsOneWidget);
      expect(lock.enabled, isFalse);
      expect(CacheService.get<bool>(CacheService.keyBiometricEnabled), isNull);
      expect(switchValue(tester, _codeRow), isFalse);
      expect(auth.reasons, isEmpty);
    });
  });

  group('the quick unlock', () {
    const row = 'Desbloquear con huella';

    testWidgets('on after the prompt, off without one', (tester) async {
      auth.kind = BiometricKind.fingerprint;
      final lock = await pumpInfo(tester, code: '1234');
      await toggle(tester, row);
      expect(auth.reasons, ['Confirmá para abrir Timbre MVD con tu huella']);
      expect(auth.biometricOnly, [true]);
      expect(find.text('Desbloqueo con huella activado'), findsOneWidget);
      expect(lock.biometric, isTrue);
      expect(switchValue(tester, row), isTrue);

      await toggle(tester, row);
      expect(auth.reasons, hasLength(1));
      expect(find.text('Desbloqueo con huella desactivado'), findsOneWidget);
      expect(lock.biometric, isFalse);
      expect(switchValue(tester, row), isFalse);
    });

    testWidgets('a cancelled prompt leaves it off, without a word',
        (tester) async {
      auth.kind = BiometricKind.fingerprint;
      auth.answers.add(false);
      final lock = await pumpInfo(tester, code: '1234');
      await toggle(tester, row);
      expect(auth.reasons, hasLength(1));
      expect(lock.biometric, isFalse);
      expect(switchValue(tester, row), isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('removed from the phone meanwhile: the row goes, with a word',
        (tester) async {
      auth.kind = BiometricKind.fingerprint;
      final lock = await pumpInfo(tester, code: '1234');
      auth.kind = null;
      await toggle(tester, row);
      expect(auth.reasons, isEmpty);
      expect(
          find.text('Tu teléfono no tiene una huella ni un rostro '
              'configurados.'),
          findsOneWidget);
      expect(find.text(row), findsNothing);
      expect(lock.biometric, isFalse);
    });
  });

  group('data sources', () {
    const map = 'Mapa: © colaboradores de OpenStreetMap, con licencia ODbL. '
        'Viene dentro de la app.';
    // Comfort data and a server in between exist only in proxy builds
    const comfort = 'Aire acondicionado y cero emisiones: API de transporte '
        'público de Montevideo.';
    const server = 'Las consultas pasan por el servidor del proyecto, que no '
        'guarda datos personales.';

    testWidgets('shows data source attribution', (tester) async {
      await pumpInfo(tester);
      expect(find.text('FUENTE DE DATOS'), findsOneWidget);
      expect(find.textContaining('Intendencia de Montevideo'), findsWidgets);
      // Covers every IM service the native screens read
      expect(find.textContaining('novedades del transporte'), findsOneWidget);
      expect(find.textContaining('estado del GPS'), findsOneWidget);
      expect(find.textContaining('posición de los ómnibus'), findsOneWidget);
      // The Mapa's basemap (ODbL), with or without the proxy
      expect(find.text(map), findsOneWidget);
    });

    testWidgets('with the proxy: comfort source and the server',
        (tester) async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      addTearDown(() => MvdApiService.proxyUrl = '');
      await pumpInfo(tester);
      expect(find.text(comfort), findsOneWidget);
      expect(find.text(server), findsOneWidget);
    });

    testWidgets('without the proxy: neither', (tester) async {
      MvdApiService.proxyUrl = '';
      await pumpInfo(tester);
      expect(find.text('FUENTE DE DATOS'), findsOneWidget);
      expect(find.text(comfort), findsNothing);
      expect(find.text(server), findsNothing);
      expect(find.text(map), findsOneWidget);
    });
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
