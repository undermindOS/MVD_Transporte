import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/nearby_stop.dart';

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

/// Stops around the user from the open WFS layer `imm:v_uptu_paradas` of the
/// Intendencia de Montevideo GeoServer (no credentials).
///
/// Each feature is one "stop × line variant"; features are grouped by
/// `cod_ubic_parada`, the stop number transporteRest and Cómo Ir use.
class NearbyStopsService {
  static const _wfsUrl = 'https://geoserver.montevideo.gub.uy/geoserver/ows';
  static const radiusMeters = 400.0;

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

  /// The only way back after "Don't ask again".
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

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

  /// Returns null on network/server error.
  static Future<List<NearbyStop>?> fetchNearby(double lat, double lng,
      {double radius = radiusMeters}) async {
    try {
      final response = await http.get(buildUri(lat, lng, radius),
          headers: const {'Accept': 'application/json'}).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ WFS ${response.statusCode}: ${response.body}');
        return null;
      }

      return parseFeatures(jsonDecode(utf8.decode(response.bodyBytes)),
          lat: lat, lng: lng, radius: radius);
    } catch (e) {
      debugPrint('❌ WFS error: $e');
      return null;
    }
  }

  /// GetFeature for the box around the point. With the `EPSG:4326` suffix
  /// this GeoServer reads the BBOX as lon,lat (lat,lon silently returns no
  /// features); the GeoJSON coordinates come back as [lon, lat] too.
  @visibleForTesting
  static Uri buildUri(double lat, double lng, double radius) {
    final dLat = radius / _metersPerDegree;
    final dLng = radius / (_metersPerDegree * math.cos(_toRadians(lat)));
    String f(double v) => v.toStringAsFixed(6);

    return Uri.parse(_wfsUrl).replace(queryParameters: {
      'service': 'wfs',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typename': 'imm:v_uptu_paradas',
      'outputFormat': 'application/json',
      'srsName': 'EPSG:4326',
      'propertyName': 'cod_ubic_parada,desc_linea,calle,esquina,the_geom',
      'bbox': '${f(lng - dLng)},${f(lat - dLat)},'
          '${f(lng + dLng)},${f(lat + dLat)},EPSG:4326',
    });
  }

  /// Parses the GeoJSON FeatureCollection:
  /// `{"features":[{"geometry":{"type":"Point","coordinates":[lon,lat]},
  ///   "properties":{"cod_ubic_parada":574,"desc_linea":"116",
  ///   "calle":"SAN JOSE","esquina":"ANDES"}}, ...]}`
  /// Groups the per-variant features by stop, drops the BBOX corners beyond
  /// [radius] and sorts nearest first.
  @visibleForTesting
  static List<NearbyStop> parseFeatures(dynamic data,
      {required double lat,
      required double lng,
      double radius = radiusMeters}) {
    if (data is! Map || data['features'] is! List) return [];

    final byId = <int, _StopBuilder>{};
    for (final feature in data['features'] as List) {
      if (feature is! Map) continue;
      final props = feature['properties'];
      final geometry = feature['geometry'];
      if (props is! Map || geometry is! Map) continue;

      final id = props['cod_ubic_parada'];
      final coords = geometry['coordinates'];
      if (id is! num || coords is! List || coords.length < 2) continue;
      final lon = coords[0], la = coords[1];
      if (lon is! num || la is! num) continue;

      final stop = byId.putIfAbsent(
        id.toInt(),
        () => _StopBuilder(
          id: id.toInt(),
          name: _stopName(id.toInt(), props['calle'], props['esquina']),
          latitude: la.toDouble(),
          longitude: lon.toDouble(),
        ),
      );
      final line = props['desc_linea']?.toString().trim() ?? '';
      if (line.isNotEmpty) stop.lines.add(line);
    }

    final stops = <NearbyStop>[];
    for (final s in byId.values) {
      final distance = distanceMeters(lat, lng, s.latitude, s.longitude);
      if (distance > radius) continue;
      stops.add(NearbyStop(
        id: s.id,
        name: s.name,
        lines: s.lines.toList()..sort(compareLines),
        latitude: s.latitude,
        longitude: s.longitude,
        distanceMeters: distance,
      ));
    }
    stops.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return stops;
  }

  static String _stopName(int id, dynamic street, dynamic corner) {
    final s = street?.toString().trim() ?? '';
    final c = corner?.toString().trim() ?? '';
    if (s.isEmpty && c.isEmpty) return 'Parada $id';
    if (s.isEmpty || c.isEmpty) return s.isEmpty ? c : s;
    return '$s y $c';
  }

  static final _leadingNumber = RegExp(r'^\d+');

  /// Numeric lines by value ("21" < "104"), suffixed variants next to their
  /// number ("124" < "124 SD" < "125"), then lettered lines ("CE1", "D10").
  @visibleForTesting
  static int compareLines(String a, String b) {
    final na = int.tryParse(_leadingNumber.stringMatch(a) ?? '');
    final nb = int.tryParse(_leadingNumber.stringMatch(b) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if ((na == null) != (nb == null)) return na == null ? 1 : -1;
    return a.compareTo(b);
  }

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

class _StopBuilder {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final Set<String> lines = {};

  _StopBuilder({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}
