// Periodic background check (WorkManager): stop and route alerts notify
// about GPS-tracked buses within their threshold, only inside their
// schedule. HTTP, the notifications plugin and the home widget are faked.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/alert_schedule.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/route_alert.dart';
import 'package:stm_app/services/background_worker.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/notification_service.dart';

/// Stop 574: 116 in 4 min and 121 in 8 min with GPS, 117 in 2 min only
/// by the timetable.
final _answer = jsonEncode([
  for (final (line, destino, minutes, real) in [
    ('117', 'CIUDAD VIEJA', 2, false),
    ('116', 'POCITOS', 4, true),
    ('121', 'CENTRO', 8, true),
  ])
    {
      'linea': line,
      'destino': destino,
      'minutos': minutes,
      'real': real,
      'idEmpresa': 50,
      'horaDesc': '8:07',
    }
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const widgetChannel = MethodChannel('home_widget');
  late Directory hiveDir;
  final shown = <String>[];
  final requests = <String>[];

  final client = MockClient((request) async {
    requests.add(request.url.path);
    return http.Response(_answer, 200);
  });

  // 2026-10-19 is a Monday
  DateTime monday(int hour, int minute) =>
      DateTime(2026, 10, 19, hour, minute);
  final saturday = DateTime(2026, 10, 24, 8, 0);
  const commute = AlertSchedule(
      days: [1, 2, 3, 4, 5], fromMinute: 7 * 60 + 30, toMinute: 8 * 60 + 30);

  Future<List<String>> check(DateTime now) async {
    shown.clear();
    requests.clear();
    await http.runWithClient(() => BackgroundWorker.checkAlerts(now),
        () => client);
    return [...shown];
  }

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_background_test');
    await CacheService.init(path: hiveDir.path);
    // What the Android plugin registrant does in the app
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'show') shown.add(call.arguments['title'] as String);
      return call.method == 'initialize' ? true : null;
    });
    messenger.setMockMethodCallHandler(widgetChannel, (_) async => true);
    await NotificationService.init();
  });

  setUp(() async {
    for (final s in CacheService.getAllStops()) {
      await CacheService.deleteStop(s.id);
    }
    for (final r in CacheService.getAllRoutes()) {
      await CacheService.deleteRoute(r.id);
    }
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(widgetChannel, null);
    await hiveDir.delete(recursive: true);
  });

  Future<BusStop> saveStop({int minutes = 5, AlertSchedule? schedule}) async {
    final stop = BusStop(
        id: 574,
        name: 'SAN JOSE y ANDES',
        notificationsEnabled: true,
        etaAlertMinutes: minutes);
    if (schedule != null) stop.schedule = schedule;
    await CacheService.saveStop(stop);
    return stop;
  }

  Future<RouteAlert> saveRoute(
      {int minutes = 5,
      AlertSchedule? schedule,
      List<String> lines = const [],
      List<String> destinations = const []}) async {
    final route = RouteAlert(
      id: 1,
      originStopId: 574,
      originName: 'SAN JOSE y ANDES',
      destinationName: 'Trabajo',
      preferredLines: lines,
      preferredDestinations: destinations,
      alertMinutes: minutes,
    );
    if (schedule != null) route.schedule = schedule;
    await CacheService.saveRoute(route);
    return route;
  }

  group('schedule', () {
    test('a stop alert notifies only inside its days and hours', () async {
      await saveStop(schedule: commute);

      expect(await check(monday(8, 0)), ['Línea 116 — 4 min']);
      // Outside the window the stop is not even requested
      expect(await check(monday(8, 30)), isEmpty);
      expect(requests, isEmpty);
      expect(await check(monday(7, 0)), isEmpty);
      expect(await check(saturday), isEmpty);
    });

    test('a route alert notifies only inside its days and hours', () async {
      await saveRoute(schedule: commute);

      expect(await check(monday(7, 45)), ['Línea 116 → Trabajo']);
      expect(await check(monday(9, 0)), isEmpty);
      expect(await check(saturday), isEmpty);
    });

    test('alerts saved without a schedule notify at any hour', () async {
      await saveStop();
      await saveRoute();

      expect(await check(DateTime(2026, 10, 25, 3, 0)),
          ['Línea 116 — 4 min', 'Línea 116 → Trabajo']);
    });
  });

  group('threshold', () {
    test('a stop alert uses its own number of minutes', () async {
      final stop = await saveStop(minutes: 3);
      // 117 is 2 min away, but without GPS
      expect(await check(monday(8, 0)), isEmpty);

      stop.etaAlertMinutes = 10;
      await stop.save();
      expect(await check(monday(8, 0)),
          ['Línea 116 — 4 min', 'Línea 121 — 8 min']);
    });

    test('a route alert uses its own number of minutes', () async {
      final route = await saveRoute(minutes: 3);
      expect(await check(monday(8, 0)), isEmpty);

      route.alertMinutes = 10;
      await route.save();
      expect(await check(monday(8, 0)),
          ['Línea 116 → Trabajo', 'Línea 121 → Trabajo']);
    });

    test('a route alert keeps to its lines and direction', () async {
      final route = await saveRoute(minutes: 10, lines: ['121']);
      expect(await check(monday(8, 0)), ['Línea 121 → Trabajo']);

      route
        ..preferredLines = []
        ..preferredDestinations = ['POCITOS'];
      await route.save();
      expect(await check(monday(8, 0)), ['Línea 116 → Trabajo']);
    });
  });
}
