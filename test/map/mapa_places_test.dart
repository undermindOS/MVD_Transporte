// The places on the Mapa: a long press keeps a point as Casa, Trabajo or a
// favourite; the bar and the map show them; a place can be renamed or
// forgotten. No saved stops, so nothing goes to the network.
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
import 'package:stm_app/services/places_service.dart';
import 'package:stm_app/ui/map/mapa_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_places_ui');
    await CacheService.init(path: hiveDir.path);
  });

  // Not Hive.close: it would wait for writes chained in a test's fake-async
  // zone, which never finish
  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
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

  testWidgets('a long press marks Casa: the chip lights up and the map '
      'shows it', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(find.bySemanticsLabel('Casa, sin marcar'), findsOneWidget);

    await tester.longPress(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    expect(find.text('Cómo llegar acá'), findsOneWidget);
    await tester.tap(find.text('Marcar como Casa'));
    await settle(tester);

    expect(PlacesService.places.value.single.kind, PlaceKind.casa);
    expect(find.bySemanticsLabel('Cómo llegar a Casa'), findsOneWidget);
    expect(find.bySemanticsLabel('Casa, sin marcar'), findsNothing);
    // The marker on the map
    expect(find.bySemanticsLabel('Casa'), findsOneWidget);

    // A second long press moves it
    await tester.longPress(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    expect(find.text('Mover Casa acá'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a favourite asks its name; it can be renamed and forgotten', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    await tester.longPress(find.byType(FlutterMap));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar como favorito'));
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

  testWidgets('an unmarked Trabajo says how to mark it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Trabajo'));
    await tester.pump();
    expect(
      find.text(
        'Mantené apretado el mapa donde está tu trabajo y elegí '
        '«Marcar como Trabajo».',
      ),
      findsOneWidget,
    );
  });
}
