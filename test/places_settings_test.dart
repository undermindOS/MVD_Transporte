// «Mis lugares» in Ajustes and the search page it opens. The search
// answers through PlaceSearchPage.suggest / .search; nothing goes to the
// network. Saving updates PlacesService.places before the Hive write, so
// the screen follows at once (see test/stop_search_test.dart).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/place.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/place_search.dart';
import 'package:stm_app/services/places_service.dart';
import 'package:stm_app/ui/place_search_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/places_settings.dart';

const _address = PlaceHit(
  title: 'Av 18 de Julio 1453',
  subtitle: 'Dirección · Montevideo',
  kind: PlaceHitKind.address,
  point: (lat: -34.9052, lon: -56.1849),
);
final _street = PlaceHit(
  title: 'Bv Gral Artigas',
  subtitle: 'Calle · agregá el número o la esquina',
  kind: PlaceHitKind.street,
  resolve: () async => null,
);
const _shop = PlaceHit(
  title: 'Montevideo Shopping',
  subtitle: 'Avenida Luis Alberto de Herrera 1290 · Buceo',
  kind: PlaceHitKind.poi,
  point: (lat: -34.9031, lon: -56.1364),
);

void main() {
  late Directory hiveDir;
  final suggested = <String>[];
  final searched = <String>[];
  Object? failure;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_places_settings');
    await CacheService.init(path: hiveDir.path);
    PlaceSearchPage.suggest = (text) async {
      suggested.add(text);
      if (failure case final f?) throw f;
      if (text.startsWith('bv gral')) return [_street];
      return [_address, _shop];
    };
    PlaceSearchPage.search = (text) async {
      searched.add(text);
      return [_shop];
    };
  });

  tearDownAll(() async {
    PlaceSearchPage.suggest = PlaceSearch.suggest;
    PlaceSearchPage.search = PlaceSearch.search;
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    suggested.clear();
    searched.clear();
    failure = null;
    CacheService.remove(CacheService.keyPlaces);
    CacheService.remove(CacheService.keyWalkMinutes);
    PlacesService.places.value = const [];
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimbreTheme(),
        home: Scaffold(body: ListView(children: const [PlacesSettings()])),
      ),
    );
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(PlaceSearchPage.debounce);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Casa by address: found, kept with it, and forgotten', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('MIS LUGARES'), findsOneWidget);
    expect(
      find.text('Sin marcar · tocá para buscar la dirección'),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dónde está tu casa?'), findsOneWidget);
    // Fewer than 3 letters: nothing asked
    await type(tester, '18');
    expect(suggested, isEmpty);
    await type(tester, '18 de julio 1453');
    expect(suggested, ['18 de julio 1453']);
    await tester.tap(find.text('Av 18 de Julio 1453'));
    await settle(tester);

    final casa = PlacesService.places.value.single;
    expect(casa.kind, PlaceKind.casa);
    expect((casa.lat, casa.lon), (-34.9052, -56.1849));
    expect(
      find.text('Av 18 de Julio 1453 · Dirección · Montevideo'),
      findsOneWidget,
    );

    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Olvidar este lugar'));
    await settle(tester);
    expect(PlacesService.places.value, isEmpty);
  });

  testWidgets('a favourite: searched, named, renamed; moved to another '
      'address', (tester) async {
    await open(tester);
    await tester.tap(find.text('Agregar un lugar'));
    await tester.pumpAndSettle();
    await type(tester, 'montevideo shopping');
    await tester.tap(find.text('Montevideo Shopping'));
    await tester.pumpAndSettle();
    // The name dialog starts with the place's name
    expect(find.widgetWithText(TextField, 'Montevideo Shopping'), findsOne);
    await tester.enterText(find.byType(TextField), 'Shopping');
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(PlacesService.places.value.single.name, 'Shopping');
    expect(find.text('Shopping'), findsOneWidget);

    await tester.tap(find.text('Shopping'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar la dirección'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva dirección de Shopping'), findsOneWidget);
    await type(tester, '18 de julio 1453');
    await tester.tap(find.text('Av 18 de Julio 1453'));
    await settle(tester);
    final moved = PlacesService.places.value.single;
    expect(moved.name, 'Shopping');
    expect((moved.lat, moved.lon), (-34.9052, -56.1849));
  });

  testWidgets('a street alone asks for its number in the same box; the '
      'search key asks once more; a failure is said', (tester) async {
    await open(tester);
    await tester.tap(find.text('Agregar un lugar'));
    await tester.pumpAndSettle();
    await type(tester, 'bv gral art');
    await tester.tap(find.text('Bv Gral Artigas'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Bv Gral Artigas ',
    );

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(searched, ['Bv Gral Artigas ']);

    failure = const PlaceSearchException(500);
    await type(tester, 'algo que falla');
    expect(find.text('No se pudo buscar. Revisá la conexión.'), findsOneWidget);
  });

  testWidgets('walking to the stop: 15 min is kept', (tester) async {
    await open(tester);
    await tester.tap(find.text('15 min'));
    await tester.pump();
    expect(PlacesService.walkMinutes, 15);
  });
}
