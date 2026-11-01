// TripPlanner on small synthetic networks (support/synthetic_network.dart):
// walking at both ends, transfers, service days and the options it keeps.

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/rutas/itinerary.dart';
import 'package:stm_app/services/rutas/transit_data.dart';
import 'package:stm_app/services/rutas/trip_planner.dart';

import 'support/synthetic_network.dart';

final _at = SyntheticNetwork.at;

/// Wednesday, Friday, Saturday, Sunday, Monday, Tuesday.
DateTime _wed(int h, int m) => DateTime(2026, 11, 4, h, m);

int _walk(GeoPoint a, GeoPoint b) =>
    TransitData.walkMetres(a.lat, a.lon, b.lat, b.lon);

List<String> _lines(Itinerary i) => [for (final r in i.rideLegs) r.line];

/// Every option keeps the walking limit at both ends.
void _expectWalkLimit(List<Itinerary> options, int maxWalkMinutes) {
  for (final o in options.where((o) => !o.walkOnly)) {
    final first = o.legs.first as WalkLeg, last = o.legs.last as WalkLeg;
    expect(first.fromStop, isNull);
    expect(last.toStop, isNull);
    expect(first.metres, lessThanOrEqualTo(maxWalkMinutes * 80));
    expect(last.metres, lessThanOrEqualTo(maxWalkMinutes * 80));
    expect(first.minutes, lessThanOrEqualTo(maxWalkMinutes));
    expect(last.minutes, lessThanOrEqualTo(maxWalkMinutes));
  }
}

void main() {
  test('a direct ride: walk, bus, walk, with stops and times', () {
    final net = SyntheticNetwork();
    final s1 = net.stop(0, 0), mid = net.stop(2000, 0), s2 = net.stop(4000, 0);
    net.route(
      '121',
      [s1, mid, s2],
      [0, 5, 10],
      habil: [hm(8, 0), hm(8, 10), hm(8, 20)],
    );
    final data = net.build();
    final a = _at(0, 100), b = _at(4000, 100);

    final options = TripPlanner(
      data,
    ).plan(from: a, to: b, departAt: _wed(7, 55));

    // The 08:10 and 08:20 buses arrive later with the same walking
    expect(options, hasLength(1));
    final trip = options.single;
    expect(trip.rides, 1);
    expect(trip.walkOnly, isFalse);
    expect(trip.legs, hasLength(3));
    final access = trip.legs[0] as WalkLeg;
    final ride = trip.legs[1] as RideLeg;
    final egress = trip.legs[2] as WalkLeg;

    final accessMetres = _walk(a, (
      lat: data.stops[s1].lat,
      lon: data.stops[s1].lon,
    ));
    expect(accessMetres, inInclusiveRange(130, 131)); // 100 m × 1.3
    expect(access.from, a);
    expect(access.metres, accessMetres);
    expect(access.minutes, 2);
    expect((access.fromStop, access.toStop, access.toStopId), (null, s1, 1001));
    // Leave just in time for the bus
    expect(access.start, _wed(7, 58));
    expect(access.end, _wed(8, 0));

    expect(ride.line, '121');
    expect(ride.variant, 100);
    expect((ride.boardStop.id, ride.alightStop.id), (1001, 1003));
    expect((ride.boardStop.index, ride.alightStop.index), (s1, s2));
    expect(ride.departure, _wed(8, 0));
    expect(ride.arrival, _wed(8, 10));
    expect([for (final s in ride.stops) s.id], [1001, 1002, 1003]);
    expect(
      [for (final s in ride.stops) s.time],
      [_wed(8, 0), _wed(8, 5), _wed(8, 10)],
    );
    expect(ride.stops[1].lat, data.stops[mid].lat);
    expect(ride.stops[1].lon, data.stops[mid].lon);
    expect(ride.stops[1].name, 'PARADA 1002');

    expect(
      (egress.fromStop, egress.fromStopId, egress.toStop),
      (s2, 1003, null),
    );
    expect(egress.to, b);
    expect(egress.start, _wed(8, 10));
    expect(egress.end, _wed(8, 12));

    expect(trip.start, _wed(7, 58));
    expect(trip.end, _wed(8, 12));
    expect(trip.duration, const Duration(minutes: 14));
    expect(trip.walkMetres, access.metres + egress.metres);
    expect(trip.walkMinutes, 4);
  });

  group('one transfer beats a long walk', () {
    late TransitData data;
    late int s2, s3;
    final a = _at(0, 50), b = _at(3000, 900);
    setUp(() {
      final net = SyntheticNetwork();
      final s1 = net.stop(0, 0);
      s2 = net.stop(3000, 0);
      s3 = net.stop(3000, 200); // 260 m on foot from s2: 4 min
      final s4 = net.stop(3000, 850);
      net.route('121', [s1, s2], [0, 20], habil: [hm(8, 0)]);
      net.route('D10', [s3, s4], [0, 3], habil: [hm(8, 25)]);
      data = net.build();
    });

    test('walking 15 min from the first bus arrives later', () {
      final options = TripPlanner(
        data,
      ).plan(from: a, to: b, departAt: _wed(7, 55), maxWalkMinutes: 15);
      expect(
        [for (final o in options) _lines(o)],
        [
          ['121', 'D10'],
          ['121'],
        ],
      );
      final transfer = options[0];
      expect(transfer.end, _wed(8, 29));
      expect(transfer.rides, 2);
      final walk = transfer.legs[2] as WalkLeg;
      expect((walk.fromStop, walk.toStop), (s2, s3));
      expect((walk.fromStopId, walk.toStopId), (1002, 1003));
      expect(walk.metres, inInclusiveRange(260, 261));
      expect((walk.start, walk.end), (_wed(8, 20), _wed(8, 24)));
      expect(transfer.rideLegs.last.departure, _wed(8, 25));

      final longWalk = options[1];
      expect(longWalk.end, _wed(8, 35));
      expect((longWalk.legs.last as WalkLeg).minutes, 15);
      _expectWalkLimit(options, 15);
    });

    test('with 10 min, the stop of the first bus is too far from B', () {
      final options = TripPlanner(
        data,
      ).plan(from: a, to: b, departAt: _wed(7, 55));
      expect(
        [for (final o in options) _lines(o)],
        [
          ['121', 'D10'],
        ],
      );
      _expectWalkLimit(options, 10);
    });
  });

  test('the walking limit (5, 10, 15 min) holds at both ends', () {
    final net = SyntheticNetwork();
    final p5 = net.stop(300, 0); // 391 m on foot: 5 min
    final p10 = net.stop(-600, 0); // 781 m: 10 min
    final p15 = net.stop(0, 900); // 1171 m: 15 min
    final q = net.stop(5000, 5000); // 65 m from B
    final qFar = net.stop(5000, 5650); // 781 m from B
    net.route('L5', [p5, q], [0, 60], habil: [hm(8, 0)]);
    net.route('LX', [p5, qFar], [0, 30], habil: [hm(8, 0)]);
    net.route('L10', [p10, q], [0, 40], habil: [hm(8, 0)]);
    net.route('L15', [p15, q], [0, 20], habil: [hm(8, 0)]);
    final planner = TripPlanner(net.build());

    List<Itinerary> plan(int minutes) => planner.plan(
      from: _at(0, 0),
      to: _at(5000, 5050),
      departAt: _wed(7, 30),
      maxWalkMinutes: minutes,
    );

    final five = plan(5), ten = plan(10), fifteen = plan(15);
    // Every bus leaves at 08:00: the fastest each limit allows
    expect(
      [for (final o in five) _lines(o)],
      [
        ['L5'],
      ],
    );
    expect(five.single.end, _wed(9, 1));
    expect(
      [for (final o in ten) _lines(o)],
      [
        ['LX'],
      ],
    );
    expect(ten.single.end, _wed(8, 40));
    expect(
      [for (final o in fifteen) _lines(o)],
      [
        ['L15'],
      ],
    );
    expect(fifteen.single.end, _wed(8, 21));
    _expectWalkLimit(five, 5);
    _expectWalkLimit(ten, 10);
    _expectWalkLimit(fifteen, 15);
    expect(plan(0), isEmpty);
  });

  group('service days', () {
    late TransitData data;
    final a = _at(0, 50), b = _at(3000, 50);
    setUp(() {
      final net = SyntheticNetwork(mondayCutoff: 240);
      final s0 = net.stop(-3000, 0), s1 = net.stop(0, 0);
      final s2 = net.stop(3000, 0);
      // Leaves at 23:50 and passes s1 at 00:05
      net.route('NOCHE', [s0, s1, s2], [0, 15, 25], habil: [hm(23, 50)]);
      data = net.build();
    });

    RideLeg ride(DateTime departAt) => TripPlanner(
      data,
    ).plan(from: a, to: b, departAt: departAt).single.rideLegs.single;

    test('after midnight, a trip of the day before', () {
      // Monday's 23:50 trip on Tuesday at 00:05
      final r = ride(DateTime(2026, 11, 3, 0, 1));
      expect(r.departure, DateTime(2026, 11, 3, 0, 5));
      expect(r.arrival, DateTime(2026, 11, 3, 0, 15));
      // Asked on Monday night, the same trip past midnight
      expect(
        ride(DateTime(2026, 11, 2, 23, 55)).departure,
        DateTime(2026, 11, 3, 0, 5),
      );
    });

    test('Monday after midnight runs the Sunday night service', () {
      final net = SyntheticNetwork(mondayCutoff: 240);
      final s1 = net.stop(0, 0), s2 = net.stop(3000, 0);
      // 00:05 on weekdays; 00:10 on Monday as part of Sunday (the `*` rows)
      net.route(
        'N1',
        [s1, s2],
        [0, 10],
        habil: [hm(0, 5)],
        domingo: [1440 + hm(0, 10)],
      );
      final planner = TripPlanner(net.build());
      DateTime board(DateTime departAt) => planner
          .plan(from: a, to: b, departAt: departAt)
          .first
          .rideLegs
          .single
          .departure;

      expect(board(DateTime(2026, 11, 2, 0, 0)), DateTime(2026, 11, 2, 0, 10));
      expect(board(DateTime(2026, 11, 3, 0, 0)), DateTime(2026, 11, 3, 0, 5));
      // Sunday 23:58: Sunday's own trip after midnight, not Monday's hábil
      expect(
        board(DateTime(2026, 11, 1, 23, 58)),
        DateTime(2026, 11, 2, 0, 10),
      );
    });

    test('sábado and domingo timetables', () {
      final net = SyntheticNetwork();
      final s1 = net.stop(0, 0), s2 = net.stop(3000, 0);
      net.route(
        '121',
        [s1, s2],
        [0, 10],
        habil: [hm(10, 0)],
        sabado: [hm(10, 20)],
        domingo: [hm(10, 40)],
      );
      final planner = TripPlanner(net.build());
      DateTime board(DateTime departAt) => planner
          .plan(from: a, to: b, departAt: departAt)
          .single
          .rideLegs
          .single
          .departure;

      expect(board(DateTime(2026, 11, 6, 9, 50)), DateTime(2026, 11, 6, 10, 0));
      expect(
        board(DateTime(2026, 11, 7, 9, 50)),
        DateTime(2026, 11, 7, 10, 20),
      );
      expect(
        board(DateTime(2026, 11, 8, 9, 50)),
        DateTime(2026, 11, 8, 10, 40),
      );
    });
  });

  group('no bus', () {
    late TripPlanner planner;
    setUp(() {
      final net = SyntheticNetwork();
      final s1 = net.stop(0, 0), s2 = net.stop(4000, 0);
      net.route('121', [s2, s1], [0, 10], habil: [hm(8, 0)]); // the other way
      planner = TripPlanner(net.build());
    });

    test('no route: an empty list', () {
      expect(
        planner.plan(from: _at(0, 50), to: _at(4000, 50), departAt: _wed(7, 0)),
        isEmpty,
      );
      // Nothing within the horizon
      expect(
        planner.plan(from: _at(4000, 50), to: _at(0, 50), departAt: _wed(4, 0)),
        isEmpty,
      );
    });

    test('on foot only within twice the walking limit, flagged', () {
      final walk = planner.plan(
        from: _at(0, 1000),
        to: _at(500, 1000), // 650 m on foot
        departAt: _wed(7, 0),
        maxWalkMinutes: 5,
      );
      expect(walk, hasLength(1));
      final trip = walk.single;
      expect(trip.walkOnly, isTrue);
      expect(trip.rides, 0);
      expect(trip.legs.single, isA<WalkLeg>());
      expect(trip.walkMetres, inInclusiveRange(650, 651));
      expect((trip.start, trip.end), (_wed(7, 0), _wed(7, 9)));

      expect(
        planner.plan(
          from: _at(0, 1000),
          to: _at(700, 1000), // 910 m > 2 × 400
          departAt: _wed(7, 0),
          maxWalkMinutes: 5,
        ),
        isEmpty,
      );
    });
  });

  test('Pareto: faster with a transfer and slower direct, both', () {
    final net = SyntheticNetwork();
    final s1 = net.stop(0, 0), s2 = net.stop(2000, 0), s9 = net.stop(4000, 0);
    net.route('LENTO', [s1, s9], [0, 40], habil: [hm(8, 0)]);
    net.route('R1', [s1, s2], [0, 8], habil: [hm(8, 0)]);
    // Arriving at 08:08 misses the 08:08: a minute to change
    net.route('R2', [s2, s9], [0, 8], habil: [hm(8, 8), hm(8, 9)]);

    final options = TripPlanner(
      net.build(),
    ).plan(from: _at(0, 50), to: _at(4000, 50), departAt: _wed(7, 55));

    expect(
      [for (final o in options) _lines(o)],
      [
        ['R1', 'R2'],
        ['LENTO'],
      ],
    );
    final fast = options[0], slow = options[1];
    expect(fast.end, _wed(8, 18));
    expect(slow.end, _wed(8, 41));
    // Same stop: no walk between the rides
    expect(fast.legs.map((l) => l.runtimeType), [
      WalkLeg,
      RideLeg,
      RideLeg,
      WalkLeg,
    ]);
    expect(
      [for (final r in fast.rideLegs) r.departure],
      [_wed(8, 0), _wed(8, 9)],
    );
    expect(fast.walkMetres, slow.walkMetres);
  });
}
