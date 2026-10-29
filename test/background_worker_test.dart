// Periodic background check (WorkManager): stop and route alerts notify
// about GPS-tracked buses within their threshold, only inside their
// schedule, and the home widget shows the first route's next bus. HTTP,
// the notifications plugin and the home widget are faked.

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
import 'package:stm_app/services/home_widget_feed.dart';
import 'package:stm_app/services/mvd_api_service.dart';
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

// When the proxy answered for stop 574 (19:52 in Montevideo)
final _t0 = DateTime.utc(2026, 10, 19, 22, 52);

/// GET /v1/stops/574/arrivals at [_t0]: 116 with GPS in 4 min to
/// [destination], 121 in 9 min.
String _v1Answer({String destination = 'POCITOS'}) => jsonEncode({
      'id': 574,
      'fetchedAt': _t0.toIso8601String(),
      'arrivals': [
        for (final (trip, line, dest, minutes, clock) in [
          ('bus-50-139', '116', destination, 4, '19:56'),
          ('bus-50-1118', '121', 'PUNTA CARRETAS', 9, '20:01'),
        ])
          {
            'tripId': trip,
            'variantId': null,
            'line': line,
            'destination': dest,
            'state': 'live',
            'etaMinutes': minutes,
            'expectedAt':
                _t0.add(Duration(minutes: minutes)).toIso8601String(),
            'clockTime': clock,
            'accessible': true,
            'airConditioning': null,
            'zeroEmission': null,
          }
      ],
    });

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
  // What the widget would read, and how often it was told to redraw
  final widget = <String, Object?>{};
  var redraws = 0;

  var client = MockClient((request) async {
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
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'saveWidgetData':
          widget[args!['id'] as String] = args['data'];
        case 'getWidgetData':
          return widget[args!['id'] as String];
        case 'updateWidget':
          expect(args!['name'], 'MVDTransporteWidgetProvider');
          redraws++;
      }
      return true;
    });
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

  tearDown(() {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
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
      {int id = 1,
      int origin = 574,
      int minutes = 5,
      AlertSchedule? schedule,
      List<String> lines = const [],
      List<String> destinations = const []}) async {
    final route = RouteAlert(
      id: id,
      originStopId: origin,
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

    test('a bus at the stop is "llegando", not "0 min"', () async {
      await saveStop();
      final normal = client;
      client = MockClient((request) async => http.Response(
          jsonEncode([
            {'linea': '116', 'minutos': 0, 'real': true, 'horaDesc': '8:07'}
          ]),
          200));
      addTearDown(() => client = normal);

      expect(await check(monday(8, 0)), ['Línea 116 — llegando']);
    });
  });

  group('requests', () {
    // Saturday 0:00 to 1:00 only
    const saturdayNight =
        AlertSchedule(days: [6], fromMinute: 0, toMinute: 60);

    test('each stop is requested once, only when needed', () async {
      await saveStop(); // 574, at any hour
      await CacheService.saveStop(BusStop(
          id: 3140,
          name: 'BV BATLLE',
          notificationsEnabled: true,
          etaAlertMinutes: 5)
        ..schedule = saturdayNight);
      await saveRoute(); // from 574 too: the widget's route
      await saveRoute(id: 2, origin: 6325, schedule: saturdayNight);

      expect(await check(monday(8, 0)),
          ['Línea 116 — 4 min', 'Línea 116 → Trabajo']);
      // 3140 and 6325 are outside their schedule; 574 is asked once
      expect(requests, ['/transporteRest/siguientesParada/574']);
    });

    test('a stop that cannot be checked gives no alert', () async {
      await saveStop();
      await saveRoute();
      final online = client;
      client = MockClient((request) async {
        requests.add(request.url.path);
        throw http.ClientException('offline');
      });
      addTearDown(() => client = online);

      expect(await check(monday(8, 0)), isEmpty);
      expect(requests, hasLength(1));
    });
  });

  group('home widget', () {
    var proxyUp = true;
    var destination = 'POCITOS';
    final proxy = MockClient((request) async {
      requests.add(request.url.path);
      if (!proxyUp) throw http.ClientException('offline');
      return http.Response.bytes(
          utf8.encode(_v1Answer(destination: destination)), 200);
    });
    Future<List<String>> checkAt(DateTime now) async {
      shown.clear();
      requests.clear();
      await http.runWithClient(
          () => BackgroundWorker.checkAlerts(now), () => proxy);
      return [...shown];
    }

    setUp(() {
      MvdApiService.proxyUrl = 'https://proxy.test';
      widget.clear();
      redraws = 0;
      proxyUp = true;
      destination = 'POCITOS';
    });

    test('shows the next bus of the first route, then keeps it offline',
        () async {
      await saveRoute(lines: ['116']);

      expect(await checkAt(_t0), ['Línea 116 → Trabajo']);
      final due = _t0.add(const Duration(minutes: 4));
      expect(widget, {
        WidgetFeed.keyLine: '116',
        // The bus's own destination, as in "Línea 116 a POCITOS"
        WidgetFeed.keyDestination: 'POCITOS',
        WidgetFeed.keyEtaMinutes: 4,
        WidgetFeed.keyClockTime: '19:56',
        WidgetFeed.keyExpectedAtMs: '${due.millisecondsSinceEpoch}',
        WidgetFeed.keyCheckedAtMs: '${_t0.millisecondsSinceEpoch}',
        WidgetFeed.keyStatus: 'ok',
      });
      expect(redraws, 1);

      // Offline before the bus is due: no alert, the row stays
      proxyUp = false;
      expect(await checkAt(_t0.add(const Duration(minutes: 2))), isEmpty);
      expect(widget[WidgetFeed.keyLine], '116');
      expect(widget[WidgetFeed.keyStatus], 'offline');
      expect(widget[WidgetFeed.keyCheckedAtMs],
          '${_t0.millisecondsSinceEpoch}');
      expect(redraws, 2);

      // Offline after it was due: the empty state
      expect(await checkAt(_t0.add(const Duration(minutes: 5))), isEmpty);
      expect(widget[WidgetFeed.keyLine], isNull);
      expect(widget[WidgetFeed.keyStatus], 'offline');
      expect(redraws, 3);
    });

    test('a phone clock 6 min ahead of the proxy: the due time is kept on '
        'the phone\'s clock', () async {
      await saveRoute(lines: ['116']);
      // The proxy stamped the board at _t0, the phone read _t0 + 6 min
      final phone = _t0.add(const Duration(minutes: 6));
      await checkAt(phone);
      // Due 4 min after the stamp: 10 min after _t0 on the phone's clock
      final dueOnPhone = _t0.add(const Duration(minutes: 10));
      expect(widget[WidgetFeed.keyExpectedAtMs],
          '${dueOnPhone.millisecondsSinceEpoch}');
      // The time shown is still the source's
      expect(widget[WidgetFeed.keyClockTime], '19:56');
      expect(widget[WidgetFeed.keyCheckedAtMs],
          '${phone.millisecondsSinceEpoch}');

      // Offline 3 min later: still due on the phone's clock, the row stays
      proxyUp = false;
      await checkAt(phone.add(const Duration(minutes: 3)));
      expect(widget[WidgetFeed.keyLine], '116');
      expect(widget[WidgetFeed.keyStatus], 'offline');
      // 5 min later it was due: the empty state
      await checkAt(phone.add(const Duration(minutes: 5)));
      expect(widget[WidgetFeed.keyLine], isNull);
    });

    test('without the proxy, IM 6 min behind the phone: its Date header '
        'keeps the due time on the phone\'s clock', () async {
      MvdApiService.proxyUrl = '';
      await saveRoute(lines: ['116']);
      // IM answered at imAt by its Date header, the phone read imAt + 6 min.
      // The test's clock, to the second as the header is: a Date a day off
      // the phone's clock is not taken
      final imAt = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
          isUtc: true);
      final due = imAt.add(const Duration(minutes: 4));
      final im = MockClient((request) async => http.Response(
          jsonEncode([
            {
              'linea': '116',
              'destino': 'POCITOS',
              'minutos': 4,
              'real': true,
              'idEmpresa': 50,
              'idBus': 139,
              'horaDesc': '19:56',
              'time': due.millisecondsSinceEpoch,
            }
          ]),
          200,
          headers: {'date': HttpDate.format(imAt)}));
      final phone = imAt.add(const Duration(minutes: 6));
      await http.runWithClient(
          () => BackgroundWorker.checkAlerts(phone), () => im);

      // Due 4 min after IM's stamp: 10 min after imAt on the phone's clock
      final dueOnPhone = imAt.add(const Duration(minutes: 10));
      expect(widget[WidgetFeed.keyExpectedAtMs],
          '${dueOnPhone.millisecondsSinceEpoch}');
      expect(widget[WidgetFeed.keyClockTime], '19:56');
    });

    test('no bus of the route coming, or no route at all', () async {
      final route = await saveRoute(lines: ['999']);
      await checkAt(_t0);
      expect(widget[WidgetFeed.keyLine], isNull);
      expect(widget[WidgetFeed.keyStatus], 'none');
      expect(widget[WidgetFeed.keyCheckedAtMs],
          '${_t0.millisecondsSinceEpoch}');

      // Only a stop alert left: nothing for the widget, only its stop asked
      route.enabled = false;
      await route.save();
      await saveStop();
      await checkAt(_t0);
      expect(widget[WidgetFeed.keyLine], isNull);
      expect(widget[WidgetFeed.keyStatus], 'off');
      expect(requests, ['/v1/stops/574/arrivals']);
    });

    test('a bus without a destination shows the route\'s name', () async {
      destination = '';
      await saveRoute(lines: ['116']);
      await checkAt(_t0);
      expect(widget[WidgetFeed.keyDestination], 'Trabajo');
    });

    test('sync() without alerts empties the widget', () async {
      widget[WidgetFeed.keyLine] = '116';
      await BackgroundWorker.sync();
      await pumpEventQueue(); // the widget is not awaited
      expect(widget[WidgetFeed.keyLine], isNull);
      expect(widget[WidgetFeed.keyStatus], 'off');
      expect(redraws, 1);
    });

    test('sync() empties the widget when no route is left, even with a stop '
        'alert', () async {
      final route = await saveRoute(lines: ['116']);
      await saveStop();
      widget
        ..[WidgetFeed.keyLine] = '116'
        ..[WidgetFeed.keyStatus] = 'ok';

      route.enabled = false;
      await route.save();
      await BackgroundWorker.sync();
      await pumpEventQueue(); // the widget is not awaited
      expect(widget[WidgetFeed.keyLine], isNull);
      expect(widget[WidgetFeed.keyStatus], 'off');
    });
  });
}
