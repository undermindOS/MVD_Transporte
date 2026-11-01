// The trip planner on the Mapa, with a planner that answers at once
// (TripService.planner) and a phone position given (locateForTrip): the
// engine itself is tested in test/rutas/. The only network is the live
// board of the stop where the first bus is taken.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/models/place.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/nearby_stops_service.dart';
import 'package:stm_app/services/places_service.dart';
import 'package:stm_app/services/rutas/itinerary.dart';
import 'package:stm_app/services/trip_service.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/map/trip_ui.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

final _now = DateTime(2026, 11, 2, 14, 0);
const _here = (lat: -34.9118, lon: -56.1530);
const _casa = (lat: -34.9067, lon: -56.2037);

RideStop _stop(
  int index,
  int id,
  String name,
  double lat,
  double lon,
  DateTime time,
) => RideStop(index: index, id: id, name: name, lat: lat, lon: lon, time: time);

/// Walk 5 min to 574, the 121 from 14:05 to 14:27, walk 4 min to Casa.
Itinerary _by121() {
  final board = _stop(
    0,
    574,
    'SAN JOSE y ANDES',
    -34.9100,
    -56.1560,
    DateTime(2026, 11, 2, 14, 5),
  );
  final alight = _stop(
    1,
    1234,
    'CIUDADELA y SARANDI',
    -34.9070,
    -56.2000,
    DateTime(2026, 11, 2, 14, 27),
  );
  return Itinerary(
    start: DateTime(2026, 11, 2, 14, 0),
    end: DateTime(2026, 11, 2, 14, 31),
    rides: 1,
    walkMetres: 700,
    walkMinutes: 9,
    legs: [
      WalkLeg(
        from: _here,
        to: (lat: board.lat, lon: board.lon),
        metres: 400,
        minutes: 5,
        start: DateTime(2026, 11, 2, 14, 0),
        end: DateTime(2026, 11, 2, 14, 5),
        toStop: 0,
        toStopId: 574,
      ),
      RideLeg(
        line: '121',
        variant: 7883,
        boardStop: board,
        alightStop: alight,
        stops: [board, alight],
      ),
      WalkLeg(
        from: (lat: alight.lat, lon: alight.lon),
        to: _casa,
        metres: 300,
        minutes: 4,
        start: DateTime(2026, 11, 2, 14, 27),
        end: DateTime(2026, 11, 2, 14, 31),
        fromStop: 1,
        fromStopId: 1234,
      ),
    ],
  );
}

void main() {
  late Directory hiveDir;
  final queries = <TripQuery>[];
  var answer = <Itinerary>[];
  Object? locateError;

  final client = MockClient((request) async {
    if (request.url.path == '/transporteRest/siguientesParada/574') {
      return http.Response(
        '[{"linea":"121","destino":"PUNTA CARRETAS","minutos":3,'
        '"real":true,"idBus":111,"idEmpresa":50,"horaDesc":"14:03",'
        '"coordinates":[-56.1570,-34.9105]}]',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('[]', 200);
  });

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_trip_ui');
    await CacheService.init(path: hiveDir.path);
    TripService.planner = (query) async {
      queries.add(query);
      return (options: answer, sourceDate: DateTime(2026, 10, 31));
    };
    locateForTrip = () async {
      if (locateError case final error?) throw error;
      return _here;
    };
  });

  // Not Hive.close: see test/map/mapa_places_test.dart
  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    queries.clear();
    answer = [_by121()];
    locateError = null;
    MvdApiService.resetLatestBoards();
    // No await: the notifier is what the screen reads
    PlacesService.save(
      Place.at(PlaceKind.casa, lat: _casa.lat, lon: _casa.lon),
    );
    CacheService.remove(CacheService.keyWalkMinutes);
  });

  Future<void> open(WidgetTester tester) async {
    MapaPage.clock = () => _now;
    addTearDown(() => MapaPage.clock = DateTime.now);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimbreTheme(),
        home: Scaffold(
          body: MapaPage(
            basemapLoader: () async => MapaBasemap(
              bounds: LatLngBounds(
                const LatLng(-34.97, -56.80),
                const LatLng(-34.50, -55.70),
              ),
              attribution: '© OpenStreetMap',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Casa: from the phone, leaving now, the 121; picked, it is '
      'drawn and its first bus comes with GPS', (tester) async {
    await http.runWithClient(() async {
      await open(tester);
      await tester.tap(find.text('Casa'));
      await tester.pumpAndSettle();

      expect(find.text('Cómo llegar a Casa'), findsOneWidget);
      expect(queries.single.from, _here);
      expect(queries.single.to, _casa);
      expect(queries.single.departAt, _now);
      expect(queries.single.maxWalkMinutes, 10);
      expect(find.text('14:00 → 14:31'), findsOneWidget);
      expect(find.text('31 min'), findsOneWidget);
      expect(find.text('Caminás 700 m · 1 ómnibus'), findsOneWidget);

      await tester.tap(find.text('14:00 → 14:31'));
      await tester.pumpAndSettle();
      expect(find.text('A Casa'), findsOneWidget);
      expect(find.text('Sale 14:05 · llegás 14:31'), findsOneWidget);
      final lines = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines;
      expect(lines, hasLength(3));

      await tester.tap(find.text('Pasos'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tomá el 121 a las 14:05 en la parada 574'),
        findsOneWidget,
      );
      expect(find.text('Con GPS: el 121 llega en 3 min.'), findsOneWidget);

      // Closed, the trip leaves the map
      Navigator.of(tester.element(find.text('Pasos'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cerrar el viaje'));
      await tester.pumpAndSettle();
      expect(find.byType(PolylineLayer), findsNothing);
    }, () => client);
  });

  testWidgets('15 min of walking asks again and is remembered', (tester) async {
    await open(tester);
    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();
    expect(queries.map((q) => q.maxWalkMinutes), [10, 15]);
    expect(PlacesService.walkMinutes, 15);
  });

  testWidgets('no trip: says so and how to widen it', (tester) async {
    answer = [];
    await open(tester);
    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No hay un viaje en ómnibus caminando hasta 10 min'),
      findsOneWidget,
    );
  });

  testWidgets('no location permission: asks to start from a place', (
    tester,
  ) async {
    locateError = const NearbyStopsException(NearbyStopsError.permissionDenied);
    PlacesService.save(Place.at(PlaceKind.trabajo, lat: -34.88, lon: -56.15));
    await open(tester);
    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin permiso de ubicación'), findsOneWidget);
    expect(queries, isEmpty);

    // From Trabajo instead
    await tester.tap(find.text('Tu ubicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trabajo').last);
    await tester.pumpAndSettle();
    expect(queries.single.from, (lat: -34.88, lon: -56.15));
    expect(find.text('14:00 → 14:31'), findsOneWidget);
  });
}
