import 'package:hive_flutter/hive_flutter.dart';

part 'bus_stop.g.dart';

@HiveType(typeId: 0)
class BusStop extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double latitude;

  @HiveField(3)
  double longitude;

  @HiveField(4)
  List<String> lines;

  @HiveField(5)
  bool notificationsEnabled;

  @HiveField(6)
  int etaAlertMinutes; // notify when bus is <= this many minutes away

  BusStop({
    required this.id,
    required this.name,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.lines = const [],
    this.notificationsEnabled = false,
    this.etaAlertMinutes = 5,
  });
}
