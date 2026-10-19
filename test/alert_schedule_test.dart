// Alert schedule (days + hours when stop and route alerts may notify) and
// reading stops/routes saved before the schedule existed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:stm_app/models/alert_schedule.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/route_alert.dart';

void main() {
  // 2026-10-19 is a Monday
  DateTime monday(int hour, int minute) =>
      DateTime(2026, 10, 19, hour, minute);

  group('AlertSchedule', () {
    const commute = AlertSchedule(
        days: [1, 2, 3, 4, 5], fromMinute: 7 * 60 + 30, toMinute: 8 * 60 + 30);

    test('the default allows any moment', () {
      expect(AlertSchedule.always.isAlways, isTrue);
      expect(AlertSchedule.always.allows(monday(0, 0)), isTrue);
      expect(AlertSchedule.always.allows(DateTime(2026, 10, 25, 23, 59)),
          isTrue);
      expect(AlertSchedule.always.label, 'Siempre');
    });

    test('Monday to Friday 7:30–8:30', () {
      expect(commute.allows(monday(7, 29)), isFalse);
      expect(commute.allows(monday(7, 30)), isTrue);
      expect(commute.allows(monday(8, 29)), isTrue);
      expect(commute.allows(monday(8, 30)), isFalse);
      expect(commute.allows(DateTime(2026, 10, 23, 8, 0)), isTrue); // Fri
      expect(commute.allows(DateTime(2026, 10, 24, 8, 0)), isFalse); // Sat
      expect(commute.label, 'Lun a Vie 7:30–8:30');
    });

    test('a window past midnight belongs to the day it starts', () {
      const friday = AlertSchedule(
          days: [5], fromMinute: 23 * 60, toMinute: 60);
      expect(friday.allows(DateTime(2026, 10, 23, 23, 15)), isTrue); // Fri
      expect(friday.allows(DateTime(2026, 10, 24, 0, 30)), isTrue); // Sat
      expect(friday.allows(DateTime(2026, 10, 24, 1, 0)), isFalse);
      expect(friday.allows(DateTime(2026, 10, 24, 23, 15)), isFalse);
      expect(friday.allows(DateTime(2026, 10, 23, 0, 30)), isFalse);
      expect(friday.label, 'Vie 23:00–1:00');
    });

    test('labels', () {
      expect(const AlertSchedule(days: [6, 7]).label, 'Sáb, Dom');
      expect(const AlertSchedule(fromMinute: 18 * 60, toMinute: 20 * 60)
          .label, '18:00–20:00');
      expect(const AlertSchedule(days: [1, 3, 5]).label, 'Lun, Mié, Vie');
    });
  });

  group('direction filter', () {
    BusArrival bus(String line, String destination) => BusArrival(
        line: line,
        companyCode: 50,
        etaMinutes: 5,
        etaSeconds: 300,
        destination: destination);

    test('accepts only the picked directions of the picked lines', () {
      final route = RouteAlert(
        id: 1,
        originStopId: 574,
        originName: 'SAN JOSE y ANDES',
        destinationName: 'Trabajo',
        preferredLines: ['116'],
        preferredDestinations: ['POCITOS'],
      );
      expect(route.accepts(bus('116', 'POCITOS')), isTrue);
      expect(route.accepts(bus('116', 'CIUDAD VIEJA')), isFalse);
      expect(route.accepts(bus('121', 'POCITOS')), isFalse);

      route.preferredDestinations = [];
      expect(route.accepts(bus('116', 'CIUDAD VIEJA')), isTrue);
    });
  });

  group('Hive data saved before the schedule', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mvd_schedule_test');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('reads as "always", with every direction', () async {
      Hive.registerAdapter(_OldBusStopAdapter(), override: true);
      Hive.registerAdapter(_OldRouteAlertAdapter(), override: true);
      final oldStops = await Hive.openBox<BusStop>('stops');
      await oldStops.put(574,
          BusStop(id: 574, name: 'SAN JOSE y ANDES', etaAlertMinutes: 3));
      final oldRoutes = await Hive.openBox<RouteAlert>('routes');
      await oldRoutes.put(
          1,
          RouteAlert(
              id: 1,
              originStopId: 574,
              originName: 'SAN JOSE y ANDES',
              destinationName: 'Centro',
              preferredLines: ['116']));
      await Hive.close();

      Hive.registerAdapter(BusStopAdapter(), override: true);
      Hive.registerAdapter(RouteAlertAdapter(), override: true);
      final stop = (await Hive.openBox<BusStop>('stops')).get(574)!;
      expect(stop.etaAlertMinutes, 3);
      expect(stop.schedule.isAlways, isTrue);
      final route = (await Hive.openBox<RouteAlert>('routes')).get(1)!;
      expect(route.preferredLines, ['116']);
      expect(route.schedule.isAlways, isTrue);
      expect(route.preferredDestinations, isEmpty);

      // New fields survive a round trip
      stop.schedule = const AlertSchedule(
          days: [1, 2, 3, 4, 5], fromMinute: 450, toMinute: 510);
      await stop.save();
      await Hive.close();
      final again = (await Hive.openBox<BusStop>('stops')).get(574)!;
      expect(again.schedule.label, 'Lun a Vie 7:30–8:30');
    });
  });
}

/// The adapters as generated before the schedule fields (7 fields each).
class _OldBusStopAdapter extends TypeAdapter<BusStop> {
  @override
  final int typeId = 0;

  @override
  BusStop read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, BusStop obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.lines)
      ..writeByte(5)
      ..write(obj.notificationsEnabled)
      ..writeByte(6)
      ..write(obj.etaAlertMinutes);
  }
}

class _OldRouteAlertAdapter extends TypeAdapter<RouteAlert> {
  @override
  final int typeId = 1;

  @override
  RouteAlert read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, RouteAlert obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originStopId)
      ..writeByte(2)
      ..write(obj.originName)
      ..writeByte(3)
      ..write(obj.destinationName)
      ..writeByte(4)
      ..write(obj.preferredLines)
      ..writeByte(5)
      ..write(obj.enabled)
      ..writeByte(6)
      ..write(obj.alertMinutes);
  }
}
