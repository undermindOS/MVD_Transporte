// A build with the proxy talks to the proxy only: no city host is ever
// contacted and no request carries the position (docs/privacy-policy.md).
// Every service is called once; HTTP answers are the contract's goldens
// (proxy/contract/v1/responses), the plugin channels are faked.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/route_alert.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/services/background_worker.dart';
import 'package:stm_app/services/bus_status_service.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/nearby_stops_service.dart';
import 'package:stm_app/services/notification_service.dart';
import 'package:stm_app/services/transport_news_service.dart';

const _responses = 'proxy/contract/v1/responses';
const _cityHosts = {
  'api.montevideo.gub.uy',
  'pci.montevideo.gub.uy',
  'geoserver.montevideo.gub.uy',
};
// 18 de Julio y Andes
const _lat = -34.9066;
const _lng = -56.1985;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const widgetChannel = MethodChannel('home_widget');
  late Directory hiveDir;
  final requests = <Uri>[];

  http.Response file(String path) =>
      http.Response.bytes(File(path).readAsBytesSync(), 200);
  final client = MockClient((request) async {
    requests.add(request.url);
    return switch (request.url.path) {
      '/v1/stops/574' => file('$_responses/stop_574.json'),
      '/v1/stops/574/arrivals' => file('$_responses/arrivals_574.json'),
      '/v1/stops/3140/schedule/weekday/8:05' =>
        file('$_responses/schedule_3140_weekday_8-05.json'),
      '/v1/catalog/stops' => file('test/fixtures/proxy_catalog_stops.json'),
      '/v1/news' => file('$_responses/news_cold.json'),
      '/v1/status/gps' => file('$_responses/gps_ok.json'),
      _ => http.Response('{"error":"not_found"}', 404),
    };
  });

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_privacy_test');
    await CacheService.init(path: hiveDir.path);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(notificationsChannel,
        (call) async => call.method == 'initialize' ? true : null);
    messenger.setMockMethodCallHandler(widgetChannel, (_) async => true);
    await NotificationService.init();
    GeolocatorPlatform.instance = _FakeGeolocator();
    MvdApiService.proxyUrl = 'https://proxy.test';
  });

  tearDownAll(() async {
    MvdApiService.proxyUrl = '';
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(widgetChannel, null);
    await hiveDir.delete(recursive: true);
  });

  test('every service asks the proxy and nobody else', () async {
    await CacheService.saveStop(BusStop(
        id: 574,
        name: 'Parada 574',
        notificationsEnabled: true,
        etaAlertMinutes: 10));
    await CacheService.saveRoute(RouteAlert(
        id: 1,
        originStopId: 574,
        originName: 'SAN JOSE y ANDES',
        destinationName: 'Trabajo'));

    await http.runWithClient(() async {
      expect((await MvdApiService.getBoard(574)).valueOrNull, isNotNull);
      expect(await MvdApiService.getBoards([574, 574]), hasLength(1));
      expect(await MvdApiService.getNextArrivals(574), hasLength(6));
      expect((await MvdApiService.getStopDetails(574)).valueOrNull, isNotNull);
      expect(await MvdApiService.resolveStop(574), isNotNull);
      expect(await MvdApiService.healPlaceholderStops(), 1);
      expect(await MvdApiService.getSchedule(3140, DayType.habil, 8, 5),
          isNotEmpty);
      expect(await MvdApiService.getStopCatalog(), isNotEmpty);
      expect(await TransportNewsService.refresh(force: true), hasLength(10));
      BusStatusService.reset();
      expect(await BusStatusService.getStatus(), hasLength(4));
      MvdApiService.clearCatalogMemory();
      expect(await NearbyStopsService.findNearMe(), isNotEmpty);
      await BackgroundWorker.checkAlerts(DateTime.now());
    }, () => client);

    expect(requests, isNotEmpty);
    for (final url in requests) {
      expect(url.host, 'proxy.test');
      expect(_cityHosts, isNot(contains(url.host)));
      // The position goes nowhere, not even to the proxy
      expect('$url', isNot(contains('34.9')));
      expect('$url', isNot(contains('56.1')));
    }
    expect(requests.map((u) => u.path).toSet(), {
      '/v1/stops/574',
      '/v1/stops/574/arrivals',
      '/v1/stops/3140/schedule/weekday/8:05',
      '/v1/catalog/stops',
      '/v1/news',
      '/v1/status/gps',
    });
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
