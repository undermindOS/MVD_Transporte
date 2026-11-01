// Small timetables for the planner tests, written in the horarios.bin
// format (tool/rutas/build_horarios.py documents it) and decoded with the
// real TransitData.decode. Stops are placed in metres east and north of a
// point in Montevideo.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:stm_app/services/rutas/itinerary.dart';
import 'package:stm_app/services/rutas/transit_data.dart';

class SyntheticNetwork {
  SyntheticNetwork({this.mondayCutoff = 240});

  static const _lat0 = -34.90, _lon0 = -56.18;

  final int mondayCutoff;
  final _stops = <({int id, String name, GeoPoint at})>[];
  final _routes =
      <
        ({
          int variant,
          String line,
          List<int> stops,
          List<int> offsets,
          List<List<int>> departures,
        })
      >[];

  /// The point [east] and [north] metres from the origin.
  static GeoPoint at(double east, double north) => (
    lat: _lat0 + north / 111320,
    lon: _lon0 + east / (111320 * math.cos(_lat0 * math.pi / 180)),
  );

  /// Adds a stop; returns its index. STM numbers are 1001, 1002…
  int stop(double east, double north) {
    final id = 1001 + _stops.length;
    _stops.add((id: id, name: 'PARADA $id', at: at(east, north)));
    return _stops.length - 1;
  }

  /// A route of [line]: [stops] with [offsets] minutes from the first, and
  /// departures from the first stop per day type.
  void route(
    String line,
    List<int> stops,
    List<int> offsets, {
    List<int> habil = const [],
    List<int> sabado = const [],
    List<int> domingo = const [],
  }) {
    _routes.add((
      variant: 100 + _routes.length,
      line: line,
      stops: stops,
      offsets: offsets,
      departures: [habil, sabado, domingo],
    ));
  }

  TransitData build() {
    final b = BytesBuilder();
    final bd = ByteData(4);
    void u8(int v) => b.addByte(v);
    void u16(int v) {
      bd.setUint16(0, v, Endian.little);
      b.add(bd.buffer.asUint8List(0, 2));
    }

    void u32(int v) {
      bd.setUint32(0, v, Endian.little);
      b.add(bd.buffer.asUint8List(0, 4));
    }

    void i32(int v) {
      bd.setInt32(0, v, Endian.little);
      b.add(bd.buffer.asUint8List(0, 4));
    }

    void str(String s) {
      final bytes = s.codeUnits;
      u8(bytes.length);
      b.add(bytes);
    }

    b.add('MVDR'.codeUnits);
    u16(TransitData.version);
    u32(20261101);
    u32(20261031);
    u16(mondayCutoff);

    u32(_stops.length);
    for (final s in _stops) {
      u32(s.id);
    }
    for (final s in _stops) {
      i32((s.at.lat * 1e6).round());
    }
    for (final s in _stops) {
      i32((s.at.lon * 1e6).round());
    }
    for (final s in _stops) {
      str(s.name);
    }

    final lines = {for (final r in _routes) r.line}.toList();
    u16(lines.length);
    lines.forEach(str);

    u16(_routes.length); // one variant per route
    for (final r in _routes) {
      u32(r.variant);
    }
    for (final r in _routes) {
      u16(lines.indexOf(r.line));
    }

    u32(_routes.length); // one pattern per route
    for (final r in _routes) {
      u16(r.stops.length);
      r.stops.forEach(u16);
    }

    u32(_routes.length);
    for (var i = 0; i < _routes.length; i++) {
      final r = _routes[i];
      u32(i);
      u16(i);
      for (var p = 1; p < r.offsets.length; p++) {
        u8(r.offsets[p] - r.offsets[p - 1]);
      }
      for (final deps in r.departures) {
        u16(deps.length);
        for (var d = 0; d < deps.length; d++) {
          u16(deps[d] - (d == 0 ? 0 : deps[d - 1]));
        }
      }
    }
    return TransitData.decode(Uint8List.fromList(gzip.encode(b.toBytes())));
  }
}

/// Minutes from midnight: hm(8, 5) == 485.
int hm(int h, int m) => h * 60 + m;
