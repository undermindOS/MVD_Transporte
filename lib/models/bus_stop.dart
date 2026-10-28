import 'package:hive_flutter/hive_flutter.dart';
import 'alert_schedule.dart';

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

  // Alert schedule (see [schedule]); stops saved before it are "always"
  @HiveField(7, defaultValue: AlertSchedule.allDays)
  List<int> alertDays;

  @HiveField(8, defaultValue: 0)
  int alertFromMinute;

  @HiveField(9, defaultValue: AlertSchedule.dayMinutes)
  int alertToMinute;

  AlertSchedule get schedule => AlertSchedule(
      days: alertDays, fromMinute: alertFromMinute, toMinute: alertToMinute);

  set schedule(AlertSchedule value) {
    alertDays = [...value.days];
    alertFromMinute = value.fromMinute;
    alertToMinute = value.toMinute;
  }

  BusStop({
    required this.id,
    required this.name,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.lines = const [],
    this.notificationsEnabled = false,
    this.etaAlertMinutes = 5,
    this.alertDays = AlertSchedule.allDays,
    this.alertFromMinute = 0,
    this.alertToMinute = AlertSchedule.dayMinutes,
  });
}
