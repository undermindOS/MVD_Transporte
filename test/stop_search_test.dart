// "Agregar parada" → "Buscar por calles": the stop catalog of the proxy,
// searched by street names, and the picked stop saved as listed, with no
// lookup. HTTP is faked with live proxy answers (test/fixtures,
// 2026-10-19).
//
// A file of its own, not test/stops_page_test.dart: Hive serialises the
// writes of a box on a future, and a future completed in an earlier test's
// fake-async zone never wakes up a later test. So in each file only the
// first test can wait for a write to the stops box, and saving the picked
// stop does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_text.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

const _stop574 = '{"id":574,"name":"SAN JOSE y ANDES",'
    '"lines":["116","117","121","141","142","144","538"]}';

void main() {
  late Directory hiveDir;
  final requests = <Uri>[];
  // The 2026-10-19 capture predates lines in the catalog: 574 gets those
  // of the contract's golden (proxy/contract/v1/responses)
  final catalog = () {
    final body = jsonDecode(
            File('test/fixtures/proxy_catalog_stops.json').readAsStringSync())
        as Map<String, dynamic>;
    body['linesAvailable'] = true;
    for (final stop in body['stops'] as List) {
      if (stop['id'] == 574) {
        stop['lines'] = ['116', '117', '121', '141', '142', '144', '538'];
      }
    }
    return utf8.encode(jsonEncode(body));
  }();

  final client = MockClient((request) async {
    requests.add(request.url);
    return switch (request.url.path) {
      '/v1/catalog/stops' => http.Response.bytes(catalog, 200),
      '/v1/stops/574' => http.Response(_stop574, 200),
      '/v1/stops/574/arrivals' => http.Response('{"arrivals":[]}', 200),
      _ => http.Response('{"error":"not_found"}', 404),
    };
  });

  Widget app() => MaterialApp(
      theme: buildTimbreTheme(),
      home: StopsPage(onOpenStopInComoIr: (_) {}));

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);
  final streets = find.widgetWithText(TextField, 'Buscar por calles');

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_stop_search_test');
    await CacheService.init(path: hiveDir.path);
  });

  setUp(() {
    MvdApiService.proxyUrl = 'https://proxy.test';
    requests.clear();
  });

  tearDown(() => MvdApiService.proxyUrl = '');

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('finds a stop by its streets and saves the picked one',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();

      // The catalog is downloaded only when the user types a street
      bool catalogRequested() =>
          requests.any((u) => u.path == '/v1/catalog/stops');
      expect(catalogRequested(), isFalse);

      await tester.enterText(streets, 'san josé andes');
      await tester.pump();
      expect(catalogRequested(), isTrue);
      // The copy kept in Hive is written for real, two awaited writes: each
      // needs real time, then a pump. The spinner spins meanwhile, so no
      // pumpAndSettle until it is gone.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }

      expect(inDialog(find.byType(CircularProgressIndicator)), findsNothing);
      expect(inDialog(find.byType(ListTile)), findsOneWidget);
      expect(inDialog(find.text('SAN JOSE y ANDES')), findsOneWidget);
      expect(inDialog(find.text('#574')), findsOneWidget);
      // One phrase per tile, the street names in words
      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(
              find.bySemanticsLabel('Parada 574, San Jose y Andes')),
          isSemantics(isButton: true, hasTapAction: true));
      handle.dispose();
      // In the app font, not the platform one
      final number = tester.widget<RichText>(find.descendant(
          of: inDialog(find.text('#574')), matching: find.byType(RichText)));
      expect(number.text.style?.fontFamily, TimbreFonts.fira);

      // Streets in any order
      await tester.enterText(streets, 'ejido 18 de julio');
      await tester.pump();
      expect(inDialog(find.byType(ListTile)), findsOneWidget);
      expect(inDialog(find.text('AV 18 DE JULIO y EJIDO')), findsOneWidget);

      await tester.enterText(streets, 'calle que no existe');
      await tester.pump();
      expect(inDialog(find.text('Ninguna parada coincide')), findsOneWidget);

      await tester.enterText(streets, 'andes san jose');
      await tester.pump();
      await tester.tap(inDialog(find.text('SAN JOSE y ANDES')));
      await tester.pumpAndSettle();
      // Hive writes to disk for real: let saveStop finish outside fake async
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Saved as listed, with the catalog's lines: no /v1/stops/574
      expect(requests.map((u) => u.path), isNot(contains('/v1/stops/574')));
      expect(find.text('Buscando parada…'), findsNothing);
      final saved = CacheService.getStop(574);
      expect(saved, isNotNull);
      expect(saved!.name, 'SAN JOSE y ANDES');
      expect(saved.lines, ['116', '117', '121', '141', '142', '144', '538']);
      // and where the catalog puts it, for the Mapa
      expect((saved.latitude, saved.longitude), (-34.90739436, -56.198255));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('#574'), findsOneWidget);
    }, () => client);
  });

  testWidgets('a catalog that cannot be loaded is reported', (tester) async {
    // No copy on the device either. Not awaited (see the top of the file):
    // removing the catalog key drops the copy at once, before the lazy
    // box reaches the disk.
    MvdApiService.clearCatalogMemory();
    CacheService.remove(CacheService.keyStopCatalog);
    final offline = MockClient((request) async {
      requests.add(request.url);
      throw http.ClientException('offline');
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();
      await tester.enterText(streets, 'ejido');
      await tester.pumpAndSettle();

      expect(
          inDialog(find.text(
              'No se pudo cargar la lista de paradas. Revisá la conexión.')),
          findsOneWidget);
      expect(inDialog(find.byType(ListTile)), findsNothing);
    }, () => offline);
  });

  testWidgets('without the proxy there is no search by streets',
      (tester) async {
    MvdApiService.proxyUrl = '';
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();

      expect(find.text('Paradas cercanas'), findsOneWidget);
      expect(streets, findsNothing);
    }, () => client);
  });
}
