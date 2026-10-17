// Smoke test for MVD Transporte: the app starts and the bottom navigation works.
//
// Runs with a fake WebView platform (no native WebView in unit tests) and
// Hive stored in a temp directory (no path_provider in unit tests).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:stm_app/main.dart';
import 'package:stm_app/services/cache_service.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDir = await Directory.systemTemp.createTemp('mvd_hive_test');
    await CacheService.init(path: hiveDir.path);
    WebViewPlatform.instance = _FakeWebViewPlatform();
    // home_widget event channel (widget button clicks): no native side in tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget/updates'), (_) async => null);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('MVD Transporte App loads with bottom navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    // Verify that bottom navigation bar exists with all 5 items.
    expect(find.byType(NavigationBar), findsOneWidget);

    // Verify navigation labels are present.
    expect(find.text('Inicio'), findsWidgets); // AppBar title + nav label
    expect(find.text('Recarga'), findsOneWidget);
    expect(find.text('Mis paradas'), findsOneWidget);
    expect(find.text('Cómo Ir'), findsOneWidget);
    expect(find.text('Avisos'), findsOneWidget);

    // Verify navigation icons are present.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.credit_card_outlined), findsOneWidget);
    expect(find.byIcon(Icons.directions_bus_outlined), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

    // Verify Info button in AppBar.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('Bottom navigation interaction test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    // Tap on 'Recarga' tab (index 1) — AppBar title follows
    await tester.tap(find.text('Recarga'));
    await tester.pump();
    expect(find.text('Recarga'), findsNWidgets(2));

    // Native tab with saved stops/routes (empty storage)
    await tester.tap(find.text('Mis paradas'));
    await tester.pump();
    expect(find.text('Sin paradas guardadas'), findsOneWidget);

    // Tap on 'Avisos' tab (index 4)
    await tester.tap(find.text('Avisos'));
    await tester.pump();
    expect(find.text('Avisos'), findsNWidgets(2));
  });

  testWidgets('WebContent crash: one reload, then an error with retry',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();
    _FakeWebViewPlatform.reloads = 0;

    const crash = WebResourceError(
      errorCode: 2,
      description: '',
      errorType: WebResourceErrorType.webContentProcessTerminated,
      isForMainFrame: true,
    );

    // First crash: silent reload, still loading
    _FakeWebViewPlatform.onError!(crash);
    await tester.pump();
    expect(_FakeWebViewPlatform.reloads, 1);
    expect(find.text('No se pudo cargar la página'), findsNothing);

    // Second crash: error screen instead of an endless spinner
    _FakeWebViewPlatform.onError!(crash);
    await tester.pump();
    expect(_FakeWebViewPlatform.reloads, 1);
    expect(find.text('No se pudo cargar la página'), findsOneWidget);
    expect(find.text('Cargando...'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('Sub-resource errors keep the page', (WidgetTester tester) async {
    await tester.pumpWidget(const MiTransporteMVDApp());
    await tester.pump();

    _FakeWebViewPlatform.onError!(const WebResourceError(
      errorCode: -1009,
      description: 'image failed',
      isForMainFrame: false,
    ));
    await tester.pump();
    expect(find.text('No se pudo cargar la página'), findsNothing);
  });
}

// --- Fake WebView platform -------------------------------------------------

class _FakeWebViewPlatform extends WebViewPlatform {
  // Lets tests fire WebView errors (the old fake never did, which hid the
  // endless "Cargando..." on a crashed iOS WebContent process).
  static WebResourceErrorCallback? onError;
  static int reloads = 0;

  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      _FakeController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _FakeWebViewWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setUserAgent(String? userAgent) async {}
  @override
  Future<void> enableZoom(bool enabled) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> setOnPlatformPermissionRequest(
      void Function(PlatformWebViewPermissionRequest request)
          onPermissionRequest) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<void> goBack() async {}
  @override
  Future<void> reload() async => _FakeWebViewPlatform.reloads++;
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback onNavigationRequest) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}
  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
  @override
  Future<void> setOnWebResourceError(
      WebResourceErrorCallback onWebResourceError) async {
    _FakeWebViewPlatform.onError = onWebResourceError;
  }
  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
