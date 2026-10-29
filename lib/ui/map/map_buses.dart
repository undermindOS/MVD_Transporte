import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart' show LatLng;

import '../../models/arrivals_board.dart';

/// When a bus reaches one saved stop, from that stop's board. [live] as
/// that board ([MapBuses.liveness]): a bus on a current board and on one
/// whose refresh failed has one lit ETA and one estimate.
typedef MapBusEta = ({int stopId, int etaMinutes, String clockTime, bool live});

/// A bus on the Mapa: one GPS position and the saved stops it is on its
/// way to.
class MapBus {
  const MapBus({
    required this.key,
    required this.line,
    required this.destination,
    required this.position,
    required this.live,
    required this.etas,
  });

  /// The trip id of a GPS bus (`bus-{company}-{bus}`), the same on every
  /// board it is on; `{stopId}/{tripId}` for a row with no bus id.
  final String key;
  final String line;
  final String destination;
  final LatLng position;

  /// Its position is from a current board. false: an estimate kept from
  /// the last board after a failed refresh, or one not refreshed for a
  /// while. Unlit.
  final bool live;

  /// The saved stops it approaches, soonest first.
  final List<MapBusEta> etas;

  /// This bus once no board has it any more: an estimate, every ETA too.
  MapBus get estimate => MapBus(
    key: key,
    line: line,
    destination: destination,
    position: position,
    live: false,
    etas: [
      for (final e in etas)
        (
          stopId: e.stopId,
          etaMinutes: e.etaMinutes,
          clockTime: e.clockTime,
          live: false,
        ),
    ],
  );
}

/// The Mapa's buses from the boards of the saved stops. Pure: no widgets,
/// the clock passed in.
abstract final class MapBuses {
  /// After a failed refresh the last buses stay this long after their
  /// board was fetched, as estimates, then they are dropped (as in Mis
  /// paradas).
  static const staleFor = Duration(minutes: 5);

  /// Two refresh intervals: an older board is not live any more, even
  /// with no failure since.
  static const liveFor = Duration(minutes: 1);

  /// An estimate due longer ago than this is dropped.
  static const staleRowGrace = Duration(minutes: 1);

  /// Whether the buses on [board] are live (true) or estimates (false):
  /// not live once its stop's latest refresh [failed] or it is [liveFor]
  /// old. null: nothing is known, no board or one [staleFor] old.
  static bool? liveness(
    ArrivalsBoard? board, {
    required bool failed,
    required DateTime now,
  }) {
    if (board == null) return null;
    final age = now.difference(board.fetchedAt);
    if (age >= staleFor) return null;
    return !failed && age < liveFor;
  }

  /// The buses with a location inside [bounds] on the boards of
  /// [stopIds], each board live or not by [liveness] (a stop in [failed]:
  /// its latest refresh failed). A GPS bus on several boards is one bus,
  /// at its position on the newest board.
  static List<MapBus> from({
    required Iterable<int> stopIds,
    required Map<int, ArrivalsBoard> boards,
    required Set<int> failed,
    required LatLngBounds bounds,
    required DateTime now,
  }) {
    final buses = <String, _Bus>{};
    final cutoff = now.subtract(staleRowGrace);
    for (final stopId in stopIds.toSet()) {
      final board = boards[stopId];
      final live = liveness(board, failed: failed.contains(stopId), now: now);
      if (board == null || live == null) continue;
      for (final arrival in board.arrivals) {
        final location = arrival.location;
        if (location == null) continue;
        final position = LatLng(location.lat, location.lng);
        // Past the basemap there are no tiles to place it on
        if (!bounds.contains(position)) continue;
        if (!live && arrival.expectedAt.isBefore(cutoff)) continue;
        // Only a GPS bus has an id shared across stops
        final key = arrival.tripId.startsWith('bus-')
            ? arrival.tripId
            : '$stopId/${arrival.tripId}';
        final eta = (
          stopId: stopId,
          etaMinutes: arrival.etaMinutes,
          clockTime: arrival.clockTime,
          live: live,
        );
        final bus = buses[key];
        if (bus == null) {
          buses[key] = _Bus(
            line: arrival.line,
            destination: arrival.destination,
            position: position,
            live: live,
            fetchedAt: board.fetchedAt,
          )..etas.add(eta);
          continue;
        }
        if (bus.etas.any((e) => e.stopId == stopId)) continue;
        bus.etas.add(eta);
        if (board.fetchedAt.isAfter(bus.fetchedAt)) {
          bus
            ..line = arrival.line
            ..destination = arrival.destination
            ..position = position
            ..live = live
            ..fetchedAt = board.fetchedAt;
        }
      }
    }
    return [
      for (final MapEntry(:key, value: bus) in buses.entries)
        MapBus(
          key: key,
          line: bus.line,
          destination: bus.destination,
          position: bus.position,
          live: bus.live,
          etas: List.unmodifiable(
            bus.etas..sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes)),
          ),
        ),
    ];
  }
}

/// A [MapBus] while its boards are read.
class _Bus {
  _Bus({
    required this.line,
    required this.destination,
    required this.position,
    required this.live,
    required this.fetchedAt,
  });

  String line;
  String destination;
  LatLng position;
  bool live;
  DateTime fetchedAt;
  final etas = <MapBusEta>[];
}
