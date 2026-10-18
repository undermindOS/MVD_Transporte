// "Mis paradas": adding a stop from "Paradas cercanas" and the
// "Ver en Cómo Ir" button. Location and HTTP are faked; the WFS answer is
// the live capture in test/fixtures.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/ui/stops_page.dart';

const _lineas574 =
    '{"descripcion":"SAN JOSE y ANDES","lineas":[{"descripcion":"116","codigo":38},'
    '{"descripcion":"117","codigo":39},{"descripcion":"121","codigo":40}]}';

void main() {
  late Directory hiveDir;
  late String wfsBody;
  late _FakeGeolocator geolocator;
  final requests = <Uri>[];
  final opened = <int>[];

  final client = MockClient((request) async {
    requests.add(request.url);
    if (request.url.host == 'geoserver.montevideo.gub.uy') {
      return http.Response(wfsBody, 200,
          headers: {'content-type': 'application/json;charset=UTF-8'});
    }
    if (request.url.path == '/transporteRest/lineas/574') {
      return http.Response(_lineas574, 200);
    }
    return http.Response('[]', 200); // siguientesParada: no buses
  });

  Widget app() => MaterialApp(
      home: StopsPage(onOpenStopInComoIr: opened.add));

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_stops_test');
    await CacheService.init(path: hiveDir.path);
    wfsBody =
        File('test/fixtures/wfs_paradas_18_de_julio.json').readAsStringSync();
  });

  setUp(() {
    geolocator = _FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;
    requests.clear();
    opened.clear();
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('Paradas cercanas lists nearby stops and saves the picked one',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Agregar parada'), findsWidgets);
      // Location is asked only when the user taps the button
      expect(geolocator.permissionRequested, isFalse);

      await tester.tap(find.text('Paradas cercanas'));
      await tester.pumpAndSettle();

      expect(geolocator.permissionRequested, isTrue);
      final wfs = requests.singleWhere(
          (u) => u.host == 'geoserver.montevideo.gub.uy');
      expect(wfs.queryParameters['bbox'], startsWith('-56.'));

      // Nearest first, with stop number, distance and lines
      expect(find.text('ANDES y AV 18 DE JULIO'), findsOneWidget);
      expect(find.textContaining('#5109 · 48 m · 124, 124 SD, 125'),
          findsOneWidget);
      expect(find.text('SAN JOSE y ANDES'), findsOneWidget);

      await tester.tap(find.text('SAN JOSE y ANDES'));
      await tester.pumpAndSettle();
      // Hive writes to disk for real: let saveStop finish outside fake async
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Saved through resolveStop (transporteRest/lineas)
      expect(requests.map((u) => u.path),
          contains('/transporteRest/lineas/574'));
      final saved = CacheService.getStop(574);
      expect(saved, isNotNull);
      expect(saved!.name, 'SAN JOSE y ANDES');
      expect(saved.lines, ['116', '117', '121']);
      expect(find.text('#574'), findsOneWidget);
    }, () => client);
  });

  testWidgets('Ver en Cómo Ir hands the stop number to the Cómo Ir tab',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();

      await tester.tap(find.text('Ver en Cómo Ir'));
      expect(opened, [574]);
    }, () => client);
  });

  testWidgets('Arrival times refresh every 30 s and on return to the app',
      (tester) async {
    var minutes = 7;
    final etaRequests = <Uri>[];
    final etaClient = MockClient((request) async {
      if (request.url.path == '/transporteRest/siguientesParada/574') {
        etaRequests.add(request.url);
        return http.Response(
            '[{"linea":"116","destino":"POCITOS","minutos":$minutes,'
            '"real":true,"idEmpresa":50,"horaDesc":"8:00"}]',
            200);
      }
      return http.Response('[]', 200);
    });
    // Hive writes to disk for real: start in the test zone (awaiting it
    // inside runAsync hangs after a test that used Hive), let the IO finish
    CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    void lifecycle(List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('7 min'), findsOneWidget);
      final initial = etaRequests.length;

      minutes = 6;
      await tester.pump(
          StopsPage.autoRefreshInterval - const Duration(seconds: 1));
      expect(etaRequests.length, initial);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(etaRequests.length, initial + 1);
      expect(find.text('6 min'), findsOneWidget);

      // A system dialog (inactive) keeps the timer, no extra request
      lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      await tester.pump();
      expect(etaRequests.length, initial + 1);

      // Nothing is requested in the background
      lifecycle([
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      minutes = 3;
      await tester.pump(const Duration(minutes: 5));
      expect(etaRequests.length, initial + 1);

      // Back in the foreground: refreshed at once, then every 30 s again
      lifecycle([
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump();
      expect(etaRequests.length, initial + 2);
      expect(find.text('3 min'), findsOneWidget);
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(etaRequests.length, initial + 3);
    }, () => etaClient);
  });

  testWidgets('Denied location explains how to enable it', (tester) async {
    geolocator.answer = LocationPermission.deniedForever;
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paradas cercanas'));
      await tester.pumpAndSettle();

      expect(find.text('El permiso de ubicación está desactivado para la app.'),
          findsOneWidget);
      expect(find.text('Abrir ajustes'), findsOneWidget);
      expect(requests.where((u) => u.host == 'geoserver.montevideo.gub.uy'),
          isEmpty);
    }, () => client);
  });
}

class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission _permission = LocationPermission.denied;
  LocationPermission answer = LocationPermission.whileInUse;
  bool permissionRequested = false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => _permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequested = true;
    return _permission = answer;
  }

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
        latitude: -34.9066,
        longitude: -56.1985,
        timestamp: DateTime(2026, 10, 17),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
