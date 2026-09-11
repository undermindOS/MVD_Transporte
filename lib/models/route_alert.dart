import 'package:hive_flutter/hive_flutter.dart';

part 'route_alert.g.dart';

@HiveType(typeId: 1)
class RouteAlert extends HiveObject {
  @HiveField(0)
  int id;

  /// Stop ID at the departure point (used to query ETA API)
  @HiveField(1)
  int originStopId;

  @HiveField(2)
  String originName;

  @HiveField(3)
  String destinationName;

  /// If empty — show all lines arriving at origin stop.
  /// If set — filter to these lines only.
  @HiveField(4)
  List<String> preferredLines;

  @HiveField(5)
  bool enabled;

  /// Alert threshold: notify when bus is <= this many minutes away
  @HiveField(6)
  int alertMinutes;

  RouteAlert({
    required this.id,
    required this.originStopId,
    required this.originName,
    required this.destinationName,
    this.preferredLines = const [],
    this.enabled = true,
    this.alertMinutes = 5,
  });
}
