// PlaceSearch against a MockClient that answers like the IM's
// ubicacionesRest, Photon and Nominatim did on 2026-11-01.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stm_app/services/place_search.dart';

http.Response _json(String body, [int status = 200]) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('UTM 21 south to degrees, under a metre off across the city', () {
    // Forward projection of these points (Snyder), to the millimetre
    for (final (x, y, lat, lon) in [
      (573880.538, 6137104.908, -34.9058, -56.1913),
      (567805.625, 6139680.562, -34.8830, -56.2580),
      (586263.268, 6139303.422, -34.8850, -56.0560),
    ]) {
      final p = utm21sToWgs84(x, y);
      expect(p.lat, closeTo(lat, 1e-6));
      expect(p.lon, closeTo(lon, 1e-6));
    }
  });

  test('the words the city abbreviates, without accents', () {
    expect(
      PlaceSearch.normalize('Bulevar General  Artigas'),
      'bv gral artigas',
    );
    expect(PlaceSearch.normalize('Avenida Gral. Rivera'), 'av gral rivera');
    expect(
      PlaceSearch.normalize('José Batlle y Ordóñez'),
      'jose batlle y ordonez',
    );
  });

  test('a point, a punto, or the middle of an outline', () {
    final point = PlaceSearch.pointOf({
      'geoJSON': {
        'type': 'Point',
        'coordinates': [573880.538, 6137104.908],
      },
    })!;
    expect(point.lat, closeTo(-34.9058, 1e-6));
    final punto = PlaceSearch.pointOf({
      'descripcion': 'AV 18 DE JULIO 1453',
      'punto': {
        'geoJSON': {
          'type': 'Point',
          'coordinates': [573880.538, 6137104.908],
        },
      },
    })!;
    expect(punto.lon, closeTo(-56.1913, 1e-6));
    final park = PlaceSearch.pointOf({
      'geometria': {
        'geoJSON': {
          'type': 'MultiPolygon',
          'coordinates': [
            [
              [
                [573870.538, 6137094.908],
                [573890.538, 6137094.908],
                [573890.538, 6137114.908],
                [573870.538, 6137114.908],
              ],
            ],
          ],
        },
      },
    })!;
    expect(park.lat, closeTo(-34.9058, 1e-5));
    expect(PlaceSearch.pointOf(null), isNull);
    expect(PlaceSearch.pointOf({'tipo': 'NO_EXISTE'}), isNull);
  });

  group('suggest', () {
    final asked = <Uri>[];
    var photonFails = false;
    var cityFails = false;

    final client = MockClient((request) async {
      asked.add(request.url);
      final u = request.url;
      if (u.host == 'photon.komoot.io') {
        if (photonFails) return http.Response('', 503);
        return _json(
          '{"features":[{"type":"Feature","properties":{"osm_key":"shop",'
          '"name":"Montevideo Shopping","street":"Avenida Luis Alberto de '
          'Herrera","housenumber":"1290","district":"Buceo"},"geometry":'
          '{"type":"Point","coordinates":[-56.1363655,-34.9030628]}},'
          '{"type":"Feature","properties":{"osm_key":"highway","name":'
          '"Avenida 18 de Julio"},"geometry":{"type":"Point","coordinates":'
          '[-56.18,-34.90]}}]}',
        );
      }
      if (cityFails) return http.Response('', 500);
      if (u.path.endsWith('/infoUbicacion/lugaresDeInteresYVias/')) {
        final name = u.queryParameters['nombre']!;
        if (name == '18 de julio') {
          return _json(
            '[{"descTipo":"VIA","codigo":7572,"nombre":"AV 18 DE JULIO"},'
            '{"descSubtipo":"MONUMENTO","descTipo":"LUGAR DE INTERES",'
            '"codigo":725,"nombre":"PUENTE 18 DE JULIO"}]',
          );
        }
        if (name == 'montevideo shopping') return _json('[]');
        return _json('[]');
      }
      if (u.path.endsWith('/infoUbicacion/esquinas/7572')) {
        return _json('[{"descTipo":"VIA","nombre":"EJIDO","codigo":2481}]');
      }
      if (u.path.endsWith('/direcciones/posicion/7572/1453')) {
        return _json(
          '{"geoJSON":{"type":"Point","coordinates":[574465.9748,6137165.9212]}}',
        );
      }
      if (u.path.endsWith('/esquinas/posicion/7572/2481')) {
        return _json(
          '{"geoJSON":{"type":"Point","coordinates":[574285.6123,6137129.8161]}}',
        );
      }
      if (u.host == 'nominatim.openstreetmap.org') {
        return _json(
          '[{"name":"Tienda Inglesa","display_name":"Tienda Inglesa, '
          'Avenida Brasil, Pocitos, Montevideo","lat":"-34.9101",'
          '"lon":"-56.1520"}]',
        );
      }
      return http.Response('', 404);
    });

    setUp(() {
      asked.clear();
      photonFails = false;
      cityFails = false;
    });

    test(
      'a door number is looked up at once: only streets that have it',
      () async {
        await http.runWithClient(() async {
          final hits = await PlaceSearch.suggest('18 de julio 1453');
          final first = hits.first;
          expect(first.title, 'Av 18 de Julio 1453');
          expect(first.kind, PlaceHitKind.address);
          final point = first.point!;
          expect(point.lat, closeTo(-34.9054, 1e-3));
          expect(point.lon, closeTo(-56.1849, 1e-3));
          // Only the text left the phone: no position in any request
          expect(
            asked.every((u) => !u.queryParameters.containsKey('lat')),
            isTrue,
          );
        }, () => client);
      },
    );

    test('a corner', () async {
      await http.runWithClient(() async {
        final hits = await PlaceSearch.suggest('18 de julio y ejido');
        expect(hits.first.title, 'Av 18 de Julio y Ejido');
        expect(hits.first.kind, PlaceHitKind.corner);
        expect(await hits.first.locate(), isNotNull);
      }, () => client);
    });

    test('a name: the city\'s street and landmark, then the shops, no '
        'OpenStreetMap street', () async {
      await http.runWithClient(() async {
        final hits = await PlaceSearch.suggest('18 de julio');
        expect(hits.map((h) => (h.title, h.kind)), [
          ('Av 18 de Julio', PlaceHitKind.street),
          ('Puente 18 de Julio', PlaceHitKind.landmark),
          ('Montevideo Shopping', PlaceHitKind.poi),
        ]);
        expect(hits.last.point!.lat, closeTo(-34.9031, 1e-4));
        expect(hits.last.subtitle, contains('Buceo'));
      }, () => client);
    });

    test('one source down: the other answers; both down: an error', () async {
      await http.runWithClient(() async {
        cityFails = true;
        final hits = await PlaceSearch.suggest('montevideo shopping');
        expect(hits.single.title, 'Montevideo Shopping');
        photonFails = true;
        await expectLater(
          PlaceSearch.suggest('montevideo shopping'),
          throwsA(isA<PlaceSearchException>()),
        );
      }, () => client);
    });

    test('under 3 letters: nothing is asked', () async {
      await http.runWithClient(() async {
        expect(await PlaceSearch.suggest('18'), isEmpty);
        expect(asked, isEmpty);
      }, () => client);
    });

    test('the search key adds Nominatim, at most once a second', () async {
      await http.runWithClient(() async {
        var now = DateTime(2026, 11, 1, 12);
        PlaceSearch.clock = () => now;
        addTearDown(() => PlaceSearch.clock = DateTime.now);
        final hits = await PlaceSearch.search('tienda inglesa');
        expect(hits.map((h) => h.title), contains('Tienda Inglesa'));
        asked.clear();
        await PlaceSearch.search('tienda inglesa');
        expect(asked.where((u) => u.host.startsWith('nominatim')), isEmpty);
        now = now.add(const Duration(seconds: 1));
        await PlaceSearch.search('tienda inglesa');
        expect(
          asked.where((u) => u.host.startsWith('nominatim')),
          hasLength(1),
        );
      }, () => client);
    });
  });
}
