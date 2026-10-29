// The biometric lock covers the whole app: pages, sheets, dialogs and
// snackbars pushed over the home page, not only the home page.
//
// Runs the real app with a fake system prompt (DeviceAuth), a fake browser
// launcher and Hive in a temp directory. The lock's clock is moved by hand.
//
// The first test awaits a Hive write to the settings box (the Info switch):
// only the first test of a file can (see test/stop_search_test.dart).

import 'dart:async';
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
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/app_lock.dart';
import 'package:stm_app/ui/home_page.dart';
import 'package:stm_app/ui/info_page.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/lock_screen.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/news_list.dart';
import 'package:stm_app/ui/stops_page.dart';

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

void main() {
  late Directory hiveDir;
  late _FakeAuth auth;
  late _FakeBrowser browser;
  late DateTime now;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_lock_test');
    await CacheService.init(path: hiveDir.path);
  });

  setUp(() {
    auth = _FakeAuth();
    browser = _FakeBrowser();
    UrlLauncherPlatform.instance = browser;
    now = DateTime(2026, 10, 27, 9);
    AppLock.clock = () => now;
  });

  tearDown(() => AppLock.clock = DateTime.now);

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  /// Not awaited: the value is in memory at once (see the header).
  void lockSetting(bool enabled) => unawaited(
      CacheService.set(CacheService.keyBiometricEnabled, enabled));

  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(MiTransporteMVDApp(deviceAuth: auth));
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

  testWidgets('turning the lock on in Info asks the system prompt first',
      (tester) async {
    // Off: nothing stored yet
    await pumpApp(tester);
    expect(auth.reasons, isEmpty);
    await openInfo(tester);
    bool switchOn() => tester.widget<Switch>(find.byType(Switch)).value;

    // Cancelled: stays off
    auth.autoAnswer = false;
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(auth.reasons, ['Confirmá para activar el bloqueo biométrico']);
    expect(switchOn(), isFalse);
    // Nothing written
    expect(CacheService.get<bool>(CacheService.keyBiometricEnabled), isNull);

    // Confirmed: on, after the setting reaches the disk
    auth.autoAnswer = true;
    await tester.tap(find.byType(Switch));
    await tester.pump();
    // Real IO, queued behind the writes the app made at start
    for (var i = 0; i < 5 && !switchOn(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(auth.reasons, hasLength(2));
    expect(switchOn(), isTrue);
    expect(CacheService.get<bool>(CacheService.keyBiometricEnabled), isTrue);
    expect(find.text('Bloqueo biométrico activado'), findsOneWidget);
    // The lock waits for the next trip to the background
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('with the lock on, nothing of the app is built before the '
      'first unlock', (tester) async {
    lockSetting(true);
    auth.autoAnswer = null;
    await pumpApp(tester);

    expect(auth.reasons, ['Autenticate para acceder a Timbre MVD']);
    expect(find.byType(LockScreen), findsOneWidget);
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
  });

  testWidgets('locked, a page, a sheet, a dialog and a snackbar are out of '
      'sight and reach; unlocking brings them back', (tester) async {
    final semantics = tester.ensureSemantics();
    lockSetting(true);
    await pumpApp(tester);
    expect(find.byType(LockScreen), findsNothing);

    // Info, a sheet over it, a dialog over the sheet, a snackbar
    await openInfo(tester);
    final info = tester.element(find.byType(InfoPage));
    unawaited(showModalBottomSheet<void>(
      context: info,
      builder: (_) => const SizedBox(height: 200, child: Text('Hoja de prueba')),
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
    expect(find.text('Aviso de prueba'), findsWidgets);
    expect(find.semantics.byLabel('Diálogo de prueba'), findsOneWidget);

    auth.autoAnswer = null;
    await tripToBackground(tester);
    expect(auth.reasons, hasLength(2));
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.semantics.byLabel('Aplicación bloqueada'), findsOneWidget);
    for (final text in [
      'Bloqueo biométrico',
      'Hoja de prueba',
      'Diálogo de prueba',
      'Aviso de prueba',
    ]) {
      expect(find.text(text), findsNothing, reason: text);
      expect(find.semantics.byLabel(RegExp(text)), findsNothing,
          reason: text);
    }
    // Kept as they were
    expect(find.text('Diálogo de prueba', skipOffstage: false), findsOneWidget);

    // Back closes nothing under the lock
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Diálogo de prueba', skipOffstage: false), findsOneWidget);
    expect(find.text('Hoja de prueba', skipOffstage: false), findsOneWidget);

    auth.answer(true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
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
    lockSetting(true);
    await pumpApp(tester);
    expect(auth.reasons, hasLength(1));
    now = now.add(const Duration(minutes: 1));

    // A system dialog (a permission request) or the recent apps peek
    lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.reasons, hasLength(1));

    auth.autoAnswer = null;
    await tripToBackground(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(auth.reasons, hasLength(2));

    auth.answer(true);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('an app opened from here (browser, mail, news link) does not '
      'lock on the way back, unless the app left later', (tester) async {
    lockSetting(true);
    await pumpApp(tester);
    now = now.add(const Duration(minutes: 1));
    await openInfo(tester);

    // Custom Tabs from Info, the app leaves at once
    await scrollInfoTo(tester, 'Código fuente');
    await tester.tap(find.text('Código fuente'));
    await tester.pump();
    expect(browser.launches.last, 'https://github.com/undermindOS/MVD_Transporte');
    now = now.add(const Duration(seconds: 1));
    lifecycle(tester, _toBackground);
    now = now.add(const Duration(minutes: 5));
    lifecycle(tester, _backFromBackground);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.reasons, hasLength(1));

    // A news link («Ver más»)
    unawaited(openExternalLink(
        tester.element(find.byType(InfoPage)), 'https://montevideo.gub.uy/'));
    await tester.pump();
    expect(browser.launches.last, 'https://montevideo.gub.uy/');
    now = now.add(const Duration(seconds: 2));
    lifecycle(tester, _toBackground);
    lifecycle(tester, _backFromBackground);
    await tester.pump();
    expect(auth.reasons, hasLength(1));

    // The mail app, but the app leaves 4 s later: another trip, it locks
    await scrollInfoTo(tester, 'Contacto');
    await tester.tap(find.text('Contacto'));
    await tester.pump();
    expect(browser.launches.last, 'mailto:daniil@khrestenkov.com');
    now = now.add(const Duration(seconds: 4));
    lifecycle(tester, _toBackground);
    lifecycle(tester, _backFromBackground);
    await tester.pump();
    expect(auth.reasons, hasLength(2));
  });

  testWidgets('the system settings opened from «Paradas cercanas» do not '
      'lock on the way back', (tester) async {
    final geolocator = _FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;
    lockSetting(true);
    await pumpApp(tester);
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
    auth.autoAnswer = null;
    now = now.add(const Duration(seconds: 1));
    lifecycle(tester, _toBackground);
    now = now.add(const Duration(minutes: 1));
    lifecycle(tester, _backFromBackground);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.reasons, hasLength(1));
    expect(find.text('Abrir ajustes'), findsOneWidget);
  });

  testWidgets('a locked-out prompt keeps the lock (fail closed)',
      (tester) async {
    lockSetting(true);
    auth.error = PlatformException(code: auth_error.lockedOut);
    await pumpApp(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(HomePage, skipOffstage: false), findsNothing);
  });

  testWidgets('a phone with no lock method opens the app', (tester) async {
    lockSetting(true);
    auth.error = PlatformException(code: auth_error.notAvailable);
    await pumpApp(tester);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('MIS PARADAS'), findsOneWidget);
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
    lockSetting(true);

    await http.runWithClient(() async {
      await pumpApp(tester);
      expect(polling(tester), isTrue);
      final requested = arrivals.length;
      expect(requested, greaterThan(0));

      auth.autoAnswer = null;
      await tripToBackground(tester);
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(polling(tester), isFalse);
      // Not even on the way back
      expect(arrivals, hasLength(requested));

      // Unlocked: refreshed at once
      auth.answer(true);
      await tester.pump();
      await tester.pump();
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
    lockSetting(true);
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
      await tester.tap(find.text('Mapa'));
      await tester.pump();
      expect(mapaPolling(), isTrue);
      final requested = arrivals.length;
      expect(requested, greaterThan(0));

      // Back minutes later: the boards are old, only the lock holds the
      // refresh
      MapaPage.clock = () => DateTime.now().add(const Duration(minutes: 6));
      auth.autoAnswer = null;
      await tripToBackground(tester);
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(mapaPolling(), isFalse);
      // Not even on the way back
      expect(arrivals, hasLength(requested));

      // Unlocked: refreshed at once
      auth.answer(true);
      await tester.pump();
      await tester.pump();
      expect(mapaPolling(), isTrue);
      expect(arrivals, hasLength(requested + 1));
    }, () => client);
    CacheService.deleteStop(574);
  });
}

// --- Fakes -----------------------------------------------------------------

class _FakeAuth implements DeviceAuth {
  final reasons = <String>[];
  Object? error;

  /// The answer of every prompt. null keeps each prompt open until
  /// [answer].
  bool? autoAnswer = true;
  Completer<bool>? _open;

  void answer(bool ok) {
    final prompt = _open!;
    _open = null;
    prompt.complete(ok);
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    if (error case final error?) throw error;
    if (autoAnswer case final answer?) return answer;
    return (_open = Completer<bool>()).future;
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
