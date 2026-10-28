import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/catalog_stop.dart';
import '../models/nearby_stop.dart';
import 'api/contract_rules.dart';
import 'api/direct/wfs_adapter.dart';
import 'api/v1_parser.dart';
import 'external_apps.dart';
import 'mvd_api_service.dart';

/// Why the nearby-stops search could not run; the UI picks the message.
enum NearbyStopsError {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  locationUnavailable,
  network,
}

class NearbyStopsException implements Exception {
  final NearbyStopsError error;
  const NearbyStopsException(this.error);

  @override
  String toString() => 'NearbyStopsException($error)';
}

/// Stops around the user.
///
/// Through the proxy they come from the stop catalog kept on the phone
/// ([MvdApiService.getStopCatalog]): the position never leaves the device.
/// Without it, from the open WFS layer `imm:v_uptu_paradas` of the
/// Intendencia de Montevideo GeoServer (no credentials), asked for a box
/// around the position rounded to 3 decimals — an approximate area — and
/// filtered by the exact position on the phone.
class NearbyStopsService {
  static const _wfsUrl = 'https://geoserver.montevideo.gub.uy/geoserver/ows';
  static const radiusMeters = 400.0;

  /// Half-side of the WFS box: [radiusMeters] plus 72 m, half the diagonal
  /// of a 0.001° cell, so the box around the rounded position holds the
  /// whole circle around the exact one.
  static const boxHalfSideMeters = radiusMeters + 72;

  static const _timeout = Duration(seconds: 15);
  static const _locationTimeout = Duration(seconds: 15);
  static const _metersPerDegree = 111320.0;
  static const _earthRadiusMeters = 6371000.0;

  /// Asks for location permission (when the user taps "Paradas cercanas"),
  /// gets the position and returns stops within [radiusMeters], nearest first.
  /// Throws [NearbyStopsException].
  static Future<List<NearbyStop>> findNearMe() async {
    final position = await _currentPosition();
    final stops = await fetchNearby(position.latitude, position.longitude);
    if (stops == null) {
      throw const NearbyStopsException(NearbyStopsError.network);
    }
    return stops;
  }

  /// The only way back after "Don't ask again". The settings are another
  /// app, opened from here: coming back from them does not lock.
  static Future<bool> openAppSettings() =>
      ExternalApps.open(Geolocator.openAppSettings);

  static Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const NearbyStopsException(NearbyStopsError.serviceDisabled);
    }

    // geolocator's own request works on iOS too; permission_handler there
    // needs the PERMISSION_LOCATION Podfile macro, which is not set.
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const NearbyStopsException(
          NearbyStopsError.permissionDeniedForever);
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const NearbyStopsException(NearbyStopsError.permissionDenied);
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _locationTimeout,
        ),
      );
    } on TimeoutException {
      // No fix indoors — a recent position is good enough for 400 m
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (e) {
      debugPrint('❌ Location error: $e');
    }
    throw const NearbyStopsException(NearbyStopsError.locationUnavailable);
  }

  /// Stops within [radiusMeters] of the point, nearest first.
  /// Returns null on network/server error.
  static Future<List<NearbyStop>?> fetchNearby(double lat, double lng) async {
    final catalog = MvdApiService.usesProxy
        ? await MvdApiService.getStopCatalog()
        : await _stopsInBox(lat, lng);
    return catalog == null ? null : nearbyFrom(catalog, lat, lng);
  }

  /// Direct mode: the stops of the WFS box around the point.
  static Future<List<CatalogStop>?> _stopsInBox(double lat, double lng) =>
      _getStops(buildUri(lat, lng));

  /// Direct mode only: the stop numbered [stopId], asked by its number with
  /// no position at all, to place a saved stop on the Mapa. Null when
  /// geoserver does not know it or cannot be reached. Never through the
  /// proxy: a proxy build asks no city host.
  static Future<CatalogStop?> fetchStop(int stopId) async {
    if (MvdApiService.usesProxy) return null;
    final stops = await _getStops(buildStopUri(stopId));
    return stops?.where((s) => s.id == stopId).firstOrNull;
  }

  /// A WFS GetFeature as catalog stops; null on network/server error.
  static Future<List<CatalogStop>?> _getStops(Uri uri) async {
    try {
      final response = await http.get(uri,
          headers: const {'Accept': 'application/json'}).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ WFS ${response.statusCode}');
        return null;
      }

      final items = WfsAdapter.featuresToCatalogItems(
          jsonDecode(utf8.decode(response.bodyBytes)));
      return items == null ? null : V1Parser.catalog({'stops': items})?.stops;
    } catch (e) {
      // Not the error text: it can hold the URL, and so the box or the
      // stop number
      debugPrint('❌ WFS error: ${e.runtimeType}');
      return null;
    }
  }

  /// GetFeature for the box of half-side [boxHalfSideMeters] around the
  /// point rounded to 3 decimals. With the `EPSG:4326` suffix this
  /// GeoServer reads the BBOX as lon,lat (lat,lon silently returns no
  /// features); the GeoJSON coordinates come back as [lon, lat] too.
  @visibleForTesting
  static Uri buildUri(double lat, double lng) {
    double rounded(double v) => (v * 1000).round() / 1000;
    final centerLat = rounded(lat), centerLng = rounded(lng);
    final dLat = boxHalfSideMeters / _metersPerDegree;
    final dLng = boxHalfSideMeters /
        (_metersPerDegree * math.cos(_toRadians(centerLat)));
    String f(double v) => v.toStringAsFixed(6);

    return Uri.parse(_wfsUrl).replace(queryParameters: {
      'service': 'wfs',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typename': 'imm:v_uptu_paradas',
      'outputFormat': 'application/json',
      'srsName': 'EPSG:4326',
      'propertyName': 'cod_ubic_parada,desc_linea,calle,esquina,the_geom',
      'bbox': '${f(centerLng - dLng)},${f(centerLat - dLat)},'
          '${f(centerLng + dLng)},${f(centerLat + dLat)},EPSG:4326',
    });
  }

  /// GetFeature for one stop by its number (`CQL_FILTER`, a GeoServer
  /// extension): no BBOX and no position. One feature is enough, as the
  /// "stop × variant" features of a stop share one point (so in every
  /// capture), and only the number and the point are asked for, to keep
  /// the answer small.
  @visibleForTesting
  static Uri buildStopUri(int stopId) =>
      Uri.parse(_wfsUrl).replace(queryParameters: {
        'service': 'wfs',
        'version': '2.0.0',
        'request': 'GetFeature',
        'typename': 'imm:v_uptu_paradas',
        'outputFormat': 'application/json',
        'srsName': 'EPSG:4326',
        'propertyName': 'cod_ubic_parada,the_geom',
        'CQL_FILTER': 'cod_ubic_parada=$stopId',
        'count': '1',
      });

  /// The stops of [catalog] within [radius] of the point, nearest first —
  /// the proxy's catalog and the WFS box alike.
  static List<NearbyStop> nearbyFrom(
      List<CatalogStop> catalog, double lat, double lng,
      {double radius = radiusMeters}) {
    final stops = <NearbyStop>[];
    for (final s in catalog) {
      final distance = distanceMeters(lat, lng, s.latitude, s.longitude);
      if (distance > radius) continue;
      stops.add(NearbyStop(
        id: s.id,
        name: s.name,
        lines: s.lines,
        latitude: s.latitude,
        longitude: s.longitude,
        distanceMeters: distance,
      ));
    }
    stops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return stops;
  }

  /// Numeric lines by value ("21" < "104"), suffixed variants next to their
  /// number ("124" < "124 SD" < "125"), then lettered lines ("CE1", "D10").
  @visibleForTesting
  static int compareLines(String a, String b) =>
      ContractRules.compareLines(a, b);

  /// Great-circle distance (haversine).
  @visibleForTesting
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.sqrt(h));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
