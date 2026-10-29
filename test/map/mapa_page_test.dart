// The Mapa tab with a basemap that has no tiles (MapaBasemap without a
// layer): no archive copy, no tile decoding, no worker isolate in the
// fake-async zone. The network is a MockClient: transporteRest in direct
// mode, the /v1 goldens in proxy mode. Stops are saved with their
// coordinates. Old minutes must never look live: not on the map, not in a
// sheet, not in what a screen reader hears.
//
// Only the first test awaits a Hive write (StopLocationsService saves the
// location it finds): only the first test of a file can (see
// test/stop_search_test.dart). The others save without awaiting and let
// the IO finish in runAsync.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/stop_locations_service.dart';
import 'package:stm_app/ui/map/bus_layer.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/arrival_row.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/line_badge.dart';

// Stop 574 where the city has it; 3140 near its fixture bus
BusStop _stop574() => BusStop(
  id: 574,
  name: 'SAN JOSE y ANDES',
  latitude: -34.90739436,
  longitude: -56.198255,
);
BusStop _stop3140() => BusStop(
  id: 3140,
  name: 'AV RAMON ANADOR y TIBURCIO GOMEZ',
  latitude: -34.8835,
  longitude: -56.1420,
);

// Bus 678 of CUTCSA (line 145) is in the 3140 fixture; here it also
// approaches 574, and 111 (line 121) goes to 574 only
const _arrivals574 =
    '['
    '{"linea":"145","destino":"BV ARTIGAS Y BV ESPAÑA","minutos":12,'
    '"real":true,"idBus":678,"idEmpresa":50,"horaDesc":"9:04",'
    '"coordinates":[-56.1465,-34.88043]},'
    '{"linea":"121","destino":"PUNTA CARRETAS","minutos":4,'
    '"real":true,"idBus":111,"idEmpresa":50,"horaDesc":"8:56",'
    '"coordinates":[-56.2078,-34.9094]},'
    '{"linea":"144","destino":"CEMENTERIO DEL NORTE","minutos":20,'
    '"real":false,"horaDesc":"9:12"}]';

// The next board of 574: bus 678 has passed it
const _after678 =
    '['
    '{"linea":"121","destino":"PUNTA CARRETAS","minutos":3,'
    '"real":true,"idBus":111,"idEmpresa":50,"horaDesc":"8:56",'
    '"coordinates":[-56.2070,-34.9090]},'
    '{"linea":"144","destino":"CEMENTERIO DEL NORTE","minutos":19,'
    '"real":false,"horaDesc":"9:12"}]';

// Timetable only: no position to draw
const _noGps =
    '[{"linea":"144","destino":"CEMENTERIO DEL NORTE",'
    '"minutos":20,"real":false,"horaDesc":"9:12"}]';

final _bounds = LatLngBounds(
  const LatLng(-34.97, -56.80),
  const LatLng(-34.50, -55.70),
);

void main() {
  late Directory hiveDir;
  late String arrivals3140;
  late String wfs574;
  late String wfsNone;
  late _FakeBrowser browser;
  final requests = <Uri>[];
  // The next refreshes fail: all, or those of these stops
  var failing = false;
  var failingStops = <int>{};
  // siguientesParada bodies by stop
  var bodies = <int, String>{};
  // The phone's clock (MapaPage.clock, and MvdApiService.clock that stamps
  // when a board arrives) is real time moved by this much
  var later = Duration.zero;

  // The basemap: loads and closes counted, failing on demand, or held
  var loads = 0;
  var disposed = 0;
  Object? loadError;
  Completer<void>? held;
  Future<MapaBasemap> basemap() async {
    loads++;
    await held?.future;
    if (loadError case final error?) throw error;
    return MapaBasemap(
      bounds: _bounds,
      attribution: '© OpenStreetMap',
      onDispose: () => disposed++,
    );
  }

  final client = MockClient((request) async {
    requests.add(request.url);
    if (failing) return http.Response('', 500);
    final path = request.url.path;
    if (request.url.host == 'geoserver.montevideo.gub.uy') {
      final id = request.url.queryParameters['CQL_FILTER'];
      return http.Response(
        id == 'cod_ubic_parada=574' ? wfs574 : wfsNone,
        200,
        headers: {'content-type': 'application/json;charset=UTF-8'},
      );
    }
    const prefix = '/transporteRest/siguientesParada/';
    if (path.startsWith(prefix)) {
      final id = int.parse(path.substring(prefix.length));
      if (failingStops.contains(id)) return http.Response('', 500);
      final body = bodies[id] ?? (id == 3140 ? arrivals3140 : '[]');
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('[]', 200);
  });

  int arrivalRequests() => requests
      .where((u) => u.path.startsWith('/transporteRest/siguientesParada/'))
      .length;

  /// [bottomInset]: a phone's home indicator.
  Widget app({bool active = true, double bottomInset = 0}) => MaterialApp(
    theme: buildTimbreTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
      child: child!,
    ),
    home: Scaffold(
      body: MapaPage(active: active, basemapLoader: basemap),
    ),
  );

  /// Saved without awaiting (see the header), then the IO finishes.
  Future<void> save(WidgetTester tester, List<BusStop> stops) async {
    for (final stop in stops) {
      CacheService.saveStop(stop);
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }

  /// The page, its basemap and boards, then the map fitted to the stops:
  /// FlutterMap fits the camera once it has a size, and lays the markers
  /// out on the frame after.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
  }

  BusLayer busLayer(WidgetTester tester) =>
      tester.widget<BusLayer>(find.byType(BusLayer));

  /// Taps the map where a bus is drawn and waits for its sheet.
  Future<void> tapBus(WidgetTester tester, LatLng at) async {
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final offset = map.mapController!.camera.latLngToScreenOffset(at);
    await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) + offset);
    // The map tells a tap from a double tap (zoom) first
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
  }

  /// Every label a screen reader can reach.
  List<String> labels() => [
    for (final node
        in find.semantics
            .byPredicate((node) => node.label.isNotEmpty)
            .evaluate())
      node.label,
  ];

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_mapa_test');
    await CacheService.init(path: hiveDir.path);
    arrivals3140 = File(
      'test/fixtures/siguientes_parada_3140.json',
    ).readAsStringSync();
    wfs574 = File('test/fixtures/wfs_parada_574.json').readAsStringSync();
    wfsNone = File('test/fixtures/wfs_parada_9999999.json').readAsStringSync();
  });

  setUp(() {
    browser = _FakeBrowser();
    UrlLauncherPlatform.instance = browser;
    requests.clear();
    failing = false;
    failingStops = {};
    bodies = {574: _arrivals574};
    later = Duration.zero;
    MapaPage.clock = () => DateTime.now().add(later);
    MvdApiService.clock = MapaPage.clock;
    loads = 0;
    disposed = 0;
    loadError = null;
    held = null;
    MvdApiService.resetLatestBoards();
    StopLocationsService.reset();
  });

  tearDown(() async {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
    MvdApiService.resetLatestBoards();
    StopLocationsService.reset();
    MapaPage.clock = DateTime.now;
    MvdApiService.clock = DateTime.now;
    for (final stop in CacheService.getAllStops()) {
      CacheService.deleteStop(stop.id);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('a stop saved with no location is placed once the city has it', (
    tester,
  ) async {
    // The first test: it can await the Hive write (see the header)
    await tester.runAsync(
      () => CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES')),
    );
    final handle = tester.ensureSemantics();

    await http.runWithClient(() async {
      await open(tester);
      // The WFS answer is saved for real
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      // Placed, the camera goes there, the marker follows
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final wfs = requests.singleWhere(
        (u) => u.host == 'geoserver.montevideo.gub.uy',
      );
      expect(wfs.queryParameters['CQL_FILTER'], 'cod_ubic_parada=574');
      expect(CacheService.getStop(574)!.hasLocation, isTrue);
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, 2 ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('No se pudo ubicar'), findsNothing);
    }, () => client);
    handle.dispose();
  });

  testWidgets('without saved stops: the empty sign, no basemap, no request', (
    tester,
  ) async {
    await http.runWithClient(() async {
      final handle = tester.ensureSemantics();
      await open(tester);

      expect(find.text('SIN PARADAS'), findsOneWidget);
      expect(find.bySemanticsLabel('Sin paradas guardadas'), findsOneWidget);
      expect(
        find.text(
          'Agregá una parada en Mis paradas para ver acá los '
          'ómnibus con GPS que se acercan.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsNothing);
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(loads, 0);
      expect(requests, isEmpty);
      handle.dispose();
    }, () => client);
  });

  testWidgets('the saved stops are markers with one phrase each, the GPS '
      'buses are drawn, one per bus', (tester) async {
    await save(tester, [_stop574(), _stop3140()]);
    final handle = tester.ensureSemantics();

    await http.runWithClient(() async {
      await open(tester);

      expect(loads, 1);
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, 2 ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Parada 3140, Av Ramon Anador y Tiburcio '
          'Gomez, 1 ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );
      // Bus 678 is on both boards: drawn once
      final buses = busLayer(tester).handle.drawn;
      expect(
        buses.map((b) => b.key),
        unorderedEquals(['bus-50-678', 'bus-50-111']),
      );
      expect(buses.every((b) => b.live), isTrue);
      // The buses are paint only: the markers say it all
      expect(
        labels(),
        unorderedEquals([
          'Parada 574, San Jose y Andes, 2 ómnibus con GPS en camino',
          'Parada 3140, Av Ramon Anador y Tiburcio '
              'Gomez, 1 ómnibus con GPS en camino',
          '© OpenStreetMap',
        ]),
      );
      final shared = buses.singleWhere((b) => b.key == 'bus-50-678');
      expect(shared.etas.map((e) => (e.stopId, e.etaMinutes)), [
        (3140, 7),
        (574, 12),
      ]);
      // No location sent anywhere, no stop looked up
      expect(
        requests.where((u) => u.host == 'geoserver.montevideo.gub.uy'),
        isEmpty,
      );
      expect(find.textContaining('ningún ómnibus'), findsNothing);
    }, () => client);
    handle.dispose();
  });

  testWidgets('tapping a stop opens its arrivals', (tester) async {
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      await open(tester);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Parada 574')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('#574'), findsOneWidget);
      final rows = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ArrivalRow),
      );
      expect(rows, findsNWidgets(3));
      expect(
        find.descendant(of: rows.first, matching: find.text('121')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byWidgetPredicate(
            (w) => w is MinutosEnVivo && w.minutes == 4,
          ),
        ),
        findsOneWidget,
      );
    }, () => client);
  });

  testWidgets('tapping a bus opens it with the minutes to each saved stop', (
    tester,
  ) async {
    await save(tester, [_stop574(), _stop3140()]);
    await http.runWithClient(() async {
      await open(tester);

      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final camera = map.mapController!.camera;
      final at = camera.latLngToScreenOffset(const LatLng(-34.88043, -56.1465));
      await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) + at);
      // The map tells a tap from a double tap (zoom) first
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final badge = tester.widget<LineBadge>(
        find.descendant(of: sheet, matching: find.byType(LineBadge)),
      );
      expect((badge.line, badge.live), ('145', true));
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('BV ARTIGAS Y BV ESPAÑA'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('a la parada 3140 · AV RAMON ANADOR y TIBURCIO GOMEZ'),
        findsOneWidget,
      );
      expect(find.text('a la parada 574 · SAN JOSE y ANDES'), findsOneWidget);
      for (final minutes in [7, 12]) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.byWidgetPredicate(
              (w) => w is MinutosEnVivo && w.minutes == minutes,
            ),
          ),
          findsOneWidget,
        );
      }
    }, () => client);
  });

  testWidgets('polls every 30 s only while active', (tester) async {
    await save(tester, [_stop574(), _stop3140()]);
    await http.runWithClient(() async {
      await open(tester);
      expect(arrivalRequests(), 2);
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), 4);

      await tester.pumpWidget(app(active: false));
      // Off screen the buses jump, with no ticker
      expect(busLayer(tester).animate, isFalse);
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(arrivalRequests(), 4);

      // Back on screen half a minute later: refreshed at once
      later = StopsPage.autoRefreshInterval;
      await open(tester);
      expect(busLayer(tester).animate, isTrue);
      expect(arrivalRequests(), 6);
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), 8);

      // In the background: nothing; back: after the next frame
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(arrivalRequests(), 8);
      later = StopsPage.autoRefreshInterval * 5;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pump();
      expect(arrivalRequests(), 10);
    }, () => client);
  });

  testWidgets('right after Mis paradas refreshed, the boards are not asked '
      'again', (tester) async {
    await save(tester, [_stop574(), _stop3140()]);
    await http.runWithClient(() async {
      // Mis paradas fetched them a moment ago
      await MvdApiService.getBoards([574, 3140]);
      expect(arrivalRequests(), 2);

      await open(tester);
      expect(arrivalRequests(), 2);
      // Drawn at once, from those boards
      expect(busLayer(tester).buses, hasLength(2));
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), 4);
    }, () => client);
  });

  testWidgets('boards half a minute old are asked again', (tester) async {
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      await MvdApiService.getBoards([574]);
      later = StopsPage.autoRefreshInterval;
      await open(tester);
      expect(arrivalRequests(), 2);
    }, () => client);
  });

  testWidgets('a failed refresh: the banner, the last buses unlit, then gone', (
    tester,
  ) async {
    await save(tester, [_stop574()]);
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      await open(tester);
      expect(busLayer(tester).buses, hasLength(2));
      expect(busLayer(tester).buses.every((b) => b.live), isTrue);
      expect(find.text('Reintentar'), findsNothing);

      failing = true;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(
        find.text('No se pudo actualizar. Revisá la conexión.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      final stale = busLayer(tester).buses;
      expect(stale, hasLength(2));
      expect(stale.any((b) => b.live), isFalse);
      // Heard as estimates too, not as GPS buses on their way
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, 2 ómnibus en camino, estimado',
        ),
        findsOneWidget,
      );

      // Five minutes after their board: gone
      later = const Duration(minutes: 5);
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(busLayer(tester).buses, isEmpty);
      expect(
        find.text('No se pudo actualizar. Revisá la conexión.'),
        findsOneWidget,
      );
      // Not "no buses are coming": that is unknown
      expect(find.textContaining('ningún ómnibus'), findsNothing);
      expect(
        find.bySemanticsLabel('Parada 574, San Jose y Andes'),
        findsOneWidget,
      );

      // Back online, with a board fetched now
      failing = false;
      later = Duration.zero;
      final asked = arrivalRequests();
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(arrivalRequests(), asked + 1);
      expect(find.text('Reintentar'), findsNothing);
      expect(busLayer(tester).buses, hasLength(2));
      expect(busLayer(tester).buses.every((b) => b.live), isTrue);
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, 2 ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );
    }, () => client);
    handle.dispose();
  });

  testWidgets('one stop failed: its buses and minutes are estimates, the '
      'other stop stays lit', (tester) async {
    await save(tester, [_stop574(), _stop3140()]);
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      await open(tester);
      failingStops = {574};
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      // The other stop answered: no banner
      expect(find.text('Reintentar'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, 2 ómnibus en camino, estimado',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Parada 3140, Av Ramon Anador y Tiburcio '
          'Gomez, 1 ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );

      // Bus 678 is on both boards: its 574 minutes are old
      await tapBus(tester, const LatLng(-34.88043, -56.1465));
      final sheet = find.byType(BottomSheet);
      final badge = tester.widget<LineBadge>(
        find.descendant(of: sheet, matching: find.byType(LineBadge)),
      );
      expect((badge.line, badge.live), ('145', true));
      final lit = tester.widgetList<MinutosEnVivo>(
        find.descendant(of: sheet, matching: find.byType(MinutosEnVivo)),
      );
      expect(lit.map((w) => w.minutes), [7]);
      expect(
        find.descendant(of: sheet, matching: find.text('~9:04')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'A la parada 574, San Jose y Andes, alrededor de las 9:04, '
          'estimado',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'A la parada 3140, Av Ramon Anador y Tiburcio Gomez, llega en 7 '
          'minutos, con GPS',
        ),
        findsOneWidget,
      );
    }, () => client);
    handle.dispose();
  });

  testWidgets('a bus no board has any more: its open sheet turns to an '
      'estimate', (tester) async {
    await save(tester, [_stop574(), _stop3140()]);
    await http.runWithClient(() async {
      await open(tester);
      await tapBus(tester, const LatLng(-34.88043, -56.1465));
      final sheet = find.byType(BottomSheet);
      Finder lit() =>
          find.descendant(of: sheet, matching: find.byType(MinutosEnVivo));
      expect(lit(), findsNWidgets(2));

      // It passed both stops
      bodies = {574: _after678, 3140: '[]'};
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(busLayer(tester).buses.map((b) => b.key), ['bus-50-111']);
      final badge = tester.widget<LineBadge>(
        find.descendant(of: sheet, matching: find.byType(LineBadge)),
      );
      expect((badge.line, badge.live), ('145', false));
      expect(lit(), findsNothing);
      for (final time in ['~8:59', '~9:04']) {
        expect(
          find.descendant(of: sheet, matching: find.text(time)),
          findsOneWidget,
        );
      }
    }, () => client);
  });

  testWidgets('busy: nothing to say, the ticks wait', (tester) async {
    MvdApiService.proxyUrl = 'https://proxy.test';
    await save(tester, [_stop574()]);
    final busy = MockClient((request) async {
      requests.add(request.url);
      return http.Response(
        '{"error":"rate_limited"}',
        429,
        headers: {'retry-after': '120'},
      );
    });
    await http.runWithClient(() async {
      await open(tester);
      final asked = requests.length;
      // Only the page's own wait holds the ticks now
      MvdApiService.resetBusy();
      await tester.pump(StopsPage.autoRefreshInterval * 3);
      expect(requests, hasLength(asked));
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('No se pudo'), findsNothing);
      expect(find.textContaining('ningún ómnibus'), findsNothing);
    }, () => busy);
  });

  testWidgets('no GPS bus on the way: a note over the map', (tester) async {
    bodies = {574: _noGps};
    await save(tester, [_stop574()]);
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      await open(tester);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
        find.text('Ahora ningún ómnibus con GPS viene a tus paradas.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Parada 574, San Jose y Andes, sin ómnibus con GPS en camino',
        ),
        findsOneWidget,
      );
    }, () => client);
    handle.dispose();
  });

  testWidgets('stops the city does not place: a short note', (tester) async {
    await save(tester, [
      _stop574(),
      BusStop(id: 9999999, name: 'Parada 9999999'),
    ]);
    await http.runWithClient(() async {
      await open(tester);
      await tester.pump();
      expect(
        find.text('No se pudo ubicar en el mapa la parada 9999999.'),
        findsOneWidget,
      );
    }, () => client);
  });

  testWidgets('a stop saved meanwhile is not called unplaced before it is '
      'looked up', (tester) async {
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      await open(tester);
      await tester.pumpWidget(app(active: false));
      // Saved in Mis paradas, with no location
      await save(tester, [BusStop(id: 9999999, name: 'Parada 9999999')]);

      later = StopsPage.autoRefreshInterval;
      await tester.pumpWidget(app());
      expect(find.textContaining('No se pudo ubicar'), findsNothing);
      await tester.pump();
      await tester.pump();
      expect(
        find.text('No se pudo ubicar en el mapa la parada 9999999.'),
        findsOneWidget,
      );
    }, () => client);
  });

  testWidgets('two stops the city does not place: one note', (tester) async {
    await save(tester, [
      BusStop(id: 9999998, name: 'Parada 9999998'),
      BusStop(id: 9999999, name: 'Parada 9999999'),
    ]);
    await http.runWithClient(() async {
      await open(tester);
      await tester.pump();
      expect(
        find.text('No se pudieron ubicar en el mapa 2 paradas.'),
        findsOneWidget,
      );
      // Nothing on the map: the camera stays on centro
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center, MapaPage.centro);
    }, () => client);
  });

  testWidgets('the basemap failed: a note, never the error, and Reintentar', (
    tester,
  ) async {
    await save(tester, [_stop574()]);
    loadError = const FileSystemException('No space left', '/private/x');
    await http.runWithClient(() async {
      await open(tester);
      expect(
        find.text('No se pudo abrir el mapa. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.textContaining('space'), findsNothing);
      expect(find.textContaining('/private'), findsNothing);
      expect(find.byType(FlutterMap), findsNothing);

      // Off screen and back: no new load by itself
      await tester.pumpWidget(app(active: false));
      later = StopsPage.autoRefreshInterval;
      await open(tester);
      expect(loads, 1);

      loadError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(loads, 2);
      expect(find.byType(FlutterMap), findsOneWidget);
    }, () => client);
  });

  testWidgets('one basemap load at a time, closed with the page', (
    tester,
  ) async {
    await save(tester, [_stop574()]);
    held = Completer<void>();
    await http.runWithClient(() async {
      await open(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(app(active: false));
      later = StopsPage.autoRefreshInterval;
      await open(tester);
      expect(loads, 1);
      held!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(disposed, 0);

      await tester.pumpWidget(const SizedBox());
      expect(disposed, 1);
    }, () => client);
  });

  testWidgets('the attribution is in sight, in the safe area, and opens the '
      'copyright page', (tester) async {
    await save(tester, [_stop574()]);
    final handle = tester.ensureSemantics();
    await http.runWithClient(() async {
      // A phone with a home indicator
      await tester.pumpWidget(app(bottomInset: 34));
      await tester.pump();
      await tester.pump();

      final label = find.text('© OpenStreetMap');
      expect(label, findsOneWidget);
      // Bottom left, inside the map, above the home indicator
      final map = tester.getRect(find.byType(FlutterMap));
      final rect = tester.getRect(label);
      expect(map.contains(rect.bottomLeft - const Offset(-1, 1)), isTrue);
      expect(rect.left - map.left, lessThan(10));
      expect(map.bottom - rect.bottom, inInclusiveRange(34, 44));
      expect(
        tester.getSemantics(find.bySemanticsLabel('© OpenStreetMap')),
        isSemantics(isLink: true, hasTapAction: true),
      );

      await tester.tap(label);
      await tester.pump();
      expect(
        browser.launches.single,
        'https://www.openstreetmap.org/copyright',
      );
    }, () => client);
    handle.dispose();
  });

  testWidgets('through the proxy: the buses of the /v1 golden, no city host', (
    tester,
  ) async {
    MvdApiService.proxyUrl = 'https://proxy.test';
    final golden = File(
      'proxy/contract/v1/responses/arrivals_574.json',
    ).readAsBytesSync();
    // The golden's fetchedAt is days behind the phone's clock: the buses
    // are as old as their arrival on the phone, so they are lit
    final proxy = MockClient((request) async {
      requests.add(request.url);
      return request.url.path == '/v1/stops/574/arrivals'
          ? http.Response.bytes(
              golden,
              200,
              headers: {'content-type': 'application/json'},
            )
          : http.Response('{"error":"not_found"}', 404);
    });
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      await open(tester);

      expect(
        busLayer(tester).buses.map((b) => b.key),
        unorderedEquals(['bus-50-111', 'bus-50-1118', 'bus-50-139']),
      );
      expect(busLayer(tester).buses.every((b) => b.live), isTrue);
      expect(requests.map((u) => u.host).toSet(), {'proxy.test'});
    }, () => proxy);
  });

  /// The proxy answers 574 with its golden, stamped days before the
  /// phone's clock; [gps] false: the same board with no bus position.
  MockClient skewedProxy({bool gps = true}) {
    final golden =
        jsonDecode(
              File(
                'proxy/contract/v1/responses/arrivals_574.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final body = gps
        ? golden
        : {
            ...golden,
            'arrivals': [
              for (final a in golden['arrivals'] as List)
                {...a as Map<String, dynamic>, 'location': null},
            ],
          };
    return MockClient((request) async {
      requests.add(request.url);
      return request.url.path == '/v1/stops/574/arrivals'
          ? http.Response.bytes(
              utf8.encode(jsonEncode(body)),
              200,
              headers: {'content-type': 'application/json'},
            )
          : http.Response('{"error":"not_found"}', 404);
    });
  }

  testWidgets('a phone clock days ahead of the proxy: a board Mis paradas '
      'just brought is fresh, and the stop sheet is lit', (tester) async {
    MvdApiService.proxyUrl = 'https://proxy.test';
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      // Mis paradas refreshed a moment ago
      await MvdApiService.getBoards([574]);
      final asked = requests.length;
      await open(tester);
      expect(requests, hasLength(asked));
      expect(busLayer(tester).buses, isNotEmpty);
      expect(busLayer(tester).buses.every((b) => b.live), isTrue);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Parada 574')));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(ArrivalRow)),
        findsWidgets,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(MinutosEnVivo)),
        findsWidgets,
      );
    }, skewedProxy);
  });

  testWidgets('a phone clock days ahead of the proxy: no GPS bus is still '
      'said', (tester) async {
    MvdApiService.proxyUrl = 'https://proxy.test';
    await save(tester, [_stop574()]);
    await http.runWithClient(() async {
      await open(tester);
      expect(busLayer(tester).buses, isEmpty);
      expect(
        find.text('Ahora ningún ómnibus con GPS viene a tus paradas.'),
        findsOneWidget,
      );
    }, () => skewedProxy(gps: false));
  });
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
