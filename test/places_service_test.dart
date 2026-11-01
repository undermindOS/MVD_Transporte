import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:stm_app/models/place.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/places_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mvd_places_test');
    await CacheService.init(path: dir.path);
    PlacesService.load();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Place casa(double lat) => Place.at(PlaceKind.casa, lat: lat, lon: -56.15);

  test('Casa, Trabajo and favourites come back in that order after a '
      'restart', () async {
    await PlacesService.save(
      Place.at(
        PlaceKind.favorito,
        lat: -34.90,
        lon: -56.20,
        name: '  Facultad ',
        now: DateTime(2026, 11, 1),
      ),
    );
    await PlacesService.save(
      Place.at(PlaceKind.trabajo, lat: -34.91, lon: -56.19),
    );
    await PlacesService.save(casa(-34.92));

    await Hive.close();
    await CacheService.init(path: dir.path);
    PlacesService.load();

    final places = PlacesService.places.value;
    expect(places.map((p) => p.name), ['Casa', 'Trabajo', 'Facultad']);
    expect(places.first, casa(-34.92));
    expect(
      places.last.id,
      'fav-${DateTime(2026, 11, 1).millisecondsSinceEpoch}',
    );
  });

  test('a new Casa moves the old one; delete forgets a place', () async {
    await PlacesService.save(casa(-34.92));
    await PlacesService.save(casa(-34.88));
    expect(PlacesService.places.value, [casa(-34.88)]);

    await PlacesService.delete('casa');
    expect(PlacesService.places.value, isEmpty);
  });

  test('a renamed favourite keeps its id and point', () async {
    final fav = Place.at(
      PlaceKind.favorito,
      lat: -34.9,
      lon: -56.2,
      name: 'Club',
      now: DateTime(2026),
    );
    await PlacesService.save(fav);
    await PlacesService.save(fav.renamed('Club de Pesca'));
    expect(PlacesService.places.value.single.name, 'Club de Pesca');
    expect(PlacesService.places.value.single.id, fav.id);
  });

  test('places in a shape this app does not read are skipped', () async {
    await CacheService.set<String>(
      CacheService.keyPlaces,
      '[{"id":"casa","kind":"casa","name":"Casa","lat":-34.9,"lon":-56.1},'
      '{"id":"x","kind":"barco","name":"?","lat":0,"lon":0},'
      '{"id":"y","kind":"favorito"}, 7]',
    );
    PlacesService.load();
    expect(PlacesService.places.value.map((p) => p.id), ['casa']);

    await CacheService.set<String>(CacheService.keyPlaces, 'not json');
    PlacesService.load();
    expect(PlacesService.places.value, isEmpty);
  });

  test(
    'the walking limit is 10 min until one of 5, 10 or 15 is chosen',
    () async {
      expect(PlacesService.walkMinutes, 10);
      await PlacesService.setWalkMinutes(15);
      expect(PlacesService.walkMinutes, 15);
      expect(() => PlacesService.setWalkMinutes(7), throwsArgumentError);
      await CacheService.set<int>(CacheService.keyWalkMinutes, 99);
      expect(PlacesService.walkMinutes, 10);
    },
  );
}
