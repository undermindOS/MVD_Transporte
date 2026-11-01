import 'package:flutter/foundation.dart';
import '../models/gps_status.dart';
import 'api/direct/pci_adapter.dart';
import 'api/v1_parser.dart';
import 'mvd_api_service.dart';

export '../models/gps_status.dart';

/// GPS data quality per operator — through the proxy (`/v1/status/gps`) or,
/// without it, the open endpoint Cómo Ir reads
/// (`pci.montevideo.gub.uy/buses/control`), no credentials.
/// Explains why some ETAs fall back to the timetable.
class BusStatusService {
  /// Requests (successful or not) are at least this far apart.
  static const minInterval = Duration(seconds: 60);

  static List<OperatorGpsStatus>? _cached;
  static DateTime? _lastAttempt;

  /// Latest status, from memory if fetched less than [minInterval] ago.
  /// Null if it has never been fetched successfully; after a failure the
  /// last good status.
  static Future<List<OperatorGpsStatus>?> getStatus() async {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return _cached;
    }
    _lastAttempt = DateTime.now();

    final status = (await MvdApiService.getGpsStatus()).valueOrNull;
    if (status != null) _cached = status;
    return _cached;
  }

  /// Sets the status as if fetched [at] (default now: no request for
  /// [minInterval]).
  @visibleForTesting
  static void seed(List<OperatorGpsStatus> status, {DateTime? at}) {
    _cached = status;
    _lastAttempt = at ?? DateTime.now();
  }

  /// Forgets the status and the last request, as at app start.
  @visibleForTesting
  static void reset() {
    _cached = null;
    _lastAttempt = null;
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
