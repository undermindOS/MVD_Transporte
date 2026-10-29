// The lock covers the whole app: pages, sheets, dialogs and snackbars
// pushed over the home page, not only the home page. With the app's code
// it opens with the code typed on the keypad (a wait after too many wrong
// codes), or first with the quick unlock: only a yes from the fingerprint
// or face prompt opens. A forgotten code: the phone's own lock, then a new
// code or «Ahora no»; a phone without a screen lock gets a note and stays
// locked. The older lock (the phone's prompt only) stays as it was, failing
// closed. setCode, checkCode, setBiometric, confirmWithPhoneLock and
// removeLock are what the welcome and Info call.
//
// Runs the real app with a fake system prompt (DeviceAuth), a fake browser
// launcher and Hive in a temp directory, the welcome already done. The
// lock's clocks are moved by hand and the code's hash takes one round.
//
// Nothing here awaits a settings write: only the first test of a file can
// (see test/stop_search_test.dart). Hive has a write in memory at once, and
// the lock's own writes are not awaited either.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:stm_app/main.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/app_lock.dart';
import 'package:stm_app/ui/home_page.dart';
import 'package:stm_app/ui/info_page.dart';
import 'package:stm_app/ui/lock_screen.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/news_list.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/widgets/led_keypad.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';

import 'support/layout.dart';

const _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];
const _backFromBackground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

const _quickUnlock = (reason: 'Desbloqueá Timbre MVD', biometricOnly: true);
const _phoneLock = (
  reason: 'Usá el bloqueo de tu teléfono para entrar a Timbre MVD',
  biometricOnly: false,
);
const _olderLock = (
  reason: 'Autenticate para acceder a Timbre MVD',
  biometricOnly: false,
);
const _noScreenLockNote = 'Tu teléfono no tiene bloqueo de pantalla, así que '
    'no puede confirmar que sos vos. Para entrar sin el código, borrá los '
    'datos de Timbre MVD en los ajustes del teléfono: se borran tus paradas '
    'y rutas.';

void main() {
  late Directory hiveDir;
  late _FakeAuth auth;
  late _FakeBrowser browser;
  late DateTime now;
  final derive = AppPasscode.derive;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_lock_test');
    await CacheService.init(path: hiveDir.path);
    // Before any test: the welcome is done, the app opens on Mis paradas
    await CacheService.set(CacheService.keyWelcomeDone, true);
  });

  setUp(() {
    auth = _FakeAuth();
    browser = _FakeBrowser();
    UrlLauncherPlatform.instance = browser;
    now = DateTime(2026, 10, 27, 9);
    AppLock.clock = () => now;
    AppPasscode.clock = () => now;
    // The real one runs in an isolate, which never ends in a widget test
    AppPasscode.derive = (code, salt, iterations) async =>
        pbkdf2Sha256(utf8.encode(code), salt, 1);
    // No lock of the test before (in memory at once, see the header)
    AppPasscode.clear();
    unawaited(CacheService.remove(CacheService.keyLockBiometric));
    unawaited(CacheService.remove(CacheService.keyBiometricEnabled));
  });

  tearDown(() {
    AppLock.clock = DateTime.now;
    AppPasscode.clock = DateTime.now;
    AppPasscode.derive = derive;
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  /// The quick unlock, turned on earlier; [kind] is what the phone offers.
  void quickUnlockOn(BiometricKind? kind) {
    unawaited(CacheService.set(CacheService.keyLockBiometric, true));
    auth.kind = kind;
  }

  /// The older lock, turned on in Info before the app had a code.
  void olderLockOn() =>
      unawaited(CacheService.set(CacheService.keyBiometricEnabled, true));

  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(MiTransporteMVDApp(deviceAuth: auth));
    await tester.pump();
  }

  AppLockState lockOf(WidgetTester tester) =>
      tester.state<AppLockState>(find.byType(AppLock));

  /// Types [code] on the lock's keypad. A wrong code stays on the dots
  /// 650 ms: wait a second before the next one.
  Future<void> typeCode(WidgetTester tester, String code) async {
    for (final digit in code.split('')) {
      await tester.tap(find.descendant(
          of: find.byType(LedKeypad), matching: find.text(digit)));
      await tester.pump();
    }
    // The check, then the app or what was wrong
    await tester.pump();
    await tester.pump();
  }

  /// The digit keys take digits.
  bool keysOn(WidgetTester tester) {
    final keypad = tester.widget<LedKeypad>(find.byType(LedKeypad));
    return keypad.enabled && keypad.onDigit != null;
  }

  bool scanning(WidgetTester tester) =>
      tester.widget<LedLock>(find.byType(LedLock)).scanning;

  Future<void> forgotCode(WidgetTester tester) async {
    await tester.tap(find.text('¿Olvidaste el código?'));
    await tester.pump();
    await tester.pump();
  }

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  /// Out of the 2 s after the last prompt, then to the background and back.
  Future<void> tripToBackground(WidgetTester tester) async {
    now = now.add(const Duration(minutes: 1));
    lifecycle(tester, _toBackground);
    now = now.add(const Duration(minutes: 5));
    lifecycle(tester, _backFromBackground);
    await tester.pump();
    // The prompt, if one opens
    await tester.pump();
  }

  /// Push transition.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openInfo(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Info'));
    await settle(tester);
  }

  /// Scrolls Info down to a link row.
  Future<void> scrollInfoTo(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(find.text(title), 200,
        scrollable: find.descendant(
            of: find.byType(InfoPage), matching: find.byType(Scrollable)));
    // A 200 px step can stop with the row built but still under the screen
    await tester.ensureVisible(find.text(title));
    await tester.pump();
  }

  bool polling(WidgetTester tester) => tester
      .widget<StopsPage>(find.byType(StopsPage, skipOffstage: false))
      .active;

  group('the code', () {
    testWidgets('nothing of the app is built before the first unlock; a '
        'wrong code keeps the lock, the right one opens', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);

      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.text('Ingresá tu código'), findsOneWidget);
      // No quick unlock: no prompt
      expect(auth.prompts, isEmpty);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
      expect(find.byType(StopsPage, skipOffstage: false), findsNothing);

      await typeCode(tester, '4321');
      expect(find.text('Código incorrecto'), findsOneWidget);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);
      expect(auth.prompts, isEmpty);
    });

    testWidgets('five wrong codes in a row: a wait with the keys off, also '
        'after closing the app; then the code opens', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);

      for (var i = 1; i < AppPasscode.freeTries; i++) {
        await typeCode(tester, '0000');
        expect(find.text('Código incorrecto'), findsOneWidget, reason: '$i');
        await tester.pump(const Duration(seconds: 1));
        expect(keysOn(tester), isTrue, reason: '$i');
      }
      await typeCode(tester, '0000');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Demasiados intentos. Probá de nuevo en 30 s'),
          findsOneWidget);
      expect(keysOn(tester), isFalse);
      // Not even the right code gets through
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsOneWidget);

      // Closed and opened again 10 s later: the same wait goes on
      now = now.add(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester);
      expect(find.text('Demasiados intentos. Probá de nuevo en 20 s'),
          findsOneWidget);
      expect(keysOn(tester), isFalse);

      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ingresá tu código'), findsOneWidget);
      expect(keysOn(tester), isTrue);
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);
    });
  });

  group('the quick unlock', () {
    testWidgets('at start and after a trip: the prompt at once over the '
        'keypad; a yes opens', (tester) async {
      await AppPasscode.set('1234');
      quickUnlockOn(BiometricKind.fingerprint);
      auth.answers.add(null);
      await pumpApp(tester);
      await tester.pump();

      expect(auth.prompts, [_quickUnlock]);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
      // While it is open the lock scans and the keys wait
      expect(scanning(tester), isTrue);
      expect(keysOn(tester), isFalse);
      // The prompt pauses the app on its way (Android's PIN screen): no
      // second lock, no second prompt
      lifecycle(tester, _toBackground);
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(auth.prompts, [_quickUnlock]);

      auth.answer(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);

      // Back from the prompt within 2 s: still open
      lifecycle(tester, _toBackground);
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(auth.prompts, [_quickUnlock]);

      auth.answers.add(null);
      await tripToBackground(tester);
      expect(auth.prompts, [_quickUnlock, _quickUnlock]);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(scanning(tester), isTrue);
      auth.answer(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);
    });

    for (final (name, answer) in <(String, Object)>[
      ('a no («Usar código», cancel, back)', false),
      ('UserFallback', PlatformException(code: 'UserFallback')),
      ('LockedOut', PlatformException(code: auth_error.lockedOut)),
    ]) {
      testWidgets('$name leaves the keypad, at start and after a trip; its '
          'key asks again', (tester) async {
        await AppPasscode.set('1234');
        quickUnlockOn(BiometricKind.faceId);
        auth.answers.add(answer);
        await pumpApp(tester);
        await tester.pump();

        expect(auth.prompts, [_quickUnlock]);
        expect(find.byType(CodeLockScreen), findsOneWidget);
        expect(find.byType(HomePage, skipOffstage: false), findsNothing);
        expect(scanning(tester), isFalse);
        expect(keysOn(tester), isTrue);
        // Silently: the keypad as it was
        expect(find.text('Ingresá tu código'), findsOneWidget);
        await typeCode(tester, '1234');
        expect(find.byType(CodeLockScreen), findsNothing);

        auth.answers.add(answer);
        await tripToBackground(tester);
        expect(auth.prompts, [_quickUnlock, _quickUnlock]);
        expect(find.byType(CodeLockScreen), findsOneWidget);
        expect(keysOn(tester), isTrue);

        auth.answers.add(true);
        await tester.tap(find.bySemanticsLabel('Desbloquear con Face ID'));
        await tester.pump();
        await tester.pump();
        expect(auth.prompts, List.filled(3, _quickUnlock));
        expect(find.byType(CodeLockScreen), findsNothing);
      });
    }

    testWidgets('needs a fingerprint or a face on the phone: none, no prompt '
        'and no key; enrolled later, the next lock asks', (tester) async {
      await AppPasscode.set('1234');
      quickUnlockOn(null);
      await pumpApp(tester);
      await tester.pump();

      expect(auth.prompts, isEmpty);
      expect(find.bySemanticsLabel(RegExp('^Desbloquear con')), findsNothing);
      expect(keysOn(tester), isTrue);
      await typeCode(tester, '1234');

      auth.kind = BiometricKind.touchId;
      auth.answers.add(null);
      await tripToBackground(tester);
      expect(auth.prompts, [_quickUnlock]);
      expect(find.bySemanticsLabel('Desbloquear con Touch ID'), findsOneWidget);
      auth.answer(false);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(keysOn(tester), isTrue);
    });

    testWidgets('setBiometric: on once the prompt sees a fingerprint, off at '
        'once; cancelled or without one it stays off', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await typeCode(tester, '1234');
      final lock = lockOf(tester);

      // Nothing enrolled: no prompt
      expect(await lock.setBiometric(true), isFalse);
      expect(auth.prompts, isEmpty);

      // Cancelled, locked out
      auth.kind = BiometricKind.fingerprint;
      auth.answers.addAll([false, PlatformException(code: auth_error.lockedOut)]);
      expect(await lock.setBiometric(true), isFalse);
      expect(await lock.setBiometric(true), isFalse);
      expect(
          auth.prompts,
          List.filled(2, (
            reason: 'Confirmá para abrir Timbre MVD con tu huella',
            biometricOnly: true,
          )));
      expect(lock.biometric, isFalse);
      expect(CacheService.get<bool>(CacheService.keyLockBiometric), isNull);

      // Confirmed: on, and the lock does not close now
      expect(await lock.setBiometric(true), isTrue);
      expect(lock.biometric, isTrue);
      expect(lock.biometricKind, BiometricKind.fingerprint);
      expect(CacheService.get<bool>(CacheService.keyLockBiometric), isTrue);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);

      // The next trip asks the fingerprint first
      auth.answers.add(true);
      await tripToBackground(tester);
      expect(auth.prompts.last, _quickUnlock);
      expect(find.byType(CodeLockScreen), findsNothing);

      // Off: at once, no prompt; the next lock is the keypad alone
      final prompts = auth.prompts.length;
      expect(await lock.setBiometric(false), isFalse);
      expect(lock.biometric, isFalse);
      expect(CacheService.get<bool>(CacheService.keyLockBiometric), isNull);
      await tripToBackground(tester);
      expect(auth.prompts, hasLength(prompts));
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Desbloquear con')), findsNothing);
    });
  });

  group('«¿Olvidaste el código?»', () {
    testWidgets('the phone\'s lock, then «CÓDIGO NUEVO»; the next lock takes '
        'the new code', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);

      auth.answers.add(null);
      await forgotCode(tester);
      expect(auth.prompts, [_phoneLock]);
      expect(scanning(tester), isTrue);
      expect(keysOn(tester), isFalse);
      auth.answer(true);
      await tester.pump();
      await tester.pump();

      expect(find.byType(NewCodeScreen), findsOneWidget);
      expect(find.text('CÓDIGO NUEVO'), findsOneWidget);
      expect(find.text('Elegí 4 cifras nuevas para abrir la app.'),
          findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
      await typeCode(tester, '5678');
      expect(find.text('REPETILO'), findsOneWidget);
      await typeCode(tester, '5678');
      expect(find.byType(NewCodeScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);
      expect(AppPasscode.isSet, isTrue);

      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      await typeCode(tester, '1234');
      expect(find.text('Código incorrecto'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await typeCode(tester, '5678');
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(auth.prompts, [_phoneLock]);
    });

    testWidgets('«Ahora no» opens the app and keeps the old code',
        (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await forgotCode(tester);
      expect(find.byType(NewCodeScreen), findsOneWidget);

      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(NewCodeScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);

      await tripToBackground(tester);
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
    });

    testWidgets('the phone\'s lock ends a wait and forgets the wrong codes, '
        'also with «Ahora no»', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      for (var i = 0; i < AppPasscode.freeTries; i++) {
        await typeCode(tester, '0000');
        await tester.pump(const Duration(seconds: 1));
      }
      expect(keysOn(tester), isFalse);
      expect(AppPasscode.waitUntil, isNotNull);

      await forgotCode(tester);
      expect(find.byType(NewCodeScreen), findsOneWidget);
      expect(AppPasscode.waitUntil, isNull);
      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      await tester.pump();
      expect(find.text('MIS PARADAS'), findsOneWidget);

      // The next lock: no wait, and a wrong code is only wrong again
      await tripToBackground(tester);
      expect(keysOn(tester), isTrue);
      await typeCode(tester, '0000');
      expect(find.text('Código incorrecto'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
    });

    testWidgets('a trip to the background while choosing the new code '
        'locks again, to the keypad', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await forgotCode(tester);
      await typeCode(tester, '56');

      await tripToBackground(tester);
      expect(find.byType(NewCodeScreen), findsNothing);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
      await typeCode(tester, '1234');
      expect(find.text('MIS PARADAS'), findsOneWidget);
    });

    testWidgets('a phone without a screen lock: no prompt, the note, nothing '
        'opens', (tester) async {
      await AppPasscode.set('1234');
      auth.available = false;
      await pumpApp(tester);
      await forgotCode(tester);

      expect(auth.prompts, isEmpty);
      expect(find.text(_noScreenLockNote), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel(_noScreenLockNote)),
          isSemantics(isLiveRegion: true));
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);

      // The code still opens; the next lock starts without the note
      await typeCode(tester, '1234');
      expect(find.text('MIS PARADAS'), findsOneWidget);
      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.text(_noScreenLockNote), findsNothing);
    });

    testWidgets('a no, or an error while the phone has a screen lock, leaves '
        'the keypad; an error because it has none, the note', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);

      for (final answer in [
        false,
        // iOS, also after a failed try
        PlatformException(code: auth_error.notAvailable),
        PlatformException(code: auth_error.lockedOut),
      ]) {
        auth.answers.add(answer);
        await forgotCode(tester);
        expect(find.byType(CodeLockScreen), findsOneWidget, reason: '$answer');
        expect(find.byType(NewCodeScreen), findsNothing, reason: '$answer');
        expect(find.text(_noScreenLockNote), findsNothing, reason: '$answer');
        expect(keysOn(tester), isTrue, reason: '$answer');
      }

      // The screen lock gone while the prompt was open
      auth.answers.add(null);
      await forgotCode(tester);
      auth.available = false;
      auth.fail(PlatformException(code: auth_error.notAvailable));
      await tester.pump();
      await tester.pump();
      expect(find.text(_noScreenLockNote), findsOneWidget);
      expect(find.byType(NewCodeScreen), findsNothing);
      expect(auth.prompts, List.filled(4, _phoneLock));
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
    });
  });

  group('prompts opened from the open app', () {
    Future<void> openWithCode(WidgetTester tester) async {
      await AppPasscode.set('1234');
      auth.kind = BiometricKind.fingerprint;
      await pumpApp(tester);
      await typeCode(tester, '1234');
      expect(find.text('MIS PARADAS'), findsOneWidget);
    }

    testWidgets('turning the quick unlock on: not sticky, and a trip while '
        'its prompt is up locks once it closes without a yes',
        (tester) async {
      await openWithCode(tester);

      auth.answers.add(null);
      var turnedOn = lockOf(tester).setBiometric(true);
      await tester.pump();
      expect(auth.sticky.last, isFalse);
      // Gone for minutes with the prompt up: back, the prompt decides
      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsNothing);
      auth.answer(false);
      await tester.pump();
      await tester.pump();
      expect(await turnedOn, isFalse);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      // The app stays built under the lock
      expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);

      // A yes after the trip is the owner's: no lock
      await typeCode(tester, '1234');
      auth.answers.add(null);
      turnedOn = lockOf(tester).setBiometric(true);
      await tester.pump();
      await tripToBackground(tester);
      auth.answer(true);
      await tester.pump();
      await tester.pump();
      expect(await turnedOn, isTrue);
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(lockOf(tester).biometric, isTrue);
    });

    testWidgets('the phone\'s lock from Info: not sticky, and a trip while it '
        'is up locks once it closes without a yes', (tester) async {
      await openWithCode(tester);

      auth.answers.add(null);
      final confirmed = lockOf(tester).confirmWithPhoneLock('Info');
      await tester.pump();
      expect(auth.sticky.last, isFalse);
      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsNothing);
      auth.fail(PlatformException(code: 'UserCancelled'));
      await tester.pump();
      await tester.pump();
      expect(await confirmed, isFalse);
      expect(find.byType(CodeLockScreen), findsOneWidget);
    });

    testWidgets('a prompt with no trip closes as before: no lock',
        (tester) async {
      await openWithCode(tester);
      auth.answers.add(false);
      expect(await lockOf(tester).setBiometric(true), isFalse);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);
    });

    testWidgets('the lock screen\'s own prompts stay sticky', (tester) async {
      await AppPasscode.set('1234');
      quickUnlockOn(BiometricKind.fingerprint);
      auth.answers.addAll([false, false]);
      await pumpApp(tester);
      await tester.pump();
      await forgotCode(tester);
      expect(auth.biometricOnlyFlags, [true, false]);
      expect(auth.sticky, [true, true]);
    });
  });

  testWidgets('every lock starts with an empty keypad: digits typed before a '
      'trip do not stay', (tester) async {
    await AppPasscode.set('1234');
    await pumpApp(tester);
    for (final digit in ['1', '2']) {
      await tester.tap(find.descendant(
          of: find.byType(LedKeypad), matching: find.text(digit)));
      await tester.pump();
    }
    expect(find.bySemanticsLabel('2 de 4 cifras'), findsOneWidget);

    await tripToBackground(tester);
    expect(find.bySemanticsLabel('0 de 4 cifras'), findsOneWidget);
    // With «12» left over, this would be «1212»
    await typeCode(tester, '1234');
    expect(find.byType(CodeLockScreen), findsNothing);
  });

  group('the older lock', () {
    testWidgets('the system prompt as before; nothing built before the first '
        'unlock; a trip asks again', (tester) async {
      olderLockOn();
      auth.autoAnswer = null;
      await pumpApp(tester);

      expect(auth.prompts, [_olderLock]);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
      expect(find.byType(StopsPage, skipOffstage: false), findsNothing);

      // Cancelled: still nothing, «Desbloquear» tries again
      auth.answer(false);
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);

      auth.autoAnswer = true;
      await tester.tap(find.text('Desbloquear'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);

      auth.autoAnswer = null;
      await tripToBackground(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(auth.prompts, List.filled(3, _olderLock));
      auth.answer(true);
      await tester.pump();
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('a locked-out prompt keeps the lock (fail closed)',
        (tester) async {
      olderLockOn();
      auth.error = PlatformException(code: auth_error.lockedOut);
      await pumpApp(tester);
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
    });

    testWidgets('NotAvailable while the phone has a lock method keeps the '
        'lock (iOS says it after a failed try)', (tester) async {
      olderLockOn();
      auth.error = PlatformException(code: auth_error.notAvailable);
      await pumpApp(tester);
      await tester.pump();
      expect(auth.prompts, [_olderLock]);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(HomePage, skipOffstage: false), findsNothing);
    });

    testWidgets('a phone with no lock method opens the app, with no prompt',
        (tester) async {
      olderLockOn();
      auth.available = false;
      await pumpApp(tester);
      await tester.pump();
      expect(auth.prompts, isEmpty);
      expect(find.byType(LockScreen), findsNothing);
      expect(find.text('MIS PARADAS'), findsOneWidget);
    });

    testWidgets('setCode replaces it; checkCode and confirmWithPhoneLock '
        'answer Info; removeLock turns every lock off', (tester) async {
      olderLockOn();
      await pumpApp(tester);
      await tester.pump();
      expect(find.text('MIS PARADAS'), findsOneWidget);
      final lock = lockOf(tester);
      expect(lock.enabled, isTrue);
      expect(lock.hasCode, isFalse);

      // Saved, the older lock gone; it locks from the next trip on
      await lock.setCode('2468');
      await tester.pump();
      expect(lock.hasCode, isTrue);
      expect(lock.enabled, isTrue);
      expect(CacheService.get<bool>(CacheService.keyBiometricEnabled), isNull);
      expect(lock.locked, isFalse);
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(await lock.checkCode('1357'), CodeCheck.wrong);
      expect(await lock.checkCode('2468'), CodeCheck.ok);

      // Info's «¿Olvidaste el código?»
      const change = 'Usá el bloqueo de tu teléfono para cambiar el código';
      auth.answers.addAll([true, false]);
      expect(await lock.confirmWithPhoneLock(change), isTrue);
      expect(await lock.confirmWithPhoneLock(change), isFalse);
      expect(auth.prompts.last, (reason: change, biometricOnly: false));
      auth.available = false;
      expect(await lock.confirmWithPhoneLock(change), isNull);
      auth.available = true;

      final prompts = auth.prompts.length;
      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
      expect(auth.prompts, hasLength(prompts));
      await typeCode(tester, '2468');
      expect(find.byType(CodeLockScreen), findsNothing);

      lock.removeLock();
      await tester.pump();
      expect(lock.enabled, isFalse);
      expect(lock.hasCode, isFalse);
      expect(AppPasscode.isSet, isFalse);
      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.byType(LockScreen), findsNothing);
      expect(auth.prompts, hasLength(prompts));
    });
  });

  group('with a code, what the lock covers', () {
    testWidgets('locked, a page, a sheet, a dialog and a snackbar are out of '
        'sight and reach; unlocking brings them back', (tester) async {
      final semantics = tester.ensureSemantics();
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);

      // Info, a sheet over it, a dialog over the sheet, a snackbar
      await openInfo(tester);
      final info = tester.element(find.byType(InfoPage));
      unawaited(showModalBottomSheet<void>(
        context: info,
        builder: (_) =>
            const SizedBox(height: 200, child: Text('Hoja de prueba')),
      ));
      await settle(tester);
      unawaited(showDialog<void>(
        context: info,
        builder: (_) => const AlertDialog(title: Text('Diálogo de prueba')),
      ));
      await settle(tester);
      ScaffoldMessenger.of(info)
          .showSnackBar(const SnackBar(content: Text('Aviso de prueba')));
      await settle(tester);
      expect(find.text('NO OFICIAL'), findsOneWidget);
      expect(find.text('Aviso de prueba'), findsWidgets);
      expect(find.semantics.byLabel('Diálogo de prueba'), findsOneWidget);

      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      expect(find.semantics.byLabel('Aplicación bloqueada'), findsOneWidget);
      for (final text in [
        'NO OFICIAL',
        'Hoja de prueba',
        'Diálogo de prueba',
        'Aviso de prueba',
      ]) {
        expect(find.text(text), findsNothing, reason: text);
        expect(find.semantics.byLabel(RegExp(text)), findsNothing,
            reason: text);
      }
      // Kept as they were
      expect(
          find.text('Diálogo de prueba', skipOffstage: false), findsOneWidget);

      // Back closes nothing under the lock
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
          find.text('Diálogo de prueba', skipOffstage: false), findsOneWidget);
      expect(find.text('Hoja de prueba', skipOffstage: false), findsOneWidget);

      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.text('Diálogo de prueba'), findsOneWidget);
      expect(find.text('Hoja de prueba'), findsOneWidget);
      expect(find.byType(InfoPage), findsOneWidget);

      // Unlocked, back works again
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Diálogo de prueba'), findsNothing);
      expect(find.text('Hoja de prueba'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('only a real trip to the background locks, not an inactive '
        'moment', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await typeCode(tester, '1234');
      now = now.add(const Duration(minutes: 1));

      // A system dialog (a permission request) or the recent apps peek
      lifecycle(
          tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);

      await tripToBackground(tester);
      expect(find.byType(CodeLockScreen), findsOneWidget);
      await typeCode(tester, '1234');
      expect(find.byType(CodeLockScreen), findsNothing);
    });

    testWidgets('an app opened from here (browser, mail, news link) does not '
        'lock on the way back, unless the app left later', (tester) async {
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await typeCode(tester, '1234');
      now = now.add(const Duration(minutes: 1));
      await openInfo(tester);

      // Custom Tabs from Info, the app leaves at once
      await scrollInfoTo(tester, 'Código fuente');
      await tester.tap(find.text('Código fuente'));
      await tester.pump();
      expect(browser.launches.last,
          'https://github.com/undermindOS/MVD_Transporte');
      now = now.add(const Duration(seconds: 1));
      lifecycle(tester, _toBackground);
      now = now.add(const Duration(minutes: 5));
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);

      // A news link («Ver más»)
      unawaited(openExternalLink(
          tester.element(find.byType(InfoPage)), 'https://montevideo.gub.uy/'));
      await tester.pump();
      expect(browser.launches.last, 'https://montevideo.gub.uy/');
      now = now.add(const Duration(seconds: 2));
      lifecycle(tester, _toBackground);
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);

      // The mail app, but the app leaves 4 s later: another trip, it locks
      await scrollInfoTo(tester, 'Contacto');
      await tester.tap(find.text('Contacto'));
      await tester.pump();
      expect(browser.launches.last, 'mailto:daniil@khrestenkov.com');
      now = now.add(const Duration(seconds: 4));
      lifecycle(tester, _toBackground);
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsOneWidget);
    });

    testWidgets('the system settings opened from «Paradas cercanas» do not '
        'lock on the way back', (tester) async {
      final geolocator = _FakeGeolocator();
      GeolocatorPlatform.instance = geolocator;
      await AppPasscode.set('1234');
      await pumpApp(tester);
      await typeCode(tester, '1234');
      now = now.add(const Duration(minutes: 1));

      // Location denied for good: «Abrir ajustes» is the only way back
      await tester.tap(find.byTooltip('Agregar parada'));
      await settle(tester);
      await tester.tap(find.text('Paradas cercanas'));
      await settle(tester);
      await tester.tap(find.text('Abrir ajustes'));
      await tester.pump();
      expect(geolocator.settingsOpened, isTrue);

      // Location turned on in the settings, then back
      now = now.add(const Duration(seconds: 1));
      lifecycle(tester, _toBackground);
      now = now.add(const Duration(minutes: 1));
      lifecycle(tester, _backFromBackground);
      await tester.pump();
      expect(find.byType(CodeLockScreen), findsNothing);
      expect(find.text('Abrir ajustes'), findsOneWidget);
    });

    testWidgets('Mis paradas requests nothing while locked', (tester) async {
      final arrivals = <Uri>[];
      final client = MockClient((request) async {
        if (request.url.path.startsWith('/transporteRest/siguientesParada/')) {
          arrivals.add(request.url);
        }
        return http.Response('[]', 200);
      });
      // Not awaited, as in test/stops_page_test.dart: let the IO finish
      CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await AppPasscode.set('1234');

      await http.runWithClient(() async {
        await pumpApp(tester);
        await typeCode(tester, '1234');
        expect(polling(tester), isTrue);
        final requested = arrivals.length;
        expect(requested, greaterThan(0));

        await tripToBackground(tester);
        await tester.pump(StopsPage.autoRefreshInterval * 3);
        expect(find.byType(CodeLockScreen), findsOneWidget);
        expect(polling(tester), isFalse);
        // Not even on the way back, nor while the code is typed
        await typeCode(tester, '12');
        expect(arrivals, hasLength(requested));

        // Unlocked: refreshed at once
        await typeCode(tester, '34');
        expect(polling(tester), isTrue);
        expect(arrivals, hasLength(requested + 1));
      }, () => client);
      CacheService.deleteStop(574);
    });

    testWidgets('the Mapa requests nothing while locked', (tester) async {
      final arrivals = <Uri>[];
      final client = MockClient((request) async {
        if (request.url.path.startsWith('/transporteRest/siguientesParada/')) {
          arrivals.add(request.url);
        }
        return http.Response('[]', 200);
      });
      // Not awaited, as in test/stops_page_test.dart: let the IO finish
      CacheService.saveStop(BusStop(
          id: 574,
          name: 'SAN JOSE y ANDES',
          latitude: -34.90739436,
          longitude: -56.198255));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await AppPasscode.set('1234');
      // No tiles: the bundled basemap is not read inside fake async
      MapaPage.defaultBasemapLoader = () async => MapaBasemap(
          bounds: LatLngBounds(
              const LatLng(-34.97, -56.80), const LatLng(-34.50, -55.70)),
          attribution: '© OpenStreetMap');
      addTearDown(() {
        MvdApiService.resetLatestBoards();
        MapaPage.clock = DateTime.now;
        MapaPage.defaultBasemapLoader = MapaBasemap.bundled;
      });
      bool mapaPolling() => tester
          .widget<MapaPage>(find.byType(MapaPage, skipOffstage: false))
          .active;

      await http.runWithClient(() async {
        await pumpApp(tester);
        await typeCode(tester, '1234');
        await tester.tap(find.text('Mapa'));
        await tester.pump();
        expect(mapaPolling(), isTrue);
        final requested = arrivals.length;
        expect(requested, greaterThan(0));

        // Back minutes later: the boards are old, only the lock holds the
        // refresh
        MapaPage.clock = () => DateTime.now().add(const Duration(minutes: 6));
        await tripToBackground(tester);
        await tester.pump(StopsPage.autoRefreshInterval * 3);
        expect(find.byType(CodeLockScreen), findsOneWidget);
        expect(mapaPolling(), isFalse);
        // Not even on the way back
        expect(arrivals, hasLength(requested));

        // Unlocked: refreshed at once
        await typeCode(tester, '1234');
        expect(mapaPolling(), isTrue);
        expect(arrivals, hasLength(requested + 1));
      }, () => client);
      CacheService.deleteStop(574);
    });
  });
}

// --- Fakes -----------------------------------------------------------------

class _FakeAuth implements DeviceAuth {
  /// Every prompt, in order.
  final prompts = <({String reason, bool biometricOnly})>[];

  List<String> get reasons => [for (final prompt in prompts) prompt.reason];

  List<bool> get biometricOnlyFlags =>
      [for (final prompt in prompts) prompt.biometricOnly];

  /// The sticky flag of every prompt, in the same order.
  final sticky = <bool>[];

  /// The phone has a screen lock (or biometrics it accepts without one).
  bool available = true;

  /// What the phone offers for the quick unlock; null = nothing enrolled.
  BiometricKind? kind;

  /// The answers of the next prompts, one each: true or false, an error to
  /// throw, or null to keep that prompt open until [answer] or [fail].
  final answers = <Object?>[];

  /// After [answers]: every prompt throws [error] if set, else answers
  /// [autoAnswer]; null keeps each prompt open until [answer].
  Object? error;
  bool? autoAnswer = true;
  Completer<bool>? _open;

  void answer(bool ok) {
    final prompt = _open!;
    _open = null;
    prompt.complete(ok);
  }

  void fail(Object error) {
    final prompt = _open!;
    _open = null;
    prompt.completeError(error);
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind?> biometrics() async => kind;

  @override
  Future<bool> authenticate(String reason,
      {bool biometricOnly = false, bool sticky = true}) async {
    prompts.add((reason: reason, biometricOnly: biometricOnly));
    this.sticky.add(sticky);
    final next =
        answers.isNotEmpty ? answers.removeAt(0) : (error ?? autoAnswer);
    if (next == null) return (_open = Completer<bool>()).future;
    if (next is bool) return next;
    throw next;
  }
}

class _FakeBrowser extends UrlLauncherPlatform {
  final launches = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add(url);
    return true;
  }
}

/// Location denied for good («No volver a preguntar»).
class _FakeGeolocator extends GeolocatorPlatform {
  bool settingsOpened = false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;

  @override
  Future<bool> openAppSettings() async => settingsOpened = true;
}
