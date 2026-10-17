import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';

/// The stop code does not exist in the STM network.
class StopNotFoundException implements Exception {
  final int stopId;
  const StopNotFoundException(this.stopId);

  @override
  String toString() => 'StopNotFoundException($stopId)';
}

/// Client for the public endpoints used by the official Cómo Ir web app
/// (https://m.montevideo.gub.uy/comoir/). They need no credentials.
///
/// The documented API (api.montevideo.gub.uy/api/transportepublico) requires
/// OAuth2 client credentials and must not ship a secret inside the app —
/// see docs/REVIEW.md for the migration path.
class MvdApiService {
  static const _baseUrl = 'https://api.montevideo.gub.uy/transporteRest';
  static const _nextBusesPath = '/siguientesParada';
  static const _stopLinesPath = '/lineas';

  static const _timeout = Duration(seconds: 10);
  static const _headers = {'Accept': 'application/json'};

  /// Returns upcoming buses for a stop, soonest first.
  /// Returns null on network/server error so callers can tell
  /// "no buses" apart from "could not check".
  static Future<List<BusArrival>?> getNextArrivals(int stopId) async {
    try {
      final uri = Uri.parse('$_baseUrl$_nextBusesPath/$stopId');
      final response =
          await http.get(uri, headers: _headers).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ ETA API ${response.statusCode}: ${response.body}');
        return null;
      }

      return parseArrivals(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('❌ ETA API error: $e');
      return null;
    }
  }

  /// Resolves stop name and lines from a stop ID.
  /// Returns null on network error; throws [StopNotFoundException]
  /// if the server reports that the stop does not exist.
  static Future<BusStop?> resolveStop(int stopId) async {
    final http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$_stopLinesPath/$stopId');
      response = await http.get(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      debugPrint('❌ Lineas API error: $e');
      return null;
    }

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      // The backend answers 500 "No existe la ubicación de parada con código 'N'."
      if (body.contains('No existe')) throw StopNotFoundException(stopId);
      debugPrint('❌ Lineas API ${response.statusCode}: $body');
      return null;
    }

    try {
      return parseStop(stopId, jsonDecode(body));
    } catch (e) {
      debugPrint('⚠️ Parse stop error: $e');
      return null;
    }
  }

  /// Parses `GET /transporteRest/siguientesParada/{id}`:
  /// `[{"linea":"145","minutos":5,"real":true,"destino":"PLAZA ESPAÑA",
  ///    "idEmpresa":50,"horaDesc":"7:39","coordinates":[lng,lat], ...}]`
  @visibleForTesting
  static List<BusArrival> parseArrivals(dynamic data) {
    final arrivals = <BusArrival>[];
    if (data is! List) return arrivals;

    for (final item in data) {
      try {
        if (item is! Map) continue;
        final line = item['linea']?.toString() ?? '';
        final rawMinutes = item['minutos'];
        if (line.isEmpty || rawMinutes == null) continue;

        final etaMinutes = _safeInt(rawMinutes);

        double? lat, lng;
        final coords = item['coordinates'];
        if (coords is List && coords.length >= 2) {
          lng = (coords[0] as num?)?.toDouble();
          lat = (coords[1] as num?)?.toDouble();
        }

        arrivals.add(BusArrival(
          line: line,
          companyCode: _safeInt(item['idEmpresa']),
          etaMinutes: etaMinutes,
          etaSeconds: etaMinutes * 60,
          busLatitude: lat,
          busLongitude: lng,
          destination: item['destino']?.toString() ?? '',
          isRealTime: item['real'] == true,
          scheduledTime: item['horaDesc']?.toString(),
        ));
      } catch (e) {
        debugPrint('⚠️ Parse arrival error: $e');
      }
    }

    arrivals.sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
    return arrivals;
  }

  /// Parses `GET /transporteRest/lineas/{id}`:
  /// `{"descripcion":"AV RAMON ANADOR y TIBURCIO GOMEZ",
  ///   "lineas":[{"descripcion":"140","codigo":56}, ...]}`
  @visibleForTesting
  static BusStop? parseStop(int stopId, dynamic data) {
    if (data is! Map) return null;

    final lines = <String>[];
    final list = data['lineas'];
    if (list is List) {
      for (final l in list) {
        final name = l is Map ? l['descripcion']?.toString() : null;
        if (name != null && name.isNotEmpty && !lines.contains(name)) {
          lines.add(name);
        }
      }
    }

    final description = data['descripcion']?.toString().trim() ?? '';
    return BusStop(
      id: stopId,
      name: description.isNotEmpty ? description : 'Parada $stopId',
      lines: lines,
    );
  }

  /// Safely parse an int from a dynamic value (may be int, String, or null).
  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
