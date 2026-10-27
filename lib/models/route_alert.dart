import 'package:hive_flutter/hive_flutter.dart';
import 'alert_schedule.dart';
import 'bus_arrival.dart';

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

  // Alert schedule (see [schedule]); routes saved before it are "always"
  @HiveField(7, defaultValue: AlertSchedule.allDays)
  List<int> alertDays;

  @HiveField(8, defaultValue: 0)
  int alertFromMinute;

  @HiveField(9, defaultValue: AlertSchedule.dayMinutes)
  int alertToMinute;

  /// Direction filter: API `destino` values ("POCITOS").
  /// If empty — every direction.
  @HiveField(10, defaultValue: <String>[])
  List<String> preferredDestinations;

  AlertSchedule get schedule => AlertSchedule(
      days: alertDays, fromMinute: alertFromMinute, toMinute: alertToMinute);

  set schedule(AlertSchedule value) {
    alertDays = [...value.days];
    alertFromMinute = value.fromMinute;
    alertToMinute = value.toMinute;
  }

  /// Case-insensitive ("64d" == "64D"); an empty list accepts every line.
  bool acceptsLine(String line) {
    final wanted = line.toUpperCase();
    return preferredLines.isEmpty ||
        preferredLines.any((l) => l.toUpperCase() == wanted);
  }

  /// Preferred line and direction.
  bool accepts(BusArrival bus) =>
      acceptsLine(bus.line) &&
      (preferredDestinations.isEmpty ||
          preferredDestinations.contains(bus.destination));

  RouteAlert({
    required this.id,
    required this.originStopId,
    required this.originName,
    required this.destinationName,
    this.preferredLines = const [],
    this.enabled = true,
    this.alertMinutes = 5,
    this.alertDays = AlertSchedule.allDays,
    this.alertFromMinute = 0,
    this.alertToMinute = AlertSchedule.dayMinutes,
    this.preferredDestinations = const [],
  });
}
