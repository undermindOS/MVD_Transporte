import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/nearby_stops_service.dart';

// Live WFS response captured on 2026-10-17: imm:v_uptu_paradas, 200 m box
// around 18 de Julio y Andes (356 "stop × variant" features, 10 stops).
const _fixture = 'test/fixtures/wfs_paradas_18_de_julio.json';
const _lat = -34.9066;
const _lng = -56.1985;

void main() {
  group('parseFeatures', () {
    final data = jsonDecode(File(_fixture).readAsStringSync());
    final stops = NearbyStopsService.parseFeatures(data,
        lat: _lat, lng: _lng, radius: 200);

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
      final all = NearbyStopsService.parseFeatures(data, lat: _lat, lng: _lng);
      expect(all, hasLength(10));
    });
  });

  group('parseFeatures robustness', () {
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

    test('returns empty for non-collections', () {
      expect(
          NearbyStopsService.parseFeatures(null, lat: _lat, lng: _lng), isEmpty);
      expect(NearbyStopsService.parseFeatures([], lat: _lat, lng: _lng),
          isEmpty);
      expect(
          NearbyStopsService.parseFeatures({'features': null},
              lat: _lat, lng: _lng),
          isEmpty);
    });

    test('skips features without stop code or coordinates', () {
      final stops = NearbyStopsService.parseFeatures({
        'features': [
          feature({'desc_linea': '116'}),
          feature({'cod_ubic_parada': 1, 'desc_linea': '116'}, coords: []),
          feature({'cod_ubic_parada': 2, 'desc_linea': '116'},
              coords: [null, null]),
          'garbage',
          feature({'cod_ubic_parada': 3, 'calle': 'A', 'esquina': 'B'}),
        ],
      }, lat: _lat, lng: _lng);
      expect(stops.map((s) => s.id), [3]);
      expect(stops.single.lines, isEmpty);
    });

    test('falls back when street names are missing', () {
      final stops = NearbyStopsService.parseFeatures({
        'features': [
          feature({'cod_ubic_parada': 1, 'calle': 'RAMBLA', 'esquina': null}),
          feature({'cod_ubic_parada': 2, 'calle': ' ', 'esquina': ''}),
        ],
      }, lat: _lat, lng: _lng);
      expect(stops.map((s) => s.name), containsAll(['RAMBLA', 'Parada 2']));
    });
  });

  group('buildUri', () {
    final uri = NearbyStopsService.buildUri(_lat, _lng, 400);
    final q = uri.queryParameters;

    test('queries the stops layer as GeoJSON in lat/lon degrees', () {
      expect(uri.host, 'geoserver.montevideo.gub.uy');
      expect(q['typename'], 'imm:v_uptu_paradas');
      expect(q['outputFormat'], 'application/json');
      expect(q['srsName'], 'EPSG:4326');
      expect(q['propertyName'],
          'cod_ubic_parada,desc_linea,calle,esquina,the_geom');
    });

    test('BBOX is lon,lat around the point (lat,lon returns nothing)', () {
      final parts = q['bbox']!.split(',');
      expect(parts.last, 'EPSG:4326');
      final box = parts.take(4).map(double.parse).toList();
      final [minLon, minLat, maxLon, maxLat] = box;
      expect(minLon, lessThan(_lng));
      expect(maxLon, greaterThan(_lng));
      expect(minLat, lessThan(_lat));
      expect(maxLat, greaterThan(_lat));
      // Half-side is the radius in both directions
      expect(NearbyStopsService.distanceMeters(_lat, _lng, maxLat, _lng),
          closeTo(400, 1));
      expect(NearbyStopsService.distanceMeters(_lat, _lng, _lat, maxLon),
          closeTo(400, 1));
    });
  });

  test('compareLines sorts lines naturally', () {
    final lines = ['D10', '124 SD', '21', 'CE1', '125', '104', '124', 'D1'];
    expect(lines..sort(NearbyStopsService.compareLines),
        ['21', '104', '124', '124 SD', '125', 'CE1', 'D1', 'D10']);
  });
}
