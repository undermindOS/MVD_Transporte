// MapBuses.from: the Mapa's buses from the boards of the saved stops. A GPS
// bus on several boards is one bus, rows without a bus id stay per stop,
// positions past the basemap are dropped, and after a failed refresh the
// last buses are estimates for 5 min after their board, then gone.

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/models/arrivals_board.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/ui/map/map_buses.dart';

/// The bbox of the bundled extract.
final _bounds = LatLngBounds(
  const LatLng(-34.97, -56.80),
  const LatLng(-34.50, -55.70),
);

final _now = DateTime.utc(2026, 10, 19, 22, 53);

BusArrival _arrival(
  String tripId, {
  String line = '121',
  int eta = 5,
  ({double lat, double lng})? at = (lat: -34.9094, lng: -56.2078),
  ArrivalState state = ArrivalState.live,
  DateTime? expectedAt,
}) => BusArrival(
  tripId: tripId,
  line: line,
  destination: 'PUNTA CARRETAS',
  state: state,
  etaMinutes: eta,
  expectedAt: expectedAt ?? _now.add(Duration(minutes: eta)),
  clockTime: '19:5$eta',
  location: at,
);

ArrivalsBoard _board(
  int stopId,
  List<BusArrival> arrivals, {
  Duration age = const Duration(seconds: 10),
}) => ArrivalsBoard(
  stopId: stopId,
  fetchedAt: _now.subtract(age),
  arrivals: arrivals,
);

List<MapBus> _buses(
  Map<int, ArrivalsBoard> boards, {
  Set<int> failed = const {},
  DateTime? now,
}) => MapBuses.from(
  stopIds: boards.keys,
  boards: boards,
  failed: failed,
  bounds: _bounds,
  now: now ?? _now,
);

void main() {
  test('a GPS bus on two boards is one bus, with the ETA to each stop', () {
    final buses = _buses({
      574: _board(574, [_arrival('bus-50-111', eta: 4)]),
      3140: _board(3140, [_arrival('bus-50-111', eta: 9)]),
    });
    expect(buses, hasLength(1));
    final bus = buses.single;
    expect(bus.key, 'bus-50-111');
    expect(bus.line, '121');
    expect(bus.live, isTrue);
    expect(bus.etas.map((e) => (e.stopId, e.etaMinutes)), [
      (574, 4),
      (3140, 9),
    ]);
  });

  test('the ETAs are soonest first, whatever the stop order', () {
    final buses = _buses({
      3140: _board(3140, [_arrival('bus-50-111', eta: 9)]),
      574: _board(574, [_arrival('bus-50-111', eta: 2)]),
    });
    expect(buses.single.etas.map((e) => e.stopId), [574, 3140]);
    expect(buses.single.etas.first.clockTime, '19:52');
  });

  test('the position comes from the newest board', () {
    final buses = _buses({
      574: _board(574, [
        _arrival('bus-50-111', at: (lat: -34.90, lng: -56.20)),
      ], age: const Duration(seconds: 40)),
      3140: _board(3140, [
        _arrival('bus-50-111', at: (lat: -34.91, lng: -56.21)),
      ]),
    });
    expect(buses.single.position, const LatLng(-34.91, -56.21));
  });

  test('a row without a bus id is keyed per stop, never merged', () {
    // A real row with no idBus: a location and a per-stop sched id
    final buses = _buses({
      574: _board(574, [_arrival('sched-883-2001')]),
      3140: _board(3140, [_arrival('sched-883-2001')]),
    });
    expect(buses.map((b) => b.key), [
      '574/sched-883-2001',
      '3140/sched-883-2001',
    ]);
    expect(buses.every((b) => b.etas.length == 1), isTrue);
  });

  test('no location, or past the basemap, is not drawn', () {
    final buses = _buses({
      574: _board(574, [
        _arrival('bus-50-1', at: null, state: ArrivalState.scheduled),
        // Buenos Aires
        _arrival('bus-50-2', at: (lat: -34.60, lng: -58.38)),
        // Just past the east edge of the extract
        _arrival('bus-50-3', at: (lat: -34.80, lng: -55.69)),
        _arrival('bus-50-4'),
      ]),
    });
    expect(buses.map((b) => b.key), ['bus-50-4']);
  });

  test('after a failed refresh the last buses are estimates', () {
    final boards = {
      574: _board(574, [_arrival('bus-50-111')]),
      3140: _board(3140, [_arrival('bus-50-139')]),
    };
    final buses = _buses(boards, failed: {574});
    expect(
      {for (final b in buses) b.key: b.live},
      {'bus-50-111': false, 'bus-50-139': true},
    );
  });

  test('a board a minute old is not live, even with no failure', () {
    final buses = _buses({
      574: _board(574, [
        _arrival('bus-50-111', eta: 9),
      ], age: const Duration(minutes: 1)),
    });
    expect(buses.single.live, isFalse);
  });

  test('estimates go 5 min after their board was fetched', () {
    final boards = {
      574: _board(574, [_arrival('bus-50-111', eta: 9)]),
    };
    final fetched = boards[574]!.fetchedAt;
    final atFour = _buses(
      boards,
      failed: {574},
      now: fetched.add(const Duration(minutes: 4, seconds: 59)),
    );
    expect(atFour.single.live, isFalse);
    expect(
      _buses(boards, failed: {574}, now: fetched.add(MapBuses.staleFor)),
      isEmpty,
    );
    // Without a failure too
    expect(_buses(boards, now: fetched.add(MapBuses.staleFor)), isEmpty);
  });

  test('an estimate due more than a minute ago is dropped', () {
    final buses = _buses(
      {
        574: _board(574, [
          _arrival(
            'bus-50-1',
            expectedAt: _now.subtract(const Duration(minutes: 2)),
          ),
          _arrival(
            'bus-50-2',
            expectedAt: _now.subtract(const Duration(seconds: 30)),
          ),
        ]),
      },
      failed: {574},
    );
    expect(buses.map((b) => b.key), ['bus-50-2']);
  });

  test('only the stops asked for, each once', () {
    final boards = {
      574: _board(574, [_arrival('bus-50-1')]),
      3140: _board(3140, [_arrival('bus-50-2')]),
    };
    final buses = MapBuses.from(
      stopIds: [574, 574],
      boards: boards,
      failed: const {},
      bounds: _bounds,
      now: _now,
    );
    expect(buses.single.etas, hasLength(1));
    expect(buses.single.key, 'bus-50-1');
  });
}
