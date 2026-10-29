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

/// A board and when it reached the phone, on the phone's clock. How old a
/// board is gets measured from [receivedAt], as Mis paradas does:
/// [ArrivalsBoard.fetchedAt] is on the source's clock (the proxy's), and a
/// phone a minute or more off would make every board look old, or new.
typedef ReceivedBoard = ({ArrivalsBoard board, DateTime receivedAt});
