// The committed assets/rutas/horarios.bin, decoded and planned on: a weekday
// afternoon from Pocitos to Ciudad Vieja. Prints the options and how long
// decoding and planning take on this machine (the app does both in a worker
// isolate). Reads the real file and never skips.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/rutas/itinerary.dart';
import 'package:stm_app/services/rutas/transit_data.dart';
import 'package:stm_app/services/rutas/trip_planner.dart';

const _pocitos = (lat: -34.9118, lon: -56.1530);
const _ciudadVieja = (lat: -34.9067, lon: -56.2037);
final _wednesday14 = DateTime(2026, 11, 4, 14, 0);

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _describe(Itinerary o) => [
  '${_hm(o.start)}→${_hm(o.end)} (${o.duration.inMinutes} min, '
      '${o.rides} ómnibus, '
      '${o.walkMetres} m a pie)',
  for (final leg in o.legs)
    switch (leg) {
      WalkLeg w =>
        '  a pie ${w.metres} m, ${w.minutes} min'
            '${w.toStopId == null ? '' : ' hasta la parada ${w.toStopId}'}',
      RideLeg r =>
        '  ${r.line} (variante ${r.variant}) ${_hm(r.departure)} '
            '${r.boardStop.name} [${r.boardStop.id}] → ${_hm(r.arrival)} '
            '${r.alightStop.name} [${r.alightStop.id}], '
            '${r.stops.length - 1} paradas',
    },
].join('\n');

void main() {
  final bytes = File('assets/rutas/horarios.bin').readAsBytesSync();

  test('decodes the bundled timetable', () {
    final data = TransitData.decode(bytes);
    expect(data.stops.length, greaterThan(4000));
    expect(data.routes.length, greaterThan(5000));
    expect(data.lines, containsAll(['121', 'D10', 'CE1', '104']));
    expect(
      data.sourceDate.isBefore(data.builtAt.add(const Duration(days: 1))),
      isTrue,
    );
    // Every stop is in Montevideo's metropolitan area
    for (final s in data.stops) {
      expect(s.lat, inInclusiveRange(-35.0, -34.6));
      expect(s.lon, inInclusiveRange(-56.6, -55.8));
    }
  });

  test('Pocitos → Ciudad Vieja on a weekday at 14:00', () {
    final watch = Stopwatch()..start();
    final data = TransitData.decode(bytes);
    final decodeMs = watch.elapsedMilliseconds;
    final planner = TripPlanner(data);
    watch.reset();
    final options = planner.plan(
      from: _pocitos,
      to: _ciudadVieja,
      departAt: _wednesday14,
    );
    final planMs = watch.elapsedMilliseconds;
    watch.reset();
    planner.plan(from: _pocitos, to: _ciudadVieja, departAt: _wednesday14);
    final warmMs = watch.elapsedMilliseconds;

    // ignore: avoid_print
    print(
      'decode $decodeMs ms, first plan $planMs ms, again $warmMs ms '
      '(${bytes.length} bytes, ${data.stops.length} stops, '
      '${data.routes.length} routes, source ${data.sourceDate})',
    );
    for (final o in options) {
      // ignore: avoid_print
      print(_describe(o));
    }

    expect(options.length, greaterThanOrEqualTo(2));
    for (final o in options) {
      expect(o.walkOnly, isFalse); // 4.6 km: too far on foot
      expect(o.end.difference(_wednesday14).inMinutes, lessThan(75));
      expect(o.start.isBefore(_wednesday14), isFalse);
      expect(o.rides, inInclusiveRange(1, 3));
      _expectWalkLimit(o, 10);
      var t = o.start;
      for (final leg in o.legs) {
        expect(leg.start.isBefore(t), isFalse);
        expect(leg.end.isBefore(leg.start), isFalse);
        t = leg.end;
      }
      for (final ride in o.rideLegs) {
        // A real line, the one its variant belongs to
        expect(data.lines, contains(ride.line));
        expect(data.lines[data.variantLines[ride.variant]!], ride.line);
        expect(ride.stops.first.id, ride.boardStop.id);
        expect(ride.stops.last.id, ride.alightStop.id);
        expect(ride.arrival.isAfter(ride.departure), isTrue);
        expect(data.indexOfStop(ride.boardStop.id), ride.boardStop.index);
      }
    }
  });

  test('decode and plan in a fresh isolate, as the app does', () async {
    final watch = Stopwatch()..start();
    final options = await Isolate.run(() {
      final data = TransitData.decode(Uint8List.fromList(bytes));
      return TripPlanner(
        data,
      ).plan(from: _pocitos, to: _ciudadVieja, departAt: _wednesday14);
    });
    // ignore: avoid_print
    print('isolate: decode + plan + copy back ${watch.elapsedMilliseconds} ms');
    expect(options.length, greaterThanOrEqualTo(2));
  });
}

void _expectWalkLimit(Itinerary o, int minutes) {
  final first = o.legs.first as WalkLeg, last = o.legs.last as WalkLeg;
  expect(first.metres, lessThanOrEqualTo(minutes * 80));
  expect(last.metres, lessThanOrEqualTo(minutes * 80));
}
