import '../../models/arrivals_board.dart';
import '../../models/bus_arrival.dart';
import '../../models/catalog_stop.dart';
import '../../models/gps_status.dart';
import '../../models/scheduled_pass.dart';
import '../../models/stop_details.dart';
import '../../models/transport_news.dart';

/// The catalog of stops (/v1 `CatalogStopsResponse`).
typedef StopCatalog = ({
  DateTime fetchedAt,
  bool linesAvailable,
  List<CatalogStop> stops,
});

/// The news of the last page reached (/v1 `NewsResponse`).
typedef NewsList = ({DateTime fetchedAt, List<TransportNews> news});

/// Reads /v1 JSON into models: the one reader of each shape, whether the
/// JSON came from the proxy or from a direct-mode adapter.
///
/// Tolerant, as docs/design/contrato-v1.md asks of the consumer: unknown
/// keys are ignored, a missing `fetchedAt` is now, missing `directions`,
/// `lines` or `linesAvailable` are empty or false, and an item without a
/// required field is skipped. A body of the wrong shape gives null — a
/// failure, never an empty list.
abstract final class V1Parser {
  /// `GET /v1/stops/{id}`. [id] is the requested stop.
  static StopDetails? stop(Object? json, int id) {
    if (json is! Map) return null;
    final name = json['name'];
    return StopDetails(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      lines: _texts(json['lines']),
      directions: [
        for (final d in _list(json['directions']))
          if (d is Map &&
              d['line'] is String &&
              d['destination'] is String &&
              d['variantIds'] is List)
            StopDirection(
              line: d['line'] as String,
              destination: d['destination'] as String,
              variantIds: [
                for (final v in d['variantIds'] as List)
                  if (v is int) v,
              ],
            ),
      ],
    );
  }

  /// `GET /v1/stops/{id}/arrivals`, in the order given (soonest first).
  /// [stopId] is the requested stop; [now] stands in for a missing
  /// `fetchedAt`.
  static ArrivalsBoard? arrivals(Object? json, int stopId, {DateTime? now}) {
    if (json is! Map || json['arrivals'] is! List) return null;
    return ArrivalsBoard(
      stopId: stopId,
      fetchedAt: _fetchedAt(json, now),
      arrivals: (json['arrivals'] as List).map(_arrival).nonNulls.toList(),
    );
  }

  static BusArrival? _arrival(Object? item) {
    if (item is! Map) return null;
    final tripId = item['tripId'];
    final line = item['line'];
    final state = ArrivalState.values.asNameMap()[item['state']];
    final eta = item['etaMinutes'];
    final expectedAt = _date(item['expectedAt']);
    final clockTime = item['clockTime'];
    if (tripId is! String ||
        line is! String ||
        line.isEmpty ||
        state == null ||
        eta is! num ||
        expectedAt == null ||
        clockTime is! String) {
      return null;
    }
    final variant = item['variantId'];
    final destination = item['destination'];
    return BusArrival(
      tripId: tripId,
      variantId: variant is int ? variant : null,
      line: line,
      destination: destination is String ? destination : '',
      state: state,
      etaMinutes: eta.toInt(),
      expectedAt: expectedAt,
      clockTime: clockTime,
      accessible: item['accessible'] == true,
      airConditioning: _bool(item['airConditioning']),
      zeroEmission: _bool(item['zeroEmission']),
    );
  }

  /// `GET /v1/stops/{id}/schedule/{day}/{H:MM}`, in the order given
  /// (chronological, wrapping past midnight).
  static List<ScheduledPass>? schedule(Object? json) {
    if (json is! Map || json['passes'] is! List) return null;
    return [
      for (final p in json['passes'] as List)
        if (p is Map &&
            p['line'] is String &&
            (p['line'] as String).isNotEmpty &&
            p['time'] is String &&
            (p['time'] as String).isNotEmpty &&
            p['hhmm'] is num)
          ScheduledPass(
            line: p['line'] as String,
            destination:
                p['destination'] is String ? p['destination'] as String : '',
            time: p['time'] as String,
            hhmm: (p['hhmm'] as num).toInt(),
          ),
    ];
  }

  /// `GET /v1/catalog/stops`. A stop without a location is skipped.
  static StopCatalog? catalog(Object? json, {DateTime? now}) {
    if (json is! Map || json['stops'] is! List) return null;
    final stops = <CatalogStop>[];
    for (final s in json['stops'] as List) {
      if (s is! Map || s['id'] is! int) continue;
      final location = s['location'];
      if (location is! Map) continue;
      final lat = location['lat'], lng = location['lng'];
      if (lat is! num || lng is! num) continue;
      final name = s['name'];
      stops.add(CatalogStop.fromSource(
        id: s['id'] as int,
        name: name is String ? name : null,
        lines: _texts(s['lines']),
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
      ));
    }
    return (
      fetchedAt: _fetchedAt(json, now),
      linesAvailable: json['linesAvailable'] == true,
      stops: stops,
    );
  }

  /// `GET /v1/news`, in the order given (newest first).
  static NewsList? news(Object? json, {DateTime? now}) {
    if (json is! Map || json['news'] is! List) return null;
    return (
      fetchedAt: _fetchedAt(json, now),
      news: (json['news'] as List).map(TransportNews.fromV1).nonNulls.toList(),
    );
  }

  /// `GET /v1/status/gps`, in the order given.
  static List<OperatorGpsStatus>? gpsStatus(Object? json) {
    if (json is! Map || json['operators'] is! List) return null;
    return [
      for (final o in json['operators'] as List)
        if (o is Map &&
            o['company'] is String &&
            (o['company'] as String).isNotEmpty &&
            o['percent'] is num)
          OperatorGpsStatus(
            o['company'] as String,
            (o['percent'] as num).toInt(),
            partial: _bool(o['partial']),
          ),
    ];
  }

  static DateTime _fetchedAt(Map json, DateTime? now) =>
      _date(json['fetchedAt']) ?? (now ?? DateTime.now()).toUtc();

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static List<Object?> _list(Object? value) =>
      value is List ? value : const [];

  static List<String> _texts(Object? value) => [
        for (final v in _list(value))
          if (v is String && v.isNotEmpty) v,
      ];

  static bool? _bool(Object? value) => value is bool ? value : null;
}
