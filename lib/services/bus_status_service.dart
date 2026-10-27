import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/gps_status.dart';
import 'api/direct/pci_adapter.dart';
import 'api/v1_parser.dart';

export '../models/gps_status.dart';

/// GPS data quality per operator — the open endpoint Cómo Ir reads
/// (`pci.montevideo.gub.uy/buses/control`), no credentials.
/// Explains why some ETAs fall back to the timetable.
class BusStatusService {
  static const _timeout = Duration(seconds: 10);
  static const _headers = {'Accept': 'application/json'};

  /// Requests (successful or not) are at least this far apart.
  static const minInterval = Duration(seconds: 60);

  static List<OperatorGpsStatus>? _cached;
  static DateTime? _lastAttempt;

  /// Latest status, from memory if fetched less than [minInterval] ago.
  /// Null if it has never been fetched successfully.
  static Future<List<OperatorGpsStatus>?> getStatus() async {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return _cached;
    }
    _lastAttempt = DateTime.now();

    try {
      final response = await http
          .get(Uri.parse(PciAdapter.url), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('❌ GPS status ${response.statusCode}: ${response.body}');
        return _cached;
      }
      return _cached = parse(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('❌ GPS status error: $e');
      return _cached;
    }
  }

  /// Sets the status as if just fetched (no request for [minInterval]).
  @visibleForTesting
  static void seed(List<OperatorGpsStatus> status) {
    _cached = status;
    _lastAttempt = DateTime.now();
  }

  /// Parses `[{"empresa":"CUTCSA","valor":100}, …]` through the direct-mode
  /// adapter and V1Parser; values are clamped to 0–100 as Cómo Ir does.
  @visibleForTesting
  static List<OperatorGpsStatus> parse(dynamic data) =>
      V1Parser.gpsStatus(
          PciAdapter.controlToV1(data, fetchedAt: DateTime.now())) ??
      [];

  /// "Datos GPS parciales" text, or null when every operator is fine.
  static String? partialWarning(List<OperatorGpsStatus>? status) {
    final partial = status?.where((s) => s.isPartial).toList() ?? const [];
    if (partial.isEmpty) return null;
    final detail = partial.map((s) => '${s.company} ${s.percent} %').join(', ');
    return 'Datos GPS parciales ($detail): algunos tiempos pueden ser '
        'horarios teóricos o menos precisos.';
  }
}
