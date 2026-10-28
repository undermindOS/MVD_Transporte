// Where the saved stops are, for the Mapa: through the proxy from the stop
// catalog on the phone, without it from geoserver by stop number. HTTP is
// faked; plain tests, so every one can wait for Hive writes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/nearby_stops_service.dart';
import 'package:stm_app/services/stop_locations_service.dart';

// Live WFS answers captured on 2026-10-28 with buildStopUri: stop 574 (one
// of its 15 "stop × variant" features) and 9999999, which does not exist.
const _wfs574 = 'test/fixtures/wfs_parada_574.json';
const _wfsNone = 'test/fixtures/wfs_parada_9999999.json';
// SAN JOSE y ANDES, the same point in the WFS and in the proxy's catalog
const _at574 = (-34.90739436, -56.198255);

void main() {
  late Directory hiveDir;
  final requests = <Uri>[];
  // Set by each test: the answer to one request
  late Future<http.Response> Function(http.Request request) answer;
  final client = MockClient((request) async {
    requests.add(request.url);
    return answer(request);
  });

  http.Response file(String path) =>
      http.Response.bytes(File(path).readAsBytesSync(), 200,
          headers: {'content-type': 'application/json;charset=UTF-8'});
  // geoserver: 574 is found, any other number is not
  Future<http.Response> wfs(http.Request request) async =>
      request.url.queryParameters['CQL_FILTER'] == 'cod_ubic_parada=574'
          ? file(_wfs574)
          : file(_wfsNone);

  Future<int> fill([Iterable<BusStop>? stops]) => http.runWithClient(
      () => StopLocationsService.fillMissing(
          stops ?? CacheService.getAllStops()),
      () => client);
  Future<BusStop> saved(int id,
      {double latitude = 0, double longitude = 0}) async {
    final stop = BusStop(
        id: id, name: 'Parada $id', latitude: latitude, longitude: longitude);
    await CacheService.saveStop(stop);
    return stop;
  }

  (double, double) locationOf(int id) {
    final stop = CacheService.getStop(id)!;
    return (stop.latitude, stop.longitude);
  }

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_stop_locations_test');
    await CacheService.init(path: hiveDir.path);
  });

  setUp(() {
    StopLocationsService.reset();
    requests.clear();
    answer = wfs;
  });

  tearDown(() async {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
    StopLocationsService.reset();
    for (final s in CacheService.getAllStops()) {
      await CacheService.deleteStop(s.id);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  test('0.0, 0.0 is an unknown location', () {
    expect(BusStop(id: 1, name: 'A').hasLocation, isFalse);
    expect(BusStop(id: 1, name: 'A', latitude: _at574.$1).hasLocation, isTrue);
    expect(
        BusStop(id: 1, name: 'A', latitude: _at574.$1, longitude: _at574.$2)
            .hasLocation,
        isTrue);
  });

  group('without the proxy', () {
    test('asks geoserver for one stop by number, with no box or position',
        () {
      final uri = NearbyStopsService.buildStopUri(574);
      // The exact request the docs describe
      expect(
          '$uri',
          'https://geoserver.montevideo.gub.uy/geoserver/ows?service=wfs'
              '&version=2.0.0&request=GetFeature&typename=imm%3Av_uptu_paradas'
              '&outputFormat=application%2Fjson&srsName=EPSG%3A4326'
              '&propertyName=cod_ubic_parada%2Cthe_geom'
              '&CQL_FILTER=cod_ubic_parada%3D574&count=1');
      final q = uri.queryParameters;
      expect(q['CQL_FILTER'], 'cod_ubic_parada=574');
      expect(q.keys.map((k) => k.toLowerCase()), isNot(contains('bbox')));
      expect('$uri', isNot(contains('34.9')));
      expect('$uri', isNot(contains('56.1')));
    });

    test('fills the stops one at a time and saves them; one not found '
        'keeps 0.0', () async {
      await saved(574);
      await saved(9999999);
      // Already placed: never asked
      await saved(3140, latitude: -34.8, longitude: -56.1);
      var inFlight = 0, maxInFlight = 0;
      answer = (request) async {
        if (++inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inFlight--;
        return wfs(request);
      };

      expect(await fill(), 1);
      expect(maxInFlight, 1);
      expect(requests, unorderedEquals([
        NearbyStopsService.buildStopUri(574),
        NearbyStopsService.buildStopUri(9999999),
      ]));
      expect(locationOf(574), _at574);
      expect(CacheService.getStop(9999999)!.hasLocation, isFalse);
      expect(locationOf(3140), (-34.8, -56.1));

      // On disk, not only in memory
      await Hive.box<BusStop>('stops').close();
      final reopened = await Hive.openBox<BusStop>('stops');
      expect((reopened.get(574)!.latitude, reopened.get(574)!.longitude),
          _at574);
    });

    test('the stop given and its saved copy are updated, asked once',
        () async {
      await saved(574);
      final copy = BusStop(id: 574, name: 'Parada 574');
      expect(await fill([copy, copy]), 1);
      expect(requests, hasLength(1));
      expect((copy.latitude, copy.longitude), _at574);
      expect(locationOf(574), _at574);
    });

    test('a stop looked up less than 10 minutes ago is not asked again',
        () async {
      var now = DateTime.utc(2026, 10, 28, 12);
      StopLocationsService.clock = () => now;
      await saved(9999999);

      expect(await fill(), 0);
      expect(requests, hasLength(1));
      expect(await fill(), 0);
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(await fill(), 0);
      expect(requests, hasLength(1));

      now = now.add(const Duration(seconds: 1));
      expect(await fill(), 0);
      expect(requests, hasLength(2));
    });

    test('a failed answer is tolerated, and waits like one not found',
        () async {
      await saved(574);
      for (final failure in <Future<http.Response> Function(http.Request)>[
        (_) async => http.Response('', 500),
        (_) async => http.Response('<html>busy</html>', 200),
        (_) async => throw http.ClientException('offline'),
      ]) {
        StopLocationsService.reset();
        answer = failure;
        expect(await fill(), 0);
        expect(CacheService.getStop(574)!.hasLocation, isFalse);
      }
      expect(requests, hasLength(3));

      // Within the 10 minutes the stop is not asked, even if it would work
      answer = wfs;
      expect(await fill(), 0);
      expect(requests, hasLength(3));
    });

    test('a stop deleted during the lookup is not saved back', () async {
      await saved(574);
      answer = (request) async {
        await CacheService.deleteStop(574);
        return wfs(request);
      };
      expect(await fill(), 0);
      expect(CacheService.getStop(574), isNull);
    });
  });

  group('through the proxy', () {
    final catalog =
        File('test/fixtures/proxy_catalog_stops.json').readAsBytesSync();

    setUp(() async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      MvdApiService.clearCatalogMemory();
      await CacheService.remove(CacheService.keyStopCatalog);
      answer = (request) async => request.url.path == '/v1/catalog/stops'
          ? http.Response.bytes(catalog, 200)
          : http.Response('{"error":"not_found"}', 404);
    });

    test('fills from the stop catalog and asks no city host', () async {
      await saved(574);
      await saved(9999999);

      expect(await fill(), 1);
      expect(requests.map((u) => '$u'),
          ['https://proxy.test/v1/catalog/stops']);
      expect(locationOf(574), _at574);
      expect(CacheService.getStop(9999999)!.hasLocation, isFalse);

      // With the catalog on the phone nothing is asked at all
      requests.clear();
      StopLocationsService.reset();
      expect(await fill(), 0);
      expect(requests, isEmpty);
    });

    test('the WFS lookup by number is closed to a proxy build', () async {
      await saved(574);
      answer = (_) async => throw http.ClientException('offline');

      expect(await fill(), 0);
      expect(
          await http.runWithClient(
              () => NearbyStopsService.fetchStop(574), () => client),
          isNull);
      expect(requests.map((u) => '$u'),
          ['https://proxy.test/v1/catalog/stops']);
      expect(CacheService.getStop(574)!.hasLocation, isFalse);
    });

    test('a located stop asks nothing, not even the catalog', () async {
      await saved(574, latitude: _at574.$1, longitude: _at574.$2);
      expect(await fill(), 0);
      expect(requests, isEmpty);
    });
  });
}
