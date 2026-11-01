import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stm_app/models/catalog_stop.dart';
import 'package:stm_app/models/nearby_stop.dart';
import 'package:stm_app/services/api/direct/wfs_adapter.dart';
import 'package:stm_app/services/api/v1_parser.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/nearby_stops_service.dart';

// Live WFS response captured on 2026-10-17: imm:v_uptu_paradas, 200 m box
// around 18 de Julio y Andes (356 "stop × variant" features, 10 stops).
const _fixture = 'test/fixtures/wfs_paradas_18_de_julio.json';
const _lat = -34.9066;
const _lng = -56.1985;

/// A WFS answer as the direct mode reads it: catalog stops.
List<CatalogStop> _catalogOf(Object? wfs) =>
    V1Parser.catalog({'stops': WfsAdapter.featuresToCatalogItems(wfs)})!
        .stops;

/// The stops of a WFS answer around the fixture's point.
List<NearbyStop> _nearby(Object? wfs, {double radius = 400}) =>
    NearbyStopsService.nearbyFrom(_catalogOf(wfs), _lat, _lng,
        radius: radius);

void main() {
  group('nearbyFrom on the WFS fixture', () {
    final data = jsonDecode(File(_fixture).readAsStringSync());
    final stops = _nearby(data, radius: 200);

    test('groups variants by stop, drops box corners, nearest first', () {
      expect(stops.map((s) => s.id),
          [5109, 3914, 574, 4019, 3177, 4018, 5033]);
      // 4756 (210 m), 5124 (213 m), 4757 (229 m) are inside the box only
      expect(stops.map((s) => s.id), isNot(contains(4756)));
      expect(stops.first.distanceMeters, closeTo(47.8, 0.5));
      expect(stops.last.distanceMeters, lessThanOrEqualTo(200));
    });

    test('names the stop "calle y esquina" like transporteRest/lineas', () {
      final stop = stops.firstWhere((s) => s.id == 574);
      expect(stop.name, 'SAN JOSE y ANDES');
      expect(stop.latitude, closeTo(-34.90739436, 1e-8));
      expect(stop.longitude, closeTo(-56.198255, 1e-8));
    });

    test('collects distinct lines in natural order', () {
      // Same set as GET transporteRest/lineas/574 on the same day
      expect(stops.firstWhere((s) => s.id == 574).lines,
          ['116', '117', '121', '141', '142', '144', '538']);
      expect(stops.firstWhere((s) => s.id == 3177).lines, [
        '21', '60', '62', '64', '104', '180', '187', '188', //
        'CE1', 'E14', 'M-A', 'M-B',
      ]);
      expect(stops.first.lines.take(3), ['124', '124 SD', '125']);
    });

    test('keeps same-corner stops on different sides apart', () {
      final convencion = stops
          .where((s) => s.name == 'AV 18 DE JULIO y CONVENCION')
          .map((s) => s.id);
      expect(convencion, [4019, 3177, 4018]);
    });

    test('default radius keeps every stop of the 200 m box', () {
      final all = NearbyStopsService.nearbyFrom(_catalogOf(data), _lat, _lng);
      expect(all, hasLength(10));
    });
  });

  group('nearbyFrom robustness', () {
    Map<String, dynamic> feature(Map<String, dynamic> props,
            {List<dynamic>? coords}) =>
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': coords ?? [_lng, _lat],
          },
          'properties': props,
        };

    test('nothing near an empty catalog', () {
      expect(NearbyStopsService.nearbyFrom(const [], _lat, _lng), isEmpty);
    });

    test('skips features without stop code or coordinates', () {
      final stops = _nearby({
        'features': [
          feature({'desc_linea': '116'}),
          feature({'cod_ubic_parada': 1, 'desc_linea': '116'}, coords: []),
          feature({'cod_ubic_parada': 2, 'desc_linea': '116'},
              coords: [null, null]),
          'garbage',
          feature({'cod_ubic_parada': 3, 'calle': 'A', 'esquina': 'B'}),
        ],
      });
      expect(stops.map((s) => s.id), [3]);
      expect(stops.single.lines, isEmpty);
    });

    test('falls back when street names are missing', () {
      final stops = _nearby({
        'features': [
          feature({'cod_ubic_parada': 1, 'calle': 'RAMBLA', 'esquina': null}),
          feature({'cod_ubic_parada': 2, 'calle': ' ', 'esquina': ''}),
        ],
      });
      expect(stops.map((s) => s.name), containsAll(['RAMBLA', 'Parada 2']));
    });
  });

  group('WfsAdapter.featuresToCatalogItems', () {
    test('groups the variants by stop into /v1 catalog items', () {
      final items = WfsAdapter.featuresToCatalogItems(
          jsonDecode(File(_fixture).readAsStringSync()))!;
      // Every stop of the box, before any distance filter
      expect(items, hasLength(10));
      expect(items.singleWhere((s) => s['id'] == 574), {
        'id': 574,
        'name': 'SAN JOSE y ANDES',
        'location': {'lat': -34.90739436, 'lng': -56.198255},
        'lines': ['116', '117', '121', '141', '142', '144', '538'],
      });
    });

    test('a stop without street names has no name; non-collections fail',
        () {
      final items = WfsAdapter.featuresToCatalogItems({
        'features': [
          {
            'geometry': {
              'coordinates': [_lng, _lat]
            },
            'properties': {'cod_ubic_parada': 2, 'calle': ' ', 'esquina': ''},
          },
          'garbage',
        ],
      })!;
      expect(items.single['name'], isNull);
      expect(items.single['lines'], isEmpty);
      expect(WfsAdapter.featuresToCatalogItems([]), isNull);
      expect(WfsAdapter.featuresToCatalogItems({'features': null}), isNull);
    });
  });

  group('buildUri', () {
    final uri = NearbyStopsService.buildUri(_lat, _lng);
    final q = uri.queryParameters;

    // [minLon, minLat, maxLon, maxLat] of the BBOX
    List<double> box(Uri uri) {
      final parts = uri.queryParameters['bbox']!.split(',');
      expect(parts.last, 'EPSG:4326');
      return parts.take(4).map(double.parse).toList();
    }

    test('queries the stops layer as GeoJSON in lat/lon degrees', () {
      expect(uri.host, 'geoserver.montevideo.gub.uy');
      expect(q['typename'], 'imm:v_uptu_paradas');
      expect(q['outputFormat'], 'application/json');
      expect(q['srsName'], 'EPSG:4326');
      expect(q['propertyName'],
          'cod_ubic_parada,desc_linea,calle,esquina,the_geom');
    });

    test('BBOX is lon,lat around the point (lat,lon returns nothing)', () {
      final [minLon, minLat, maxLon, maxLat] = box(uri);
      expect(minLon, lessThan(_lng));
      expect(maxLon, greaterThan(_lng));
      expect(minLat, lessThan(_lat));
      expect(maxLat, greaterThan(_lat));
    });

    test('the box is centred on the position rounded to 3 decimals', () {
      final [minLon, minLat, maxLon, maxLat] =
          box(NearbyStopsService.buildUri(-34.9058, -56.1913));
      final (lat, lng) = ((minLat + maxLat) / 2, (minLon + maxLon) / 2);
      expect(lat, closeTo(-34.906, 1e-6));
      expect(lng, closeTo(-56.191, 1e-6));
      // Half-side 472 m: the 400 m radius plus half a 0.001° cell diagonal
      expect(NearbyStopsService.distanceMeters(lat, lng, maxLat, lng),
          closeTo(472, 1));
      expect(NearbyStopsService.distanceMeters(lat, lng, lat, maxLon),
          closeTo(472, 1));
      // Any position in the same cell asks for the same box
      expect(NearbyStopsService.buildUri(-34.90551, -56.19149),
          NearbyStopsService.buildUri(-34.9058, -56.1913));
    });
  });

  group('without the proxy', () {
    final wfs = File(_fixture).readAsStringSync();
    final requests = <Uri>[];
    var answer = http.Response(wfs, 200);
    final client = MockClient((request) async {
      requests.add(request.url);
      return answer;
    });

    setUp(() {
      MvdApiService.proxyUrl = '';
      requests.clear();
      answer = http.Response.bytes(utf8.encode(wfs), 200);
    });

    test('the stops of the WFS box, filtered by the exact position',
        () async {
      final stops = await http.runWithClient(
          () => NearbyStopsService.fetchNearby(_lat, _lng), () => client);
      expect(requests.single.host, 'geoserver.montevideo.gub.uy');
      expect(requests.single, NearbyStopsService.buildUri(_lat, _lng));
      // The same order and distances as the shared nearbyFrom
      final expected = _nearby(jsonDecode(wfs));
      expect(stops!.map((s) => s.id), expected.map((s) => s.id));
      expect(stops.map((s) => s.distanceMeters),
          expected.map((s) => s.distanceMeters));
      expect(stops.first.id, 5109);
      expect(stops.first.distanceMeters, closeTo(47.8, 0.5));
    });

    test('a failed or malformed answer is a network error', () async {
      for (final failure in [
        http.Response('', 500),
        http.Response('{"error":true}', 200),
      ]) {
        answer = failure;
        expect(
            await http.runWithClient(
                () => NearbyStopsService.fetchNearby(_lat, _lng),
                () => client),
            isNull);
      }
    });
  });

  group('through the proxy', () {
    late Directory hiveDir;
    final catalog =
        File('test/fixtures/proxy_catalog_stops.json').readAsBytesSync();
    var proxyUp = true;
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (!proxyUp) throw http.ClientException('offline');
      return request.url.path == '/v1/catalog/stops'
          ? http.Response.bytes(catalog, 200)
          : http.Response('{"error":"not_found"}', 404);
    });
    Future<List<NearbyStop>> findNearMe() =>
        http.runWithClient(NearbyStopsService.findNearMe, () => client);

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('mvd_nearby_test');
      await CacheService.init(path: hiveDir.path);
    });

    setUp(() async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      MvdApiService.clearCatalogMemory();
      await CacheService.remove(CacheService.keyStopCatalog);
      GeolocatorPlatform.instance = _FakeGeolocator();
      proxyUp = true;
      requests.clear();
    });

    tearDown(() => MvdApiService.proxyUrl = '');

    tearDownAll(() async {
      await hiveDir.delete(recursive: true);
    });

    test('the position never leaves the phone: only the catalog is asked',
        () async {
      final stops = await findNearMe();
      expect(requests.map((u) => '$u'),
          ['https://proxy.test/v1/catalog/stops']);
      for (final u in requests) {
        expect('$u', isNot(contains('34.9')));
        expect('$u', isNot(contains('56.1')));
      }
      expect(stops.map((s) => s.id), contains(574));
      expect(stops.every((s) => s.distanceMeters <= 400), isTrue);
      final distances = [for (final s in stops) s.distanceMeters];
      expect(distances, [...distances]..sort());

      // With the catalog on the phone nothing is requested at all
      requests.clear();
      expect(await findNearMe(), hasLength(stops.length));
      MvdApiService.clearCatalogMemory();
      expect(await findNearMe(), hasLength(stops.length));
      expect(requests, isEmpty);
    });

    test('no catalog and no proxy is a network error', () async {
      proxyUp = false;
      await expectLater(
          findNearMe(),
          throwsA(isA<NearbyStopsException>()
              .having((e) => e.error, 'error', NearbyStopsError.network)));
      expect(requests.map((u) => u.host), everyElement('proxy.test'));
    });
  });

  test('compareLines sorts lines naturally', () {
    final lines = ['D10', '124 SD', '21', 'CE1', '125', '104', '124', 'D1'];
    expect(lines..sort(NearbyStopsService.compareLines),
        ['21', '104', '124', '124 SD', '125', 'CE1', 'D1', 'D10']);
  });
}

/// Location allowed, at 18 de Julio y Andes.
class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
        latitude: _lat,
        longitude: _lng,
        timestamp: DateTime(2026, 10, 27),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
