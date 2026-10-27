import 'bus_arrival.dart';

/// The upcoming buses of one stop, as fetched at [fetchedAt]
/// (/v1 `ArrivalsResponse`).
class ArrivalsBoard {
  final int stopId;

  /// When the source answered (UTC); the proxy's edge cache can make it up
  /// to 15 s older than the request.
  final DateTime fetchedAt;

  /// Soonest first.
  final List<BusArrival> arrivals;

  const ArrivalsBoard({
    required this.stopId,
    required this.fetchedAt,
    required this.arrivals,
  });
}
