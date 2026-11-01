import 'bus_stop.dart';

/// Where one line goes from a stop, with the transporteRest variants that
/// carry that destination label.
class StopDirection {
  final String line;
  final String destination;

  /// Ascending.
  final List<int> variantIds;

  const StopDirection({
    required this.line,
    required this.destination,
    required this.variantIds,
  });
}

/// Name, lines and directions of a stop (/v1 `StopResponse`), for the
/// "Agregar parada" and "Agregar ruta" dialogs.
class StopDetails {
  final int id;

  /// "CALLE y ESQUINA"; null when the source has none.
  final String? name;

  final List<String> lines;

  /// Empty = unknown or none: the UI then falls back to the arrivals.
  final List<StopDirection> directions;

  const StopDetails({
    required this.id,
    required this.name,
    required this.lines,
    required this.directions,
  });

  String get displayName => name ?? 'Parada $id';

  /// A new saved stop with this name and these lines.
  BusStop toBusStop() => BusStop(id: id, name: displayName, lines: [...lines]);
}
