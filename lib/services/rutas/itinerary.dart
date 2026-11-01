/// What [TripPlanner.plan] returns: plain immutable values (no Flutter, no
/// references back to the timetable), so they can come back from compute().
library;

/// A point as the planner takes it: WGS84 degrees.
typedef GeoPoint = ({double lat, double lon});

/// One trip from A to B. A trip by bus starts and ends with a [WalkLeg]
/// (0 m when A or B is at the stop), with [RideLeg]s in between, and a
/// [WalkLeg] between two rides only when the transfer changes stop.
class Itinerary {
  const Itinerary({
    required this.start,
    required this.end,
    required this.legs,
    required this.rides,
    required this.walkMetres,
    required this.walkMinutes,
    this.walkOnly = false,
  });

  /// When to leave A: just in time to walk to the first bus. For
  /// [walkOnly], the time asked for.
  final DateTime start;

  /// Arrival at B.
  final DateTime end;
  final List<Leg> legs;

  /// How many buses: transfers are [rides] - 1.
  final int rides;

  /// Walking of the whole trip (both ends and transfers).
  final int walkMetres;
  final int walkMinutes;

  /// The trip on foot, offered only when it fits in twice the walking limit.
  final bool walkOnly;

  Duration get duration => end.difference(start);

  Iterable<RideLeg> get rideLegs => legs.whereType<RideLeg>();

  @override
  String toString() => [
    '${_hm(start)}→${_hm(end)}',
    for (final leg in legs) leg.toString(),
  ].join(' · ');
}

sealed class Leg {
  const Leg();
  DateTime get start;
  DateTime get end;
}

/// On foot. Distances are along the streets as the planner estimates them:
/// straight line × 1.3, at 80 m a minute.
class WalkLeg extends Leg {
  const WalkLeg({
    required this.from,
    required this.to,
    required this.metres,
    required this.minutes,
    required this.start,
    required this.end,
    this.fromStop,
    this.toStop,
    this.fromStopId,
    this.toStopId,
  });

  final GeoPoint from;
  final GeoPoint to;
  final int metres;
  final int minutes;
  @override
  final DateTime start;
  @override
  final DateTime end;

  /// Index in TransitData.stops; null when the leg starts at A.
  final int? fromStop;

  /// Index in TransitData.stops; null when the leg ends at B.
  final int? toStop;

  /// STM stop numbers (cod_ubic_parada) of [fromStop] and [toStop].
  final int? fromStopId;
  final int? toStopId;

  @override
  String toString() => 'a pie $metres m ($minutes min)';
}

/// On a bus, from [boardStop] to [alightStop].
class RideLeg extends Leg {
  const RideLeg({
    required this.line,
    required this.variant,
    required this.boardStop,
    required this.alightStop,
    required this.stops,
  });

  /// As IM names it: "121", "D10", "CA1".
  final String line;

  /// cod_variante.
  final int variant;
  final RideStop boardStop;
  final RideStop alightStop;

  /// Every stop of the ride, [boardStop] and [alightStop] included, with
  /// their positions: the line to draw.
  final List<RideStop> stops;

  /// When the bus leaves [boardStop] by the timetable.
  DateTime get departure => boardStop.time;

  /// When it gets to [alightStop] by the timetable.
  DateTime get arrival => alightStop.time;

  @override
  DateTime get start => departure;
  @override
  DateTime get end => arrival;

  @override
  String toString() =>
      '$line ${_hm(departure)} ${boardStop.id}'
      '→${_hm(arrival)} ${alightStop.id}';
}

/// A stop of a ride and when the bus passes it.
class RideStop {
  const RideStop({
    required this.index,
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.time,
  });

  /// Index in TransitData.stops.
  final int index;

  /// STM stop number (cod_ubic_parada): the one the live board asks for.
  final int id;

  /// "SAN JOSE y ANDES".
  final String name;
  final double lat;
  final double lon;
  final DateTime time;
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
