// The places on the Mapa, as in a map app: a long press or the search
// drops a pin with its card (go there, or keep it as Casa, Trabajo or a
// favourite); the bar and the map show the places; a place can be renamed
// or forgotten. No saved stops, so nothing goes to the network; the search
// answers through PlaceSearchPage.suggest.
//
// Saving a place updates PlacesService.places before its Hive write, so
// the screen follows at once; the writes finish in runAsync (see
// test/stop_search_test.dart on awaited Hive writes in widget tests).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/models/place.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/place_search.dart';
import 'package:stm_app/services/places_service.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/place_search_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

void main() {
  late Directory hiveDir;
  final typed = <String>[];

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_places_ui');
    await CacheService.init(path: hiveDir.path);
    PlaceSearchPage.suggest = (text) async {
      typed.add(text);
      return [
        const PlaceHit(
          title: 'Av 18 de Julio 1453',
          subtitle: 'Dirección · Montevideo',
          kind: PlaceHitKind.address,
          point: (lat: -34.9052, lon: -56.1849),
        ),
      ];
    };
  });

  // Not Hive.close: it would wait for writes chained in a test's fake-async
  // zone, which never finish
  tearDownAll(() async {
    PlaceSearchPage.suggest = PlaceSearch.suggest;
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    typed.clear();
    // No await: see the header
    CacheService.remove(CacheService.keyPlaces);
    PlacesService.places.value = const [];
  });

  Future<void> open(WidgetTester tester) async {
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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  /// Types in the search page and waits out the debounce.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(PlaceSearchPage.debounce);
    await tester.pumpAndSettle();
  }

  testWidgets('a long press drops a pin; «Casa» keeps it: the chip lights '
      'up and the map shows it', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(find.bySemanticsLabel('Casa, sin marcar'), findsOneWidget);

    await tester.longPress(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    expect(find.text('Punto en el mapa'), findsOneWidget);
    expect(find.text('Cómo llegar'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Guardar como Casa'));
    await settle(tester);

    expect(PlacesService.places.value.single.kind, PlaceKind.casa);
    expect(find.text('Casa guardada.'), findsOneWidget);
    expect(find.text('Punto en el mapa'), findsNothing);
    expect(find.bySemanticsLabel('Cómo llegar a Casa'), findsOneWidget);
    expect(find.bySemanticsLabel('Casa, sin marcar'), findsNothing);
    // The marker on the map
    expect(find.bySemanticsLabel('Casa'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a favourite asks its name; it can be renamed and forgotten', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    await tester.longPress(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Guardar como favorito'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Facultad ');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(find.bySemanticsLabel('Cómo llegar a Facultad'), findsOneWidget);

    // Its marker opens its sheet
    await tester.tap(find.bySemanticsLabel('Facultad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar el nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fing');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(PlacesService.places.value.single.name, 'Fing');

    await tester.tap(find.bySemanticsLabel('Fing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olvidar este lugar'));
    await settle(tester);
    expect(PlacesService.places.value, isEmpty);
    expect(find.bySemanticsLabel('Cómo llegar a Fing'), findsNothing);
    handle.dispose();
  });

  testWidgets('the search box: the address found gets the pin and its card', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.bySemanticsLabel('Buscar una dirección o un lugar'));
    await tester.pumpAndSettle();
    await type(tester, '18 de julio 1453');
    expect(typed, ['18 de julio 1453']);
    await tester.tap(find.text('Av 18 de Julio 1453'));
    await tester.pumpAndSettle();

    expect(find.text('Av 18 de Julio 1453'), findsOneWidget);
    expect(find.text('Dirección · Montevideo'), findsOneWidget);
    expect(find.text('Cómo llegar'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Av 18 de Julio 1453'), findsNothing);
    handle.dispose();
  });

  testWidgets('an unmarked Trabajo opens the search, and keeps what is '
      'picked with its address', (tester) async {
    await open(tester);
    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dónde está tu trabajo?'), findsOneWidget);
    await type(tester, '18 de julio 1453');
    await tester.tap(find.text('Av 18 de Julio 1453'));
    await settle(tester);

    final trabajo = PlacesService.places.value.single;
    expect(trabajo.kind, PlaceKind.trabajo);
    expect(trabajo.address, 'Av 18 de Julio 1453 · Dirección · Montevideo');
    // «Trabajo guardado.» comes after the Hive write, which only the first
    // test of a file can await (see the header)
  });
}
