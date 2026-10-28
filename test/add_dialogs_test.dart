// "Agregar ruta" and "Agregar parada" through the proxy. The route's HACIA
// chips come from the stop's directions (/v1/stops/{id}), each carrying
// the variants of its destination, and fall back to the upcoming buses
// for a line without directions. A typed stop number is looked up once:
// one that cannot exist is refused with no request, one typed offline is
// kept as "Parada N" and named on the next start.
//
// In a widget test only the first test of a file that writes to a Hive
// box can wait for that write: the first test saves the route (routes
// box), the second the stop (stops box); the others save nothing.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

const _responses = 'proxy/contract/v1/responses';

// Stop 574 as a complete stop index would give it: 117 and 121 both go
// to PUNTA CARRETAS, on variants of their own
const _stop574 = '{"id":574,"name":"SAN JOSE y ANDES",'
    '"lines":["116","117","121","141","142","144","538"],'
    '"directions":['
    '{"line":"116","destination":"POCITOS","variantIds":[630]},'
    '{"line":"117","destination":"PUNTA CARRETAS","variantIds":[2779]},'
    '{"line":"121","destination":"PUNTA CARRETAS","variantIds":[7884]}]}';
// No bus coming
const _noBuses =
    '{"id":574,"fetchedAt":"2026-10-27T13:00:00.000Z","arrivals":[]}';

void main() {
  late Directory hiveDir;
  final requests = <String>[];
  late Future<http.Response> Function(http.Request request) answer;

  http.Response golden(String name) => http.Response.bytes(
      File('$_responses/$name').readAsBytesSync(), 200);
  final client = MockClient((request) {
    requests.add(request.url.path);
    return answer(request);
  });

  Widget app() => MaterialApp(
      theme: buildTimbreTheme(),
      home: StopsPage(onOpenStopInComoIr: (_) {}));

  Finder chip(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilterChip, text));
  Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog), matching: find.text(text));
  final numberField = find.widgetWithText(TextField, 'Número de parada');

  /// Opens "Agregar ruta" and looks up stop 574.
  Future<void> lookUpRoute(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('Rutas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar ruta'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Parada de origen *'), '574');
    await tester.enterText(
        find.widgetWithText(TextField, 'Destino *'), 'Trabajo');
    await tester.tap(find.byTooltip('Ver líneas'));
    await tester.pumpAndSettle();
  }

  // Real time for each awaited Hive write, then a frame
  Future<void> letHiveWrite(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  setUpAll(() async {
    // Saving a route asks for the notification permission
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (_) async => true);
    hiveDir = await Directory.systemTemp.createTemp('mvd_add_dialogs_test');
    await CacheService.init(path: hiveDir.path);
    MvdApiService.proxyUrl = 'https://proxy.test';
  });

  setUp(() {
    requests.clear();
    answer = (request) async => switch (request.url.path) {
          '/v1/stops/574' => http.Response(_stop574, 200),
          '/v1/stops/574/arrivals' => http.Response(_noBuses, 200),
          _ => http.Response('{"error":"not_found"}', 404),
        };
  });

  tearDownAll(() async {
    MvdApiService.proxyUrl = '';
    await hiveDir.delete(recursive: true);
  });

  testWidgets('HACIA comes from the directions, even with no bus coming',
      (tester) async {
    // A small phone: the dialog and the chips must fit
    tester.view.physicalSize = const Size(360, 690) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await http.runWithClient(() async {
      await lookUpRoute(tester);

      expect(inDialog('SAN JOSE y ANDES'), findsOneWidget);
      for (final line in ['116', '117', '121', '141', '142', '144', '538']) {
        expect(chip(line), findsOneWidget, reason: line);
      }
      // One chip per destination, whatever the lines that go there
      expect(chip('POCITOS'), findsOneWidget);
      expect(chip('PUNTA CARRETAS'), findsOneWidget);
      await tester.tap(chip('117'));
      await tester.tap(chip('121'));
      await tester.pumpAndSettle();
      expect(chip('POCITOS'), findsNothing);
      await tester.ensureVisible(chip('PUNTA CARRETAS'));
      await tester.pumpAndSettle();
      await tester.tap(chip('PUNTA CARRETAS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await letHiveWrite(tester);

      final route = CacheService.getAllRoutes().single;
      expect((route.originStopId, route.originName, route.destinationName),
          (574, 'SAN JOSE y ANDES', 'Trabajo'));
      expect(route.preferredLines, ['117', '121']);
      expect(route.preferredDestinations, ['PUNTA CARRETAS']);
      // Both lines' variants: a bus of either matches, whatever its label
      expect(route.preferredVariantIds, [2779, 7884]);
      // The stop was looked up once, by the dialog
      expect(requests.where((p) => p == '/v1/stops/574'), hasLength(1));
      expect(find.text('Líneas: 117, 121 · Hacia: PUNTA CARRETAS'),
          findsOneWidget);
    }, () => client);
  });

  testWidgets('a number typed offline is kept as "Parada N", named later',
      (tester) async {
    var offline = true;
    final online = answer;
    answer = (request) async =>
        offline ? throw http.ClientException('offline') : online(request);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();
      await tester.enterText(numberField, '574');
      await tester.tap(find.text('Agregar'));
      await tester.pump();
      await letHiveWrite(tester);

      expect(requests, contains('/v1/stops/574'));
      final saved = CacheService.getStop(574)!;
      expect(saved.name, 'Parada 574');
      expect(saved.lines, isEmpty);
      expect(find.text('Parada 574'), findsOneWidget);

      // The next start, online: the placeholder gets its name and lines
      offline = false;
      requests.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump();
      await letHiveWrite(tester);

      expect(requests, contains('/v1/stops/574'));
      expect(CacheService.getStop(574)!.lines,
          ['116', '117', '121', '141', '142', '144', '538']);
      expect(find.text('SAN JOSE y ANDES'), findsOneWidget);
      expect(find.text('Parada 574'), findsNothing);
    }, () => client);
  });

  testWidgets('a number that cannot be a stop is refused without a request',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      requests.clear();
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();

      // At most 7 digits
      await tester.enterText(numberField, '123456789');
      expect(find.text('1234567'), findsOneWidget);

      await tester.enterText(numberField, '0');
      await tester.tap(find.text('Agregar'));
      await tester.pump();
      expect(find.text('No existe la parada 0. Revisá el número.'),
          findsOneWidget);
      expect(find.text('Buscando parada…'), findsNothing);
      expect(requests.where((p) => p.startsWith('/v1/stops/0')), isEmpty);
    }, () => client);
  });

  testWidgets('without directions HACIA falls back to the upcoming buses',
      (tester) async {
    tester.view.physicalSize = const Size(360, 690) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    answer = (request) async => switch (request.url.path) {
          '/v1/stops/574' => http.Response(
              _stop574.replaceFirst(
                  RegExp(r'"directions":\[.*\]\}$'), '"directions":[]}'),
              200),
          '/v1/stops/574/arrivals' => golden('arrivals_574.json'),
          _ => http.Response('{"error":"not_found"}', 404),
        };

    await http.runWithClient(() async {
      await lookUpRoute(tester);

      for (final destination in [
        'CEMENTERIO DEL NORTE',
        'GRAL FLORES Y JOSÉ SERRATO',
        'POCITOS',
        'PUNTA CARRETAS',
        'RAMBLA COSTANERA',
      ]) {
        expect(chip(destination), findsOneWidget, reason: destination);
      }
      await tester.tap(chip('144'));
      await tester.pumpAndSettle();
      expect(chip('CEMENTERIO DEL NORTE'), findsOneWidget);
      expect(chip('POCITOS'), findsNothing);
    }, () => client);
  });

  testWidgets('a line without directions takes its upcoming buses',
      (tester) async {
    tester.view.physicalSize = const Size(360, 690) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The golden: directions for the 116 only
    answer = (request) async => switch (request.url.path) {
          '/v1/stops/574' => golden('stop_574.json'),
          '/v1/stops/574/arrivals' => golden('arrivals_574.json'),
          _ => http.Response('{"error":"not_found"}', 404),
        };

    await http.runWithClient(() async {
      await lookUpRoute(tester);

      await tester.tap(chip('116'));
      await tester.pumpAndSettle();
      expect(chip('POCITOS'), findsOneWidget);
      expect(chip('CEMENTERIO DEL NORTE'), findsNothing);
      // The 144 has no direction: its bus says where it goes
      await tester.tap(chip('144'));
      await tester.pumpAndSettle();
      expect(chip('POCITOS'), findsOneWidget);
      expect(chip('CEMENTERIO DEL NORTE'), findsOneWidget);
      expect(chip('PUNTA CARRETAS'), findsNothing);
    }, () => client);
  });
}
