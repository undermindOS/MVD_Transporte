import 'bus_arrival.dart';

enum WaitOutcome { waiting, alert, over }

class WaitCheck {
  final WaitOutcome outcome;

  /// The followed trip in the last answer; null when not listed.
  final BusArrival? trip;

  /// The request failed (offline, server error).
  final bool failed;

  const WaitCheck(this.outcome, {this.trip, this.failed = false});
}

/// "Estoy esperando": one trip the user waits for at a stop.
///
/// A trip is followed by its [tripId]. A timetable trip gets a new id once
/// its bus is tracked (`sched-…` → `bus-…`), so when the id is not listed
/// each check takes the bus of the same variant (or, without one, of the
/// same line and destination) closest to [expectedAt], and adopts its id
/// and time.
class BusWait {
  final int stopId;
  final String stopName;
  final String line;
  final String destination;

  /// The followed trip; null in a wait saved before trip ids existed.
  String? tripId;

  /// transporteRest `variante` of the trip, null when unknown.
  final int? variantId;

  /// Notify when the GPS-tracked bus is at most this many minutes away.
  final int alertMinutes;
  final DateTime startedAt;
  DateTime expectedAt;

  /// The wait ends on its own after this long.
  static const maxDuration = Duration(minutes: 60);

  /// A bus further than this from [expectedAt] is another trip.
  static const sameTripTolerance = Duration(minutes: 10);

  /// Not listed this long after [expectedAt]: the bus has passed.
  static const passedGrace = Duration(minutes: 2);

  BusWait({
    required this.stopId,
    required this.stopName,
    required this.line,
    required this.destination,
    this.tripId,
    this.variantId,
    required this.alertMinutes,
    required this.startedAt,
    required this.expectedAt,
  });

  factory BusWait.forTrip({
    required int stopId,
    required String stopName,
    required BusArrival trip,
    required int alertMinutes,
    required DateTime now,
  }) =>
      BusWait(
        stopId: stopId,
        stopName: stopName,
        line: trip.line,
        destination: trip.destination,
        tripId: trip.tripId,
        variantId: trip.variantId,
        alertMinutes: alertMinutes,
        startedAt: now,
        expectedAt: trip.expectedAt,
      );

  String get title => destination.isEmpty
      ? 'Esperando el $line'
      : 'Esperando el $line → $destination';

  /// The followed trip in [arrivals], or null when it is not listed.
  BusArrival? findTrip(List<BusArrival> arrivals, DateTime now) {
    final id = tripId;
    if (id != null) {
      final same = _closest(arrivals.where((a) => a.tripId == id));
      if (same != null) return same;
    }
    return _closest(arrivals.where(_sameRoute), within: sameTripTolerance);
  }

  /// Whether [arrival], one of [all], is the followed trip.
  bool follows(BusArrival arrival, List<BusArrival> all, DateTime now) =>
      identical(findTrip(all, now), arrival);

  // The variant when both sides know it, otherwise line and destination
  bool _sameRoute(BusArrival a) {
    final variant = variantId;
    if (variant != null && a.variantId != null) return a.variantId == variant;
    return a.line.toUpperCase() == line.toUpperCase() &&
        a.destination == destination;
  }

  BusArrival? _closest(Iterable<BusArrival> candidates, {Duration? within}) {
    BusArrival? best;
    Duration? bestDiff;
    for (final a in candidates) {
      final diff = a.expectedAt.difference(expectedAt).abs();
      if (within != null && diff > within) continue;
      if (bestDiff == null || diff < bestDiff) {
        best = a;
        bestDiff = diff;
      }
    }
    return best;
  }

  /// One poll: follows the trip ([expectedAt] moves) and decides whether
  /// to notify. [arrivals] null = the request failed.
  WaitCheck check(List<BusArrival>? arrivals, DateTime now) {
    if (now.difference(startedAt) >= maxDuration) {
      return const WaitCheck(WaitOutcome.over);
    }
    if (arrivals == null) {
      return const WaitCheck(WaitOutcome.waiting, failed: true);
    }
    final trip = findTrip(arrivals, now);
    if (trip == null) {
      return WaitCheck(now.isAfter(expectedAt.add(passedGrace))
          ? WaitOutcome.over
          : WaitOutcome.waiting);
    }
    tripId = trip.tripId;
    expectedAt = trip.expectedAt;
    // Like the periodic alerts: only a GPS-tracked bus is "arriving"
    final arriving = trip.isRealTime && trip.etaMinutes <= alertMinutes;
    return WaitCheck(arriving ? WaitOutcome.alert : WaitOutcome.waiting,
        trip: trip);
  }

  /// Text for the ongoing notification.
  String statusText(WaitCheck result) {
    final trip = result.trip;
    final String status;
    if (result.failed) {
      status = 'Sin conexión, reintentando…';
    } else if (trip == null) {
      status = 'Sin datos del ómnibus por ahora';
    } else if (trip.isRealTime) {
      status = trip.etaMinutes <= 0
          ? 'Llegando'
          : 'Llega en ${trip.etaMinutes} min';
    } else {
      status = 'Según horario ${trip.etaLabel}, sin GPS todavía';
    }
    return '$status · $stopName';
  }

  Map<String, Object?> toJson() => {
        'stopId': stopId,
        'stopName': stopName,
        'line': line,
        'destination': destination,
        'tripId': tripId,
        'variantId': variantId,
        'alertMinutes': alertMinutes,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'expectedAt': expectedAt.millisecondsSinceEpoch,
      };

  factory BusWait.fromJson(Map<String, dynamic> json) => BusWait(
        stopId: json['stopId'] as int,
        stopName: json['stopName'] as String,
        line: json['line'] as String,
        destination: json['destination'] as String,
        tripId: json['tripId'] as String?,
        variantId: json['variantId'] as int?,
        alertMinutes: json['alertMinutes'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
        expectedAt:
            DateTime.fromMillisecondsSinceEpoch(json['expectedAt'] as int),
      );
}
