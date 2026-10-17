import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Share of an operator's buses whose GPS data is reaching the system.
class OperatorGpsStatus {
  /// Below this Cómo Ir stops showing the operator as OK.
  static const partialThreshold = 70;

  final String company;

  /// 0–100.
  final int percent;

  const OperatorGpsStatus(this.company, this.percent);

  bool get isPartial => percent < partialThreshold;
}

/// GPS data quality per operator — the open endpoint Cómo Ir reads
/// (`pci.montevideo.gub.uy/buses/control`), no credentials.
/// Explains why some ETAs fall back to the timetable.
class BusStatusService {
  static const _url = 'https://pci.montevideo.gub.uy/buses/control';
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
          .get(Uri.parse(_url), headers: _headers)
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

  /// Parses `[{"empresa":"CUTCSA","valor":100}, …]`; values are clamped
  /// to 0–100 as Cómo Ir does.
  @visibleForTesting
  static List<OperatorGpsStatus> parse(dynamic data) {
    final list = <OperatorGpsStatus>[];
    if (data is! List) return list;
    for (final item in data) {
      if (item is! Map) continue;
      final company = item['empresa']?.toString().trim() ?? '';
      final value = item['valor'];
      if (company.isEmpty || value is! num) continue;
      list.add(OperatorGpsStatus(company, value.round().clamp(0, 100)));
    }
    return list;
  }

  /// "Datos GPS parciales" text, or null when every operator is fine.
  static String? partialWarning(List<OperatorGpsStatus>? status) {
    final partial = status?.where((s) => s.isPartial).toList() ?? const [];
    if (partial.isEmpty) return null;
    final detail = partial.map((s) => '${s.company} ${s.percent} %').join(', ');
    return 'Datos GPS parciales ($detail): algunos tiempos pueden ser '
        'horarios teóricos o menos precisos.';
  }
}
