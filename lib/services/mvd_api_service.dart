import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';

class MvdApiService {
  static const _baseUrl = 'https://m.montevideo.gub.uy';
  static const _etaPath = '/stmonlineRest/nextETA';
  static const _variantesPath = '/transporteRest/variantes';

  static const _timeout = Duration(seconds: 10);

  /// Returns ETA list for a given stop ID.
  /// On network error returns empty list (graceful degradation).
  static Future<List<BusArrival>> getNextArrivals(int stopId) async {
    try {
      final uri = Uri.parse('$_baseUrl$_etaPath');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'parada': stopId}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ ETA API ${response.statusCode}: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body);
      return _parseArrivals(data);
    } catch (e) {
      debugPrint('❌ ETA API error: $e');
      return [];
    }
  }

  /// Resolves stop name and lines from a stop ID.
  static Future<BusStop?> resolveStop(int stopId) async {
    try {
      final uri = Uri.parse('$_baseUrl$_variantesPath/$stopId');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      return _parseStop(stopId, data);
    } catch (e) {
      debugPrint('❌ Variantes API error: $e');
      return null;
    }
  }

  static List<BusArrival> _parseArrivals(dynamic data) {
    final arrivals = <BusArrival>[];

    // Response is a GeoJSON FeatureCollection
    if (data is! Map || data['features'] is! List) return arrivals;

    for (final feature in data['features'] as List) {
      try {
        final props = feature['properties'] as Map<String, dynamic>?;
        final coords = feature['geometry']?['coordinates'];
        if (props == null) continue;

        // ETA may come as seconds or milliseconds depending on API version
        final rawEta = props['eta'] ?? props['tiempo'] ?? props['segundos'];
        if (rawEta == null) continue;

        final etaSeconds = (rawEta is num) ? rawEta.toInt() : 0;
        final etaMinutes = (etaSeconds / 60).floor();

        final line = (props['linea'] ?? props['line'] ?? '').toString();
        final company = _safeInt(props['empresa'] ?? props['company']);

        double? lat, lng;
        if (coords is List && coords.length >= 2) {
          lng = (coords[0] as num?)?.toDouble();
          lat = (coords[1] as num?)?.toDouble();
        }

        arrivals.add(BusArrival(
          line: line,
          companyCode: company,
          etaMinutes: etaMinutes,
          etaSeconds: etaSeconds,
          busLatitude: lat,
          busLongitude: lng,
        ));
      } catch (e) {
        debugPrint('⚠️ Parse arrival feature error: $e');
      }
    }

    arrivals.sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
    return arrivals;
  }

  static BusStop? _parseStop(int stopId, dynamic data) {
    try {
      // The variantes endpoint returns a list of route variants at the stop
      final lines = <String>[];

      if (data is List) {
        for (final v in data) {
          final linea = v['linea']?.toString() ?? v['nombre']?.toString();
          if (linea != null && !lines.contains(linea)) {
            lines.add(linea);
          }
        }
      } else if (data is Map) {
        // Some versions wrap in a map
        final list = data['variantes'] ?? data['results'] ?? [];
        if (list is List) {
          for (final v in list) {
            final linea = v['linea']?.toString();
            if (linea != null && !lines.contains(linea)) {
              lines.add(linea);
            }
          }
        }
      }

      // Build a readable stop name; the API may not return one directly
      final name = 'Parada $stopId';

      return BusStop(
        id: stopId,
        name: name,
        lines: lines,
      );
    } catch (e) {
      debugPrint('⚠️ Parse stop error: $e');
      return null;
    }
  }

  /// Safely parse an int from a dynamic value (may be int, String, or null).
  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
