// The Mapa with real fonts on a phone screen at 1x, 1.3x and 2x: the empty
// sign, the notes over the map, the failed-refresh banner, the basemap
// error and both sheets keep every word. Any overflow fails the test. The
// basemap has no tiles (see mapa_page_test.dart).

import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

import '../support/layout.dart';

// A GPS bus on its way to 574, a block away, and one by timetable
const _arrivals574 =
    '['
    '{"linea":"121","destino":"PUNTA CARRETAS","minutos":4,'
    '"real":true,"idBus":111,"idEmpresa":50,"horaDesc":"8:56",'
    '"coordinates":[-56.1990,-34.9085]},'
    '{"linea":"144","destino":"CEMENTERIO DEL NORTE","minutos":20,'
    '"real":false,"horaDesc":"9:12"}]';

const _noGps =
    '[{"linea":"144","destino":"CEMENTERIO DEL NORTE",'
    '"minutos":20,"real":false,"horaDesc":"9:12"}]';

// A block from the stop: in sight with the camera on it
const _bus = LatLng(-34.9085, -56.1990);

BusStop _stop574() => BusStop(
  id: 574,
  name: 'SAN JOSE y ANDES',
  latitude: -34.90739436,
  longitude: -56.198255,
);

void main() {
  late Directory hiveDir;
  late String wfsNone;
  var failing = false;
  var body574 = _arrivals574;
  Object? loadError;

  final client = MockClient((request) async {
    if (failing) return http.Response('', 500);
    if (request.url.host == 'geoserver.montevideo.gub.uy') {
      return http.Response(
        wfsNone,
        200,
        headers: {'content-type': 'application/json;charset=UTF-8'},
      );
    }
    if (request.url.path == '/transporteRest/siguientesParada/574') {
      return http.Response(
        body574,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('[]', 200);
  });

  Future<MapaBasemap> basemap() async {
    if (loadError case final error?) throw error;
    return MapaBasemap(
      bounds: LatLngBounds(
        const LatLng(-34.97, -56.80),
        const LatLng(-34.50, -55.70),
      ),
      attribution: '© OpenStreetMap',
    );
  }

  setUpAll(() async {
    await loadBundledFonts();
    hiveDir = await Directory.systemTemp.createTemp('mvd_mapa_layout');
    await CacheService.init(path: hiveDir.path);
    wfsNone = File('test/fixtures/wfs_parada_9999999.json').readAsStringSync();
  });

  setUp(() {
    failing = false;
    body574 = _arrivals574;
    loadError = null;
    MvdApiService.resetLatestBoards();
    StopLocationsService.reset();
  });

  tearDown(() {
    MvdApiService.resetBusy();
    MvdApiService.resetLatestBoards();
    StopLocationsService.reset();
    MapaPage.clock = DateTime.now;
    for (final stop in CacheService.getAllStops()) {
      CacheService.deleteStop(stop.id);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpMapa(
    WidgetTester tester,
    double scale, {
    List<BusStop> stops = const [],
  }) async {
    usePhoneScreen(tester);
    // Not awaited (see mapa_page_test.dart): let the IO finish
    for (final stop in stops) {
      CacheService.saveStop(stop);
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimbreTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: MapaPage(basemapLoader: basemap)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void whole(WidgetTester tester, Finder text, double scale) {
    expect(text, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
      isFalse,
      reason: '$text at ${scale}x',
    );
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Text at ${scale}x: the empty sign fits', (tester) async {
      await http.runWithClient(() async {
        await pumpMapa(tester, scale);
        whole(tester, find.text('SIN PARADAS'), scale);
        whole(
          tester,
          find.textContaining('Agregá una parada en Mis paradas'),
          scale,
        );
      }, () => client);
    });

    testWidgets('Text at ${scale}x: the notes over the map fit', (
      tester,
    ) async {
      body574 = _noGps;
      await http.runWithClient(() async {
        await pumpMapa(
          tester,
          scale,
          stops: [
            _stop574(),
            BusStop(id: 9999998, name: 'Parada 9999998'),
            BusStop(id: 9999999, name: 'Parada 9999999'),
          ],
        );
        await tester.pump();
        whole(
          tester,
          find.text('Ahora ningún ómnibus con GPS viene a tus paradas.'),
          scale,
        );
        whole(
          tester,
          find.text('No se pudieron ubicar en el mapa 2 paradas.'),
          scale,
        );
        whole(tester, find.text('© OpenStreetMap'), scale);
      }, () => client);
    });

    testWidgets('Text at ${scale}x: the failed refresh banner fits', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await pumpMapa(tester, scale, stops: [_stop574()]);
        failing = true;
        await tester.pump(StopsPage.autoRefreshInterval);
        await tester.pump();
        whole(
          tester,
          find.text('No se pudo actualizar. Revisá la conexión.'),
          scale,
        );
        whole(tester, find.text('Reintentar'), scale);
      }, () => client);
    });

    testWidgets('Text at ${scale}x: the basemap error fits', (tester) async {
      loadError = StateError('no basemap');
      await http.runWithClient(() async {
        await pumpMapa(tester, scale, stops: [_stop574()]);
        whole(
          tester,
          find.text('No se pudo abrir el mapa. Probá de nuevo.'),
          scale,
        );
        whole(tester, find.text('Reintentar'), scale);
      }, () => client);
    });

    testWidgets('Text at ${scale}x: the stop sheet fits', (tester) async {
      await http.runWithClient(() async {
        await pumpMapa(tester, scale, stops: [_stop574()]);
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Parada 574')));
        await tester.pumpAndSettle();
        whole(
          tester,
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('SAN JOSE y ANDES'),
          ),
          scale,
        );
        for (final d in ['PUNTA CARRETAS', 'CEMENTERIO DEL NORTE']) {
          whole(tester, find.text(d), scale);
        }
      }, () => client);
    });

    testWidgets('Text at ${scale}x: the bus sheet fits', (tester) async {
      await http.runWithClient(() async {
        await pumpMapa(tester, scale, stops: [_stop574()]);
        final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final at = map.mapController!.camera.latLngToScreenOffset(_bus);
        await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) + at);
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        whole(
          tester,
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('PUNTA CARRETAS'),
          ),
          scale,
        );
        whole(tester, find.text('a la parada 574 · SAN JOSE y ANDES'), scale);
      }, () => client);
    });
  }
}
