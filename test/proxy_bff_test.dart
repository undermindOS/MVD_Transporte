// A build with the proxy, as the user sees it: the "Datos GPS parciales"
// warning comes from /v1/status/gps, the news badge from /v1/news, the
// board and the nearby stops from the proxy too, and no city host is ever
// asked (docs/privacy-policy.md). HTTP answers are the contract's goldens
// (proxy/contract/v1/responses); the location is faked.
//
// One test: the news and the catalog are kept in Hive, and in a widget
// test only the first test of a file can wait for a Hive write.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/bus_status_service.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

const _responses = 'proxy/contract/v1/responses';
const _cityHosts = {
  'api.montevideo.gub.uy',
  'pci.montevideo.gub.uy',
  'geoserver.montevideo.gub.uy',
};
// CUTCSA sends GPS for 40 % of its buses
const _gpsPartial = '{"fetchedAt":"2026-10-27T13:23:30.000Z","operators":['
    '{"company":"COETC","percent":100,"partial":false},'
    '{"company":"CUTCSA","percent":40,"partial":true}]}';

void main() {
  late Directory hiveDir;
  final requests = <Uri>[];

  http.Response file(String path) =>
      http.Response.bytes(File(path).readAsBytesSync(), 200);
  final client = MockClient((request) async {
    requests.add(request.url);
    return switch (request.url.path) {
      '/v1/stops/574/arrivals' => file('$_responses/arrivals_574.json'),
      '/v1/status/gps' => http.Response(_gpsPartial, 200),
      '/v1/news' => file('$_responses/news_cold.json'),
      '/v1/catalog/stops' => file('$_responses/catalog_sample.json'),
      _ => http.Response('{"error":"not_found"}', 404),
    };
  });

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  // Real time for each awaited Hive write, then a frame
  Future<void> letHiveWrite(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_proxy_bff_test');
    await CacheService.init(path: hiveDir.path);
    await CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
    BusStatusService.reset();
    GeolocatorPlatform.instance = _FakeGeolocator();
    MvdApiService.proxyUrl = 'https://proxy.test';
  });

  tearDownAll(() async {
    MvdApiService.proxyUrl = '';
    await hiveDir.delete(recursive: true);
  });

  testWidgets('a proxy build shows its data and asks no city host',
      (tester) async {
    await http.runWithClient(() async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
          theme: buildTimbreTheme(),
          home: StopsPage(onOpenStopInComoIr: (_) {})));
      await tester.pump();
      await letHiveWrite(tester);

      // The warning above the stops, from /v1/status/gps
      expect(find.textContaining('Datos GPS parciales (CUTCSA 40 %)'),
          findsOneWidget);
      // The ten newest messages of /v1/news, none read yet
      expect(find.text('10'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('10 novedades sin leer')),
          findsOneWidget);
      // The board of the saved stop
      expect(find.text('117'), findsOneWidget);
      handle.dispose();

      // "Paradas cercanas" from the catalog, on the phone
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paradas cercanas'));
      await tester.pump();
      await letHiveWrite(tester);
      expect(inDialog(find.text('SAN JOSE y ANDES')), findsOneWidget);

      expect(
          requests.map((u) => u.path),
          containsAll([
            '/v1/status/gps',
            '/v1/news',
            '/v1/stops/574/arrivals',
            '/v1/catalog/stops',
          ]));
      expect(requests.where((u) => _cityHosts.contains(u.host)), isEmpty);
      expect(requests.map((u) => u.host).toSet(), {'proxy.test'});
      // Nor the position, in any form
      expect(requests.where((u) => u.hasQuery), isEmpty);
    }, () => client);
  });
}

class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  // 18 de Julio y Andes, about 90 m from stop 574
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
        latitude: -34.9066,
        longitude: -56.1985,
        timestamp: DateTime(2026, 10, 27),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
