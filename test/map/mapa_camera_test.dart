// The Mapa's camera when saved stops get placed one lookup at a time: the
// map can open with only some of them, and the others must not be left
// off-screen. A file of its own because the test awaits the Hive write of
// the location StopLocationsService finds, which only the first test of a
// file can do (see test/stop_search_test.dart).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/stop_locations_service.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

void main() {
  late Directory hiveDir;
  late String wfs574;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_mapa_camera_test');
    await CacheService.init(path: hiveDir.path);
    wfs574 = File('test/fixtures/wfs_parada_574.json').readAsStringSync();
  });

  tearDownAll(() async {
    MvdApiService.resetLatestBoards();
    StopLocationsService.reset();
    await hiveDir.delete(recursive: true);
  });

  testWidgets('a stop placed after the map opened is brought into view', (
    tester,
  ) async {
    // 3140 is already placed; 574, about 6 km away, still has to be looked up
    await tester.runAsync(() async {
      await CacheService.saveStop(
        BusStop(
          id: 3140,
          name: 'AV RAMON ANADOR y TIBURCIO GOMEZ',
          latitude: -34.8835,
          longitude: -56.1420,
        ),
      );
      await CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
    });

    // Geoserver answers only once the map is on screen, as on a phone
    final answer = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.host == 'geoserver.montevideo.gub.uy') {
        await answer.future;
        return http.Response(
          wfs574,
          200,
          headers: {'content-type': 'application/json;charset=UTF-8'},
        );
      }
      return http.Response('[]', 200);
    });

    await http.runWithClient(() async {
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
      expect(find.byType(FlutterMap), findsOneWidget);
      answer.complete();
      // The WFS answer is saved for real
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }, () => client);

    final placed = CacheService.getStop(574)!;
    expect(placed.hasLocation, isTrue);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final view = map.mapController!.camera.visibleBounds;
    expect(view.contains(LatLng(placed.latitude, placed.longitude)), isTrue);
    expect(view.contains(const LatLng(-34.8835, -56.1420)), isTrue);
  });
}
