// Smoke tests for MVD Transporte: the app starts, the bottom navigation
// works and official sites open in the system browser, never in a WebView.
//
// Runs with fake browser and auth platforms (no Custom Tabs, Safari or
// biometrics in unit tests) and Hive stored in a temp directory (no
// path_provider in unit tests).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:stm_app/main.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/official_sites.dart';
import 'package:stm_app/ui/lock_screen.dart';

import 'support/layout.dart';

void main() {
  late Directory hiveDir;
  late _FakeBrowser browser;
  late _FakeLocalAuth auth;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDir = await Directory.systemTemp.createTemp('mvd_hive_test');
    await CacheService.init(path: hiveDir.path);
  });

  setUp(() {
    browser = _FakeBrowser();
    UrlLauncherPlatform.instance = browser;
    auth = _FakeLocalAuth();
    LocalAuthPlatform.instance = auth;
  });

  tearDown(() async {
    await CacheService.remove(CacheService.keyBiometricEnabled);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('opens on Mis paradas with two native tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(find.text('MIS PARADAS'), findsOneWidget); // the header sign
    expect(find.text('Mis paradas'), findsOneWidget); // nav label
    expect(find.text('Servicios'), findsOneWidget);
    expect(find.text('SIN PARADAS'), findsOneWidget);
    expect(find.byTooltip('Info'), findsOneWidget);
  });

  testWidgets('Servicios lists the official sites',
      (WidgetTester tester) async {
    // Portrait phone: the 800 × 600 test window hides the last tile
    usePhoneScreen(tester);
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    await tester.tap(find.text('Servicios'));
    await tester.pump();

    expect(find.text('SERVICIOS'), findsOneWidget);
    for (final title in ['Mi STM', 'Recarga', 'Cómo Ir', 'Avisos']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(browser.launches, isEmpty);
  });

  testWidgets('Mi STM opens in Custom Tabs / SFSafariViewController',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    await tester.tap(find.text('Servicios'));
    await tester.pump();
    await tester.tap(find.text('Mi STM'));
    await tester.pump();

    expect(browser.launches, hasLength(1));
    expect(browser.launches.single.url, OfficialSite.miStm.url);
    expect(browser.launches.single.mode, PreferredLaunchMode.inAppBrowserView);
  });

  testWidgets('without a Custom Tabs browser the full browser opens',
      (WidgetTester tester) async {
    browser.supportsInApp = false;
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    await tester.tap(find.text('Servicios'));
    await tester.pump();
    await tester.tap(find.text('Recarga'));
    await tester.pump();

    expect(browser.launches.single.url, OfficialSite.recarga.url);
    expect(browser.launches.single.mode,
        PreferredLaunchMode.externalApplication);
  });

  testWidgets('a failed launch is reported', (WidgetTester tester) async {
    browser.result = false;
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    await tester.tap(find.text('Servicios'));
    await tester.pump();
    await tester.tap(find.text('Avisos'));
    await tester.pump();

    expect(find.text('No se pudo abrir el navegador'), findsOneWidget);
  });

  testWidgets('Ver en Cómo Ir opens the stop deep link',
      (WidgetTester tester) async {
    // Hive does real file I/O, which never completes in the fake-async zone
    await tester.runAsync(() =>
        CacheService.saveStop(BusStop(id: 1234, name: 'Parada de prueba')));

    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    await tester.tap(find.text('Ver en Cómo Ir'));
    await tester.pump();

    expect(browser.launches.single.url,
        'https://m.montevideo.gub.uy/comoir/parada?numero=1234');
    expect(browser.launches.single.mode, PreferredLaunchMode.inAppBrowserView);

    await tester.runAsync(() => CacheService.deleteStop(1234));
  });

  testWidgets('coming back from the browser does not re-lock, '
      'a later trip to the background does', (WidgetTester tester) async {
    await tester.runAsync(
        () => CacheService.set(CacheService.keyBiometricEnabled, true));
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();
    // Wait out the grace period after the startup unlock
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)));
    expect(auth.calls, 1);

    await tester.tap(find.text('Servicios'));
    await tester.pump();
    await tester.tap(find.text('Mi STM'));
    await tester.pump();

    // A Custom Tab is another activity: the app pauses, then resumes
    void cycle() {
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
    }

    cycle();
    await tester.pump();
    expect(auth.calls, 1);
    expect(find.byType(LockScreen), findsNothing);

    cycle();
    await tester.pump();
    expect(auth.calls, 2);
  });
}

// --- Fake platforms --------------------------------------------------------

class _FakeBrowser extends UrlLauncherPlatform {
  final launches = <({String url, PreferredLaunchMode mode})>[];
  bool supportsInApp = true;
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async =>
      mode == PreferredLaunchMode.inAppBrowserView
          ? supportsInApp
          : mode == PreferredLaunchMode.externalApplication;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url: url, mode: options.mode));
    return result;
  }
}

class _FakeLocalAuth extends LocalAuthPlatform {
  int calls = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    calls++;
    return true;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;
}
