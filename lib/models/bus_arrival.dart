/// How an arrival time is known (/v1 `state`).
enum ArrivalState {
  /// GPS-tracked bus at the stop now (0 min or less).
  arriving,

  /// GPS-tracked bus on its way.
  live,

  /// Timetable estimate: the bus is not tracked yet.
  scheduled,
}

/// One upcoming bus at a stop: an item of /v1 `arrivals`.
class BusArrival {
  /// Stable id of the trip across refreshes: `bus-{company}-{bus}` for a
  /// GPS-tracked bus, `sched-{variant}-{H*100+MM}` for a timetable one.
  final String tripId;

  /// transporteRest `variante`, null when unknown. Not the IM API's
  /// lineVariantId: the two can differ for the same bus.
  final int? variantId;

  final String line;

  /// Variant destination (e.g. "PLAZA ESPAÑA"), as the API writes it.
  final String destination;

  final ArrivalState state;

  /// Minutes to the stop, never negative.
  final int etaMinutes;

  /// When the bus is expected at the stop (UTC).
  final DateTime expectedAt;

  /// [expectedAt] on the Montevideo clock ("8:07", "20:17").
  final String clockTime;

  /// Wheelchair-accessible bus (API `accesibilidad`).
  final bool accessible;

  /// Comfort of the GPS-tracked bus, from the official IM API via the proxy.
  /// null = unknown (timetable estimate, no data, or no proxy configured).
  final bool? airConditioning;

  /// Zero-emission (electric) bus; null = unknown.
  final bool? zeroEmission;

  const BusArrival({
    required this.tripId,
    this.variantId,
    required this.line,
    this.destination = '',
    required this.state,
    required this.etaMinutes,
    required this.expectedAt,
    required this.clockTime,
    this.accessible = false,
    this.airConditioning,
    this.zeroEmission,
  });

  /// true = ETA computed from the bus GPS position;
  /// false = timetable estimate (bus not tracked yet).
  bool get isRealTime => state != ArrivalState.scheduled;

  bool get isArriving => state == ArrivalState.arriving;

  String get etaLabel {
    // Timetable estimate: show the clock time, not a countdown that looks live
    if (state == ArrivalState.scheduled) return clockTime;
    if (isArriving || etaMinutes <= 0) return 'Llegando';
    if (etaMinutes == 1) return '1 min';
    return '$etaMinutes min';
  }
}
