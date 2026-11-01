import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

/// The STM timetable for the trip planner: stops, lines and FIFO routes,
/// decoded from `assets/rutas/horarios.bin` (built by
/// tool/rutas/build_horarios.py, which documents the format).
///
/// Decoded once and never changed. Also holds what [TripPlanner] needs
/// precomputed: the routes through each stop, the footpaths between stops
/// and a grid for the stops near a point.
class TransitData {
  TransitData._({
    required this.builtAt,
    required this.sourceDate,
    required this.mondayCutoff,
    required this.stops,
    required this.lines,
    required this.variantLines,
    required this.routes,
  }) {
    _index();
  }

  static const magic = 'MVDR';
  static const version = 1;

  /// Streets are not straight lines: walking = haversine × [detour].
  static const detour = 1.3;
  static const walkMetresPerMinute = 80;

  /// Transfers on foot between stops at most this far (walking metres).
  static const footpathMaxMetres = 300;

  /// When the asset was built.
  final DateTime builtAt;

  /// The date of IM's schedule file the asset comes from.
  final DateTime sourceDate;

  /// Minutes. On the day after a Sunday, hábil trips that leave before
  /// this do not run: the Sunday night service (the CSV's `*` passes) does.
  final int mondayCutoff;
  final List<TransitStop> stops;

  /// Line names, "121", "D10", "CA1".
  final List<String> lines;

  /// cod_variante → index in [lines].
  final Map<int, int> variantLines;
  final List<TransitRoute> routes;

  late final Map<int, int> _stopById;
  late final Int32List _lastMinute;

  // Routes through each stop: for stop s, entries
  // [_stopRoutesStart[s], _stopRoutesStart[s + 1]) of route and position.
  late final Int32List _stopRoutesStart;
  late final Int32List _stopRoutesRoute;
  late final Int32List _stopRoutesPos;

  // Footpaths from each stop, same layout.
  late final Int32List _footStart;
  late final Int32List _footTo;
  late final Int32List _footMetres;

  // Grid of ~550 m cells: cell key → stop indices.
  late final Map<int, List<int>> _grid;
  late final double _gridLat0;
  late final double _gridLon0;
  static const _cellLat = 0.005;
  static const _cellLon = 0.006;
  static const _gridCols = 1 << 16;
  static const _metresPerDegree = 111320.0;

  /// Decodes the gzipped asset. Throws [FormatException] when it is not
  /// a version [version] timetable.
  static TransitData decode(Uint8List gzipped) {
    final List<int> raw;
    try {
      raw = gzip.decode(gzipped);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('horarios: not gzip ($e)');
    }
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    try {
      return _decode(_Reader(bytes));
    } on RangeError {
      throw const FormatException('horarios: truncated');
    }
  }

  static TransitData _decode(_Reader r) {
    if (String.fromCharCodes(r.bytes(4)) != magic) {
      throw const FormatException('horarios: bad magic');
    }
    final v = r.u16();
    if (v != version) {
      throw FormatException('horarios: version $v, expected $version');
    }
    final builtAt = _date(r.u32());
    final sourceDate = _date(r.u32());
    final mondayCutoff = r.u16();

    final nStops = r.u32();
    final ids = List<int>.generate(nStops, (_) => r.u32());
    final lats = List<int>.generate(nStops, (_) => r.i32());
    final lons = List<int>.generate(nStops, (_) => r.i32());
    final stops = List<TransitStop>.generate(
      nStops,
      (i) => TransitStop(
        id: ids[i],
        name: r.str(),
        lat: lats[i] / 1e6,
        lon: lons[i] / 1e6,
      ),
      growable: false,
    );

    final lines = List<String>.generate(
      r.u16(),
      (_) => r.str(),
      growable: false,
    );

    final nVariants = r.u16();
    final variants = List<int>.generate(nVariants, (_) => r.u32());
    final variantLine = List<int>.generate(nVariants, (_) => r.u16());
    final variantLines = {
      for (var i = 0; i < nVariants; i++) variants[i]: variantLine[i],
    };

    final patterns = List<Int32List>.generate(r.u32(), (_) {
      final n = r.u16();
      final stopsOf = Int32List(n);
      for (var i = 0; i < n; i++) {
        stopsOf[i] = r.u16();
      }
      return stopsOf;
    }, growable: false);

    final routes = List<TransitRoute>.generate(r.u32(), (_) {
      final pattern = patterns[r.u32()];
      final variant = r.u16();
      final offsets = Int32List(pattern.length);
      for (var i = 1; i < pattern.length; i++) {
        offsets[i] = offsets[i - 1] + r.u8();
      }
      final departures = List<Int32List>.generate(DayType.values.length, (_) {
        final deps = Int32List(r.u16());
        for (var i = 0; i < deps.length; i++) {
          deps[i] = (i == 0 ? 0 : deps[i - 1]) + r.u16();
        }
        return deps;
      }, growable: false);
      return TransitRoute(
        variant: variants[variant],
        line: variantLine[variant],
        stops: pattern,
        offsets: offsets,
        departures: departures,
      );
    }, growable: false);
    if (!r.atEnd) throw const FormatException('horarios: trailing bytes');

    return TransitData._(
      builtAt: builtAt,
      sourceDate: sourceDate,
      mondayCutoff: mondayCutoff,
      stops: stops,
      lines: lines,
      variantLines: variantLines,
      routes: routes,
    );
  }

  static DateTime _date(int yyyymmdd) =>
      DateTime(yyyymmdd ~/ 10000, yyyymmdd ~/ 100 % 100, yyyymmdd % 100);

  void _index() {
    _stopById = {for (var i = 0; i < stops.length; i++) stops[i].id: i};

    _lastMinute = Int32List(DayType.values.length);
    for (final route in routes) {
      for (final type in DayType.values) {
        final deps = route.departures[type.index];
        if (deps.isEmpty) continue;
        final last = deps.last + route.offsets.last;
        if (last > _lastMinute[type.index]) _lastMinute[type.index] = last;
      }
    }

    final counts = Int32List(stops.length + 1);
    for (final route in routes) {
      for (final s in route.stops) {
        counts[s + 1]++;
      }
    }
    for (var i = 0; i < stops.length; i++) {
      counts[i + 1] += counts[i];
    }
    _stopRoutesStart = Int32List.fromList(counts);
    _stopRoutesRoute = Int32List(counts[stops.length]);
    _stopRoutesPos = Int32List(counts[stops.length]);
    final fill = Int32List.fromList(counts);
    for (var r = 0; r < routes.length; r++) {
      final routeStops = routes[r].stops;
      for (var p = 0; p < routeStops.length; p++) {
        final at = fill[routeStops[p]]++;
        _stopRoutesRoute[at] = r;
        _stopRoutesPos[at] = p;
      }
    }

    _gridLat0 = stops.fold(90.0, (m, s) => math.min(m, s.lat));
    _gridLon0 = stops.fold(180.0, (m, s) => math.min(m, s.lon));
    _grid = {};
    for (var i = 0; i < stops.length; i++) {
      final key = _cell(stops[i].lat, stops[i].lon);
      (_grid[key] ??= []).add(i);
    }

    final start = Int32List(stops.length + 1);
    final to = <int>[];
    final metres = <int>[];
    for (var i = 0; i < stops.length; i++) {
      for (final near in stopsNear(
        stops[i].lat,
        stops[i].lon,
        footpathMaxMetres,
      )) {
        if (near.stop == i) continue;
        to.add(near.stop);
        metres.add(near.metres);
      }
      start[i + 1] = to.length;
    }
    _footStart = start;
    _footTo = Int32List.fromList(to);
    _footMetres = Int32List.fromList(metres);
  }

  int _row(double lat) => ((lat - _gridLat0) / _cellLat).floor();
  int _col(double lon) => ((lon - _gridLon0) / _cellLon).floor();
  int _cell(double lat, double lon) => _row(lat) * _gridCols + _col(lon);

  /// When the last bus of a [type] service day reaches its last stop, in
  /// minutes from that day's midnight (past 1440: after midnight).
  int lastMinute(DayType type) => _lastMinute[type.index];

  /// Index of the stop with this STM number, or null.
  int? indexOfStop(int id) => _stopById[id];

  /// Stops within [maxMetres] walking metres of the point, nearest first.
  List<({int stop, int metres})> stopsNear(
    double lat,
    double lon,
    int maxMetres,
  ) {
    final radius = maxMetres / detour;
    final dLat = radius / _metresPerDegree;
    final dLon = radius / (_metresPerDegree * math.cos(lat * math.pi / 180));
    final found = <({int stop, int metres})>[];
    for (var row = _row(lat - dLat); row <= _row(lat + dLat); row++) {
      for (var col = _col(lon - dLon); col <= _col(lon + dLon); col++) {
        if (col < 0 || col >= _gridCols) continue;
        final cell = _grid[row * _gridCols + col];
        if (cell == null) continue;
        for (final i in cell) {
          final m = walkMetres(lat, lon, stops[i].lat, stops[i].lon);
          if (m <= maxMetres) found.add((stop: i, metres: m));
        }
      }
    }
    found.sort(
      (a, b) => a.metres != b.metres
          ? a.metres.compareTo(b.metres)
          : a.stop.compareTo(b.stop),
    );
    return found;
  }

  /// Walking metres between two points: haversine × [detour], rounded up.
  static int walkMetres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final metres = 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
    return (metres * detour).ceil();
  }

  /// Whole minutes to walk [metres].
  static int walkMinutes(int metres) =>
      (metres + walkMetresPerMinute - 1) ~/ walkMetresPerMinute;

  /// For [TripPlanner]: routes through [stop] as (route, position) pairs.
  int routesAtStart(int stop) => _stopRoutesStart[stop];
  int routesAtEnd(int stop) => _stopRoutesStart[stop + 1];
  int routeAt(int entry) => _stopRoutesRoute[entry];
  int positionAt(int entry) => _stopRoutesPos[entry];

  /// For [TripPlanner]: footpaths from [stop] (other stops, walking metres).
  int footpathsStart(int stop) => _footStart[stop];
  int footpathsEnd(int stop) => _footStart[stop + 1];
  int footpathTo(int entry) => _footTo[entry];
  int footpathMetres(int entry) => _footMetres[entry];
}

/// tipo_dia of IM's schedule. No holiday calendar: by weekday only.
enum DayType {
  habil,
  sabado,
  domingo;

  static DayType of(DateTime day) => switch (day.weekday) {
    DateTime.saturday => sabado,
    DateTime.sunday => domingo,
    _ => habil,
  };
}

class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  /// STM stop number (cod_ubic_parada).
  final int id;

  /// "{calle} y {esquina}" as IM writes them: "SAN JOSE y ANDES".
  final String name;
  final double lat;
  final double lon;
}

/// Trips of one variant with the same stops and the same minutes between
/// them: no trip overtakes another (FIFO).
class TransitRoute {
  const TransitRoute({
    required this.variant,
    required this.line,
    required this.stops,
    required this.offsets,
    required this.departures,
  });

  /// cod_variante.
  final int variant;

  /// Index in TransitData.lines.
  final int line;

  /// Indices in TransitData.stops, in order (routes of one variant may
  /// share the list).
  final Int32List stops;

  /// Minutes from the first stop to each stop; offsets[0] == 0.
  final Int32List offsets;

  /// By [DayType.index]: departures from the first stop, ascending, in
  /// minutes from the service day's midnight. Above 1440 the trip left
  /// that day and runs after midnight.
  final List<Int32List> departures;
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  bool get atEnd => _at == _bytes.length;

  int u8() => _data.getUint8(_at++);

  int u16() {
    final v = _data.getUint16(_at, Endian.little);
    _at += 2;
    return v;
  }

  int u32() {
    final v = _data.getUint32(_at, Endian.little);
    _at += 4;
    return v;
  }

  int i32() {
    final v = _data.getInt32(_at, Endian.little);
    _at += 4;
    return v;
  }

  Uint8List bytes(int n) {
    if (_at + n > _bytes.length) throw RangeError('truncated');
    final v = Uint8List.sublistView(_bytes, _at, _at + n);
    _at += n;
    return v;
  }

  String str() => utf8.decode(bytes(u8()));
}
