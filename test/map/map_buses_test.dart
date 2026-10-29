// MapBuses.from: the Mapa's buses from the boards of the saved stops. A GPS
// bus on several boards is one bus, rows without a bus id stay per stop,
// positions past the basemap are dropped, and after a failed refresh the
// last buses are estimates for 5 min after their board reached the phone,
// then gone. Each ETA is live or an estimate as its own board. Ages count
// on the phone's clock, never on the source's.

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

/// A board that reached the phone [age] ago; the source stamped it
/// [fetchedAt] (by default the same moment, a source clock that agrees).
ReceivedBoard _board(
  int stopId,
  List<BusArrival> arrivals, {
  Duration age = const Duration(seconds: 10),
  DateTime? fetchedAt,
}) => (
  board: ArrivalsBoard(
    stopId: stopId,
    fetchedAt: fetchedAt ?? _now.subtract(age),
    arrivals: arrivals,
  ),
  receivedAt: _now.subtract(age),
);

List<MapBus> _buses(
  Map<int, ReceivedBoard> boards, {
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

  test('a bus on a current board and on a failed one: its ETA to the '
      'failed stop is an estimate', () {
    final buses = _buses(
      {
        574: _board(574, [
          _arrival('bus-50-678', eta: 8),
        ], age: const Duration(minutes: 3)),
        3140: _board(3140, [_arrival('bus-50-678', eta: 2)]),
      },
      failed: {574},
    );
    final bus = buses.single;
    // Its position is from the current board
    expect(bus.live, isTrue);
    expect(bus.etas.map((e) => (e.stopId, e.etaMinutes, e.live)), [
      (3140, 2, true),
      (574, 8, false),
    ]);
  });

  test('a bus as an estimate: unlit, and every ETA too', () {
    final bus = _buses({
      574: _board(574, [_arrival('bus-50-111', eta: 4)]),
      3140: _board(3140, [_arrival('bus-50-111', eta: 9)]),
    }).single;
    expect(bus.etas.every((e) => e.live), isTrue);
    final estimate = bus.estimate;
    expect(
      (estimate.key, estimate.line, estimate.position),
      (bus.key, bus.line, bus.position),
    );
    expect(estimate.live, isFalse);
    expect(estimate.etas.map((e) => (e.stopId, e.clockTime, e.live)), [
      (574, '19:54', false),
      (3140, '19:59', false),
    ]);
  });

  test('a board a minute old is not live, even with no failure', () {
    final buses = _buses({
      574: _board(574, [
        _arrival('bus-50-111', eta: 9),
      ], age: const Duration(minutes: 1)),
    });
    expect(buses.single.live, isFalse);
  });

  test('estimates go 5 min after their board reached the phone', () {
    final boards = {
      574: _board(574, [_arrival('bus-50-111', eta: 9)]),
    };
    final fetched = boards[574]!.receivedAt;
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

  test('a phone clock off from the source: ages from the arrival', () {
    // The proxy stamped these boards 3 min before the phone's clock says
    // it got them, or 3 min after: both just arrived, both live
    final behind = _board(574, [
      _arrival('bus-50-1'),
    ], fetchedAt: _now.subtract(const Duration(minutes: 3)));
    final ahead = _board(3140, [
      _arrival('bus-50-2'),
    ], fetchedAt: _now.add(const Duration(minutes: 3)));
    final buses = _buses({574: behind, 3140: ahead});
    expect(buses.map((b) => (b.key, b.live)), [
      ('bus-50-1', true),
      ('bus-50-2', true),
    ]);
    expect(MapBuses.liveness(behind, failed: false, now: _now), isTrue);

    // Stamped just now by the source but received 2 min ago: not live
    final late = _board(
      574,
      [_arrival('bus-50-1')],
      age: const Duration(minutes: 2),
      fetchedAt: _now,
    );
    expect(_buses({574: late}).single.live, isFalse);
    // Received 5 min ago: gone, whatever the source's stamp
    final old = _board(
      574,
      [_arrival('bus-50-1')],
      age: MapBuses.staleFor,
      fetchedAt: _now,
    );
    expect(_buses({574: old}), isEmpty);
  });

  test('a bus on two boards: its position from the one the source stamped '
      'later, whatever reached the phone first', () {
    final buses = _buses({
      // Stamped later by the proxy, but it reached the phone first
      574: _board(
        574,
        [_arrival('bus-50-111', at: (lat: -34.9000, lng: -56.2000))],
        age: const Duration(seconds: 20),
        fetchedAt: _now.subtract(const Duration(seconds: 5)),
      ),
      3140: _board(
        3140,
        [_arrival('bus-50-111', at: (lat: -34.9100, lng: -56.2100))],
        age: const Duration(seconds: 5),
        fetchedAt: _now.subtract(const Duration(seconds: 15)),
      ),
    });
    expect(buses.single.position, const LatLng(-34.9000, -56.2000));
  });

  test('estimates are dropped on the source clock: a phone 10 min ahead '
      'keeps a bus due 5 min after the board', () {
    // The proxy stamped the board 10 min before the phone's clock says it
    // arrived (10 s ago); its refresh then failed
    final fetched = _now.subtract(const Duration(minutes: 10));
    final board = _board(574, [
      _arrival('bus-50-1', expectedAt: fetched.add(const Duration(minutes: 5))),
      _arrival(
        'bus-50-2',
        expectedAt: fetched.subtract(const Duration(minutes: 2)),
      ),
    ], fetchedAt: fetched);
    final buses = _buses({574: board}, failed: {574});
    expect(buses.map((b) => (b.key, b.live)), [('bus-50-1', false)]);
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
