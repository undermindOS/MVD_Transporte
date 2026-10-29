// Periodic background check (WorkManager): stop and route alerts notify
// about GPS-tracked buses within their threshold, only inside their
// schedule, and the stop widgets get the boards of the stops they show.
// HTTP, the notifications plugin and the home widget plugin are faked.

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
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/services/notification_service.dart';
import 'package:stm_app/services/stop_widgets_feed.dart';

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
  // What the widgets would read, and which were told to redraw
  final widget = <String, Object?>{};
  final stopRedraws = <String>[];

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
          stopRedraws.add(args!['android'] as String);
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

  group('stop widgets', () {
    var proxyUp = true;
    final proxy = MockClient((request) async {
      requests.add(request.url.path);
      if (!proxyUp) throw http.ClientException('offline');
      return http.Response.bytes(utf8.encode(_v1Answer()), 200);
    });
    Future<List<String>> checkAt(DateTime now) async {
      shown.clear();
      requests.clear();
      await http.runWithClient(
          () => BackgroundWorker.checkAlerts(now), () => proxy);
      return [...shown];
    }

    Map<String, Object?> board() =>
        jsonDecode(widget[StopWidgetsFeed.keyBoard(574)] as String)
            as Map<String, Object?>;

    // What TimbreStopWidget writes for a placed Parada widget on 574
    Future<void> placeWidget() async {
      await CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
      widget
        ..[StopWidgetsFeed.keyShownStops] = '574'
        ..[StopWidgetsFeed.keyPlacedWidgets] = '1';
    }

    setUp(() {
      MvdApiService.proxyUrl = 'https://proxy.test';
      widget.clear();
      stopRedraws.clear();
      proxyUp = true;
    });

    test('no widget placed: nothing is asked for widgets', () async {
      await CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
      expect(await checkAt(_t0), isEmpty);
      expect(requests, isEmpty);
      expect(widget, isEmpty);
      expect(stopRedraws, isEmpty);
    });

    test('the stop widgets get their stops at any hour, without alerts',
        () async {
      await placeWidget();

      expect(await checkAt(_t0), isEmpty);
      expect(requests, ['/v1/stops/574/arrivals']);
      expect(jsonDecode(widget[StopWidgetsFeed.keySavedStops] as String), [
        {'id': 574, 'name': 'SAN JOSE y ANDES'},
      ]);
      expect(board()['checkedAtMs'], _t0.millisecondsSinceEpoch);
      expect((board()['arrivals'] as List).first, {
        'line': '116',
        'dest': 'POCITOS',
        'clock': '19:56',
        'dueMs': _t0.add(const Duration(minutes: 4)).millisecondsSinceEpoch,
        'acc': true,
      });
      expect(stopRedraws, StopWidgetsFeed.providers);
    });

    test('a phone clock 6 min ahead of the proxy: the due time is kept on '
        'the phone\'s clock', () async {
      await placeWidget();
      // The proxy stamped the board at _t0, the phone read _t0 + 6 min
      final phone = _t0.add(const Duration(minutes: 6));
      await checkAt(phone);
      // Due 4 min after the stamp: 10 min after _t0 on the phone's clock
      final dueOnPhone = _t0.add(const Duration(minutes: 10));
      final first = (board()['arrivals'] as List).first as Map;
      expect(first['dueMs'], dueOnPhone.millisecondsSinceEpoch);
      // The time shown is still the source's
      expect(first['clock'], '19:56');
      expect(board()['checkedAtMs'], phone.millisecondsSinceEpoch);

      // Offline 3 min later: the buses stay, the board says it failed
      proxyUp = false;
      final later = phone.add(const Duration(minutes: 3));
      await checkAt(later);
      expect(board()['arrivals'], hasLength(2));
      expect(board()['checkedAtMs'], phone.millisecondsSinceEpoch);
      expect(board()['failedAtMs'], later.millisecondsSinceEpoch);
    });

    test('without the proxy, IM 6 min behind the phone: its Date header '
        'keeps the due time on the phone\'s clock', () async {
      MvdApiService.proxyUrl = '';
      await placeWidget();
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
      final first = (board()['arrivals'] as List).first as Map;
      expect(first['dueMs'],
          imAt.add(const Duration(minutes: 10)).millisecondsSinceEpoch);
      expect(first['clock'], '19:56');
    });
  });
}
