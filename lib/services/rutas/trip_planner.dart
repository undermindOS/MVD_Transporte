import 'dart:typed_data';

import 'itinerary.dart';
import 'transit_data.dart';

/// A→B by STM bus on the phone: RAPTOR (one round per ride) over
/// [TransitData]. Nothing leaves the device.
///
/// Times are whole minutes, as the timetable has them. Walking: straight
/// line × 1.3 at 80 m a minute; at each end only stops within
/// `maxWalkMinutes`; between rides the same stop (1 minute to change) or
/// another stop up to [TransitData.footpathMaxMetres] away.
class TripPlanner {
  TripPlanner(this.data);

  final TransitData data;

  /// Trips arriving later than this after `departAt` are not looked for.
  static const horizonMinutes = 180;

  /// Minutes to change bus at the same stop.
  static const sameStopTransfer = 1;

  /// Up to `maxOptions` trips by bus, best first (arrival, then rides,
  /// then walking), plus the trip on foot when it takes at most twice
  /// `maxWalkMinutes` (flagged [Itinerary.walkOnly]). Empty when no bus
  /// gets there within [horizonMinutes] and B is too far to walk.
  ///
  /// First the Pareto set of arrival × rides; then the search again with
  /// the first bus at least a minute after the first boarding of the
  /// fastest trip just found, until there are `maxOptions`, a search brings
  /// nothing new, or `3 × maxOptions` searches. Options another one beats
  /// (leaves no earlier and arrives no later, with no more rides and no
  /// more walking) are dropped: the next bus of the same line stays, for
  /// whoever misses the first.
  List<Itinerary> plan({
    required ({double lat, double lon}) from,
    required ({double lat, double lon}) to,
    required DateTime departAt,
    int maxWalkMinutes = 10,
    int maxTransfers = 2,
    int maxOptions = 5,
  }) {
    final maxWalk = maxWalkMinutes * TransitData.walkMetresPerMinute;
    final search = _Search(
      data,
      from: from,
      to: to,
      day: DateTime(departAt.year, departAt.month, departAt.day),
      t0: departAt.hour * 60 + departAt.minute,
      access: maxWalk > 0 ? data.stopsNear(from.lat, from.lon, maxWalk) : [],
      egress: maxWalk > 0 ? data.stopsNear(to.lat, to.lon, maxWalk) : [],
      rounds: maxTransfers + 1,
    );

    final options = <Itinerary>[];
    final seen = <String>{};
    var minBoard = 0;
    for (var run = 0; run < maxOptions * 3; run++) {
      final found = search.run(minBoard);
      var added = false;
      for (final journey in found) {
        if (seen.add(journey.key)) {
          options.add(search.itinerary(journey));
          added = true;
        }
      }
      if (!added || _undominated(options).length >= maxOptions) break;
      // The last one found is the fastest: the next search leaves its bus
      minBoard = found.last.firstBoard + 1;
    }

    final walk = TransitData.walkMetres(from.lat, from.lon, to.lat, to.lon);
    final walkOnly = walk <= 2 * maxWalk
        ? _walkOnly(from, to, departAt, walk)
        : null;

    final kept = _undominated([...options, ?walkOnly])..sort(_byQuality);
    final rides = kept.where((i) => !i.walkOnly).take(maxOptions).toSet();
    return [
      for (final i in kept)
        if (i.walkOnly || rides.contains(i)) i,
    ];
  }

  static Itinerary _walkOnly(
    GeoPoint from,
    GeoPoint to,
    DateTime departAt,
    int metres,
  ) {
    final minutes = TransitData.walkMinutes(metres);
    final end = departAt.add(Duration(minutes: minutes));
    return Itinerary(
      start: departAt,
      end: end,
      legs: [
        WalkLeg(
          from: from,
          to: to,
          metres: metres,
          minutes: minutes,
          start: departAt,
          end: end,
        ),
      ],
      rides: 0,
      walkMetres: metres,
      walkMinutes: minutes,
      walkOnly: true,
    );
  }

  static int _byQuality(Itinerary a, Itinerary b) {
    var c = a.end.compareTo(b.end);
    if (c != 0) return c;
    c = a.rides.compareTo(b.rides);
    if (c != 0) return c;
    return a.walkMetres.compareTo(b.walkMetres);
  }

  /// Drops every option another one beats: leaves no earlier and arrives
  /// no later, with no more rides and no more walking, and is better in at
  /// least one of them. Leaving later is never worse: a later bus is what
  /// someone who missed the first one needs.
  static List<Itinerary> _undominated(List<Itinerary> options) => [
    for (final b in options)
      if (!options.any(
        (a) =>
            !identical(a, b) &&
            !a.start.isBefore(b.start) &&
            !a.end.isAfter(b.end) &&
            a.rides <= b.rides &&
            a.walkMetres <= b.walkMetres &&
            (a.start.isAfter(b.start) ||
                a.end.isBefore(b.end) ||
                a.rides < b.rides ||
                a.walkMetres < b.walkMetres),
      ))
        b,
  ];
}

/// A trip found by [_Search.run]: the round (= rides) and the stop where
/// the last ride ends.
class _Journey {
  _Journey(
    this.round,
    this.egressStop,
    this.egressMetres,
    this.firstBoard,
    this.key,
  );

  final int round;
  final int egressStop;
  final int egressMetres;

  /// Minute the first bus leaves its stop.
  final int firstBoard;

  /// The rides (route, trip, stops): equal keys are the same trip.
  final String key;
}

/// One A→B query: the labels of every round, reused by every run.
class _Search {
  _Search(
    this.data, {
    required this.from,
    required this.to,
    required this.day,
    required this.t0,
    required this.access,
    required this.egress,
    required this.rounds,
  }) {
    for (final shift in const [-1, 0, 1]) {
      final date = DateTime(day.year, day.month, day.day + shift);
      final type = DayType.of(date);
      // Only the days with trips between departAt and the horizon
      final first = shift * 1440, last = first + data.lastMinute(type);
      if (last < t0 || first > t0 + TripPlanner.horizonMinutes) continue;
      _services.add(
        _Service(
          type: type,
          shift: first,
          minDeparture: date.weekday == DateTime.monday ? data.mondayCutoff : 0,
        ),
      );
    }
    final n = data.stops.length;
    for (var k = 0; k <= rounds; k++) {
      _ready.add(Int32List(n));
      _readyFrom.add(Int32List(n));
      _readyMetres.add(Int32List(n));
      _readyWalk.add(Int32List(n));
      _arrival.add(Int32List(n));
      _arrivalWalk.add(Int32List(n));
      _route.add(Int32List(n));
      _trip.add(Int32List(n));
      _boardPos.add(Int32List(n));
      _alightPos.add(Int32List(n));
    }
    _bestReady = Int32List(n);
    _bestArrival = Int32List(n);
    _firstPos = Int32List(data.routes.length)
      ..fillRange(0, data.routes.length, -1);
    for (final a in access) {
      _accessMetres[a.stop] = a.metres;
    }
  }

  static const _inf = 1 << 30;

  final TransitData data;
  final GeoPoint from;
  final GeoPoint to;

  /// The calendar day of `departAt`; minutes count from its midnight.
  final DateTime day;
  final int t0;
  final List<({int stop, int metres})> access;
  final List<({int stop, int metres})> egress;
  final int rounds;
  final _services = <_Service>[];
  final _accessMetres = <int, int>{};

  // Round k: ready to board at a stop (after walking or changing), how and
  // after walking how much in all; arrival at a stop by the k-th ride, on
  // what, and after walking how much.
  final _ready = <Int32List>[];
  final _readyFrom = <Int32List>[]; // -1: from A; the stop itself: change
  final _readyMetres = <Int32List>[];
  final _readyWalk = <Int32List>[];
  final _arrival = <Int32List>[];
  final _arrivalWalk = <Int32List>[];
  final _route = <Int32List>[];
  final _trip = <Int32List>[]; // departure from the route's first stop
  final _boardPos = <Int32List>[];
  final _alightPos = <Int32List>[];
  late final Int32List _bestReady;
  late final Int32List _bestArrival;
  late final Int32List _firstPos;

  /// Pareto set of arrival × rides, fewest rides first, with no first bus
  /// before [minBoard]. Equal arrivals go to the one walking less.
  List<_Journey> run(int minBoard) {
    for (var k = 0; k <= rounds; k++) {
      _ready[k].fillRange(0, _ready[k].length, _inf);
      _arrival[k].fillRange(0, _arrival[k].length, _inf);
    }
    _bestReady.fillRange(0, _bestReady.length, _inf);
    _bestArrival.fillRange(0, _bestArrival.length, _inf);

    var marked = <int>[];
    for (final a in access) {
      final t = t0 + TransitData.walkMinutes(a.metres);
      final ready = t > minBoard ? t : minBoard;
      _ready[0][a.stop] = ready;
      _readyFrom[0][a.stop] = -1;
      _readyWalk[0][a.stop] = a.metres;
      _bestReady[a.stop] = ready;
      marked.add(a.stop);
    }

    final found = <_Journey>[];
    var best = t0 + TripPlanner.horizonMinutes + 1;
    for (var k = 1; k <= rounds && marked.isNotEmpty; k++) {
      final improved = _scanRoutes(k, marked, best);
      marked = _transfers(k, improved, best);

      var arrival = _inf, stop = -1, metres = 0, walk = _inf;
      for (final e in egress) {
        final t = _arrival[k][e.stop];
        if (t == _inf) continue;
        final at = t + TransitData.walkMinutes(e.metres);
        final w = _arrivalWalk[k][e.stop] + e.metres;
        if (at < arrival || (at == arrival && w < walk)) {
          arrival = at;
          stop = e.stop;
          metres = e.metres;
          walk = w;
        }
      }
      if (arrival < best) {
        best = arrival;
        found.add(_journey(k, stop, metres));
      }
    }
    return found;
  }

  /// Rides of round [k] from the stops [marked] in round k - 1. Returns
  /// the stops this round reached.
  List<int> _scanRoutes(int k, List<int> marked, int best) {
    final firstPos = _firstPos;
    final queue = <int>[];
    for (final s in marked) {
      for (var e = data.routesAtStart(s); e < data.routesAtEnd(s); e++) {
        final r = data.routeAt(e), p = data.positionAt(e);
        if (firstPos[r] == -1) {
          queue.add(r);
          firstPos[r] = p;
        } else if (p < firstPos[r]) {
          firstPos[r] = p;
        }
      }
    }

    // Locals: the hot loop below reads them for every stop of every route
    final ready = _ready[k - 1], readyWalk = _readyWalk[k - 1];
    final arrival = _arrival[k], arrivalWalk = _arrivalWalk[k];
    final bestArrival = _bestArrival;
    final routeOf = _route[k], tripOf = _trip[k];
    final boardPosOf = _boardPos[k], alightPosOf = _alightPos[k];
    final improved = <int>[];
    for (final r in queue) {
      final route = data.routes[r];
      final stops = route.stops, offsets = route.offsets;
      // The trip on board, and the one before it that runs (-_inf: none;
      // _inf: not looked up yet). An earlier trip can only be caught where
      // the one before passes after we are ready.
      var trip = _inf, before = _inf, boardPos = -1, walk = 0;
      for (var p = firstPos[r]; p < stops.length; p++) {
        final s = stops[p];
        if (trip != _inf) {
          final t = trip + offsets[p];
          if ((t < bestArrival[s] && t < best) ||
              (t == arrival[s] && walk < arrivalWalk[s])) {
            if (arrival[s] == _inf) improved.add(s);
            arrival[s] = t;
            arrivalWalk[s] = walk;
            bestArrival[s] = t;
            routeOf[s] = r;
            tripOf[s] = trip;
            boardPosOf[s] = boardPos;
            alightPosOf[s] = p;
          }
        }
        final at = ready[s];
        if (at == _inf) continue;
        if (at <= before + offsets[p]) {
          final earlier = _earliestTrip(route, at - offsets[p]);
          before = _before;
          if (earlier < trip) {
            trip = earlier;
            boardPos = p;
            walk = readyWalk[s];
          }
        } else if (at <= trip + offsets[p] && readyWalk[s] < walk) {
          // Same bus boarded further on: only when it saves walking
          boardPos = p;
          walk = readyWalk[s];
        }
      }
      firstPos[r] = -1;
    }
    return improved;
  }

  /// Departure from the route's first stop of its first trip leaving
  /// there at [minute] or later, over the service days; or [_inf]. Sets
  /// [_before] to the departure of the last trip before it that runs, or
  /// -[_inf].
  int _earliestTrip(TransitRoute route, int minute) {
    var best = _inf, before = -_inf;
    for (final service in _services) {
      final deps = route.departures[service.type.index];
      var need = minute - service.shift;
      if (need < service.minDeparture) need = service.minDeparture;
      var lo = 0, hi = deps.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (deps[mid] < need) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo < deps.length && deps[lo] + service.shift < best) {
        best = deps[lo] + service.shift;
      }
      if (lo > 0 &&
          deps[lo - 1] >= service.minDeparture &&
          deps[lo - 1] + service.shift > before) {
        before = deps[lo - 1] + service.shift;
      }
    }
    _before = before;
    return best;
  }

  int _before = -_inf;

  /// After the rides of round [k]: change bus at the same stop or walk to
  /// a nearby one. Returns the stops to board from in round k + 1.
  List<int> _transfers(int k, List<int> improved, int best) {
    final marked = <int>[];
    final ready = _ready[k], readyWalk = _readyWalk[k];
    void reach(int stop, int t, int fromStop, int metres, int walk) {
      if ((t < _bestReady[stop] && t < best) ||
          (t == ready[stop] && walk < readyWalk[stop])) {
        if (ready[stop] == _inf) marked.add(stop);
        ready[stop] = t;
        readyWalk[stop] = walk;
        _bestReady[stop] = t;
        _readyFrom[k][stop] = fromStop;
        _readyMetres[k][stop] = metres;
      }
    }

    for (final s in improved) {
      final t = _arrival[k][s], walk = _arrivalWalk[k][s];
      reach(s, t + TripPlanner.sameStopTransfer, s, 0, walk);
      for (var e = data.footpathsStart(s); e < data.footpathsEnd(s); e++) {
        final m = data.footpathMetres(e);
        var minutes = TransitData.walkMinutes(m);
        if (minutes < 1) minutes = 1;
        reach(data.footpathTo(e), t + minutes, s, m, walk + m);
      }
    }
    return marked;
  }

  _Journey _journey(int round, int stop, int metres) {
    final key = StringBuffer();
    var s = stop, firstBoard = 0;
    for (var k = round; k > 0; k--) {
      final route = data.routes[_route[k][s]];
      final board = _boardPos[k][s];
      key.write('${_route[k][s]}:${_trip[k][s]}:$board:${_alightPos[k][s]};');
      firstBoard = _trip[k][s] + route.offsets[board];
      final b = route.stops[board];
      s = _readyFrom[k - 1][b] == -1 ? b : _readyFrom[k - 1][b];
    }
    return _Journey(round, stop, metres, firstBoard, key.toString());
  }

  DateTime _time(int minute) =>
      DateTime(day.year, day.month, day.day, 0, minute);

  GeoPoint _at(int stop) =>
      (lat: data.stops[stop].lat, lon: data.stops[stop].lon);

  RideStop _rideStop(int stop, int minute) {
    final s = data.stops[stop];
    return RideStop(
      index: stop,
      id: s.id,
      name: s.name,
      lat: s.lat,
      lon: s.lon,
      time: _time(minute),
    );
  }

  Itinerary itinerary(_Journey journey) {
    final legs = <Leg>[];
    var walkMetres = 0, walkMinutes = 0;
    WalkLeg walk(
      GeoPoint a,
      GeoPoint b,
      int metres,
      int startMinute, {
      int? fromStop,
      int? toStop,
    }) {
      final minutes = TransitData.walkMinutes(metres);
      walkMetres += metres;
      walkMinutes += minutes;
      return WalkLeg(
        from: a,
        to: b,
        metres: metres,
        minutes: minutes,
        start: _time(startMinute),
        end: _time(startMinute + minutes),
        fromStop: fromStop,
        toStop: toStop,
        fromStopId: fromStop == null ? null : data.stops[fromStop].id,
        toStopId: toStop == null ? null : data.stops[toStop].id,
      );
    }

    // Built backwards, from B.
    var s = journey.egressStop;
    final arrival = _arrival[journey.round][s];
    legs.add(walk(_at(s), to, journey.egressMetres, arrival, fromStop: s));
    var startMinute = 0;
    for (var k = journey.round; k > 0; k--) {
      final route = data.routes[_route[k][s]];
      final trip = _trip[k][s];
      final board = _boardPos[k][s], alight = _alightPos[k][s];
      legs.add(
        RideLeg(
          line: data.lines[route.line],
          variant: route.variant,
          boardStop: _rideStop(route.stops[board], trip + route.offsets[board]),
          alightStop: _rideStop(
            route.stops[alight],
            trip + route.offsets[alight],
          ),
          stops: [
            for (var p = board; p <= alight; p++)
              _rideStop(route.stops[p], trip + route.offsets[p]),
          ],
        ),
      );
      final b = route.stops[board];
      if (k == 1) {
        final metres = _accessMetres[b]!;
        // Leave A just in time for the bus
        startMinute =
            trip + route.offsets[board] - TransitData.walkMinutes(metres);
        legs.add(walk(from, _at(b), metres, startMinute, toStop: b));
        break;
      }
      // Ready at b after ride k - 1: at b itself, or walked from prev
      final prev = _readyFrom[k - 1][b];
      if (prev != b) {
        legs.add(
          walk(
            _at(prev),
            _at(b),
            _readyMetres[k - 1][b],
            _arrival[k - 1][prev],
            fromStop: prev,
            toStop: b,
          ),
        );
      }
      s = prev;
    }
    return Itinerary(
      start: _time(startMinute),
      end: _time(arrival + TransitData.walkMinutes(journey.egressMetres)),
      legs: legs.reversed.toList(growable: false),
      rides: journey.round,
      walkMetres: walkMetres,
      walkMinutes: walkMinutes,
    );
  }
}

/// One service day as seen from the day searched: its timetable, how far
/// its minutes are from ours, and the first departure that runs.
class _Service {
  const _Service({
    required this.type,
    required this.shift,
    required this.minDeparture,
  });

  final DayType type;
  final int shift;
  final int minDeparture;
}
