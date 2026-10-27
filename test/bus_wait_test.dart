// "Estoy esperando": following one trip (model) and the Android service
// handler. HTTP, the plugin channels and storage are faked; the stop 3140
// answer is the live capture in test/fixtures.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/bus_wait.dart';
import 'package:stm_app/services/bus_wait_service.dart';
import 'package:stm_app/services/bus_wait_task.dart';
import 'package:stm_app/services/mvd_api_service.dart';

// When the live answer of stop 3140 came (8:52 in Montevideo)
final _t0 = DateTime.utc(2026, 10, 17, 11, 52);

var _trips = 0;

/// A bus [minutes] away as seen at [at] (default [_t0]). Without [tripId]
/// each bus gets an id of its own, so only line, destination or variant
/// can match it.
BusArrival _bus(String line, int minutes,
        {DateTime? at,
        String destino = 'POCITOS',
        bool real = true,
        String? tripId,
        int? variantId}) =>
    BusArrival(
      tripId: tripId ?? 'trip-${_trips++}',
      variantId: variantId,
      line: line,
      destination: destino,
      state: real ? ArrivalState.live : ArrivalState.scheduled,
      etaMinutes: minutes,
      expectedAt: (at ?? _t0).add(Duration(minutes: minutes)),
      clockTime: '8:07',
    );

/// GET /v1/stops/3140/arrivals at [at]: GPS buses of the 116 to POCITOS.
String _v1Answer(DateTime at, List<(String, int)> buses) => jsonEncode({
      'arrivals': [
        for (final (tripId, minutes) in buses)
          {
            'tripId': tripId,
            'variantId': 630,
            'line': '116',
            'destination': 'POCITOS',
            'state': 'live',
            'etaMinutes': minutes,
            'expectedAt':
                at.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
            'clockTime': '8:07',
            'accessible': false,
            'airConditioning': null,
            'zeroEmission': null,
          }
      ],
    });

String _answer(List<(String, int, bool)> buses) => jsonEncode([
      for (final (line, minutes, real) in buses)
        {
          'linea': line,
          'destino': 'POCITOS',
          'minutos': minutes,
          'real': real,
          'idEmpresa': 50,
          'horaDesc': '8:07',
        }
    ]);

void main() {
  BusWait waitFor(BusArrival trip, {int alertMinutes = 5}) => BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE y AV 8 DE OCTUBRE',
        trip: trip,
        alertMinutes: alertMinutes,
        now: _t0,
      );

  group('BusWait', () {
    final live = MvdApiService.parseArrivals(
        jsonDecode(File('test/fixtures/siguientes_parada_3140.json')
            .readAsStringSync()),
        now: _t0);

    test('follows a GPS trip from the live answer and alerts at the threshold',
        () {
      final trip = live.first; // 145 → BV ARTIGAS Y BV ESPAÑA, 7 min, GPS
      final wait = waitFor(trip);
      expect(wait.title, 'Esperando el 145 → BV ARTIGAS Y BV ESPAÑA');
      expect(wait.tripId, 'bus-50-678');
      // The API's own arrival time (`time`), not the phone clock plus 7 min
      expect(wait.expectedAt, DateTime.utc(2026, 10, 17, 11, 59));

      final first = wait.check(live, _t0);
      expect(first.outcome, WaitOutcome.waiting);
      expect(identical(first.trip, trip), isTrue);
      expect(wait.statusText(first),
          'Llega en 7 min · BV BATLLE y AV 8 DE OCTUBRE');

      final later = _t0.add(const Duration(minutes: 3));
      final closer = [
        _bus('145', 4,
            at: later, destino: trip.destination, tripId: 'bus-50-678'),
        ...live.skip(1),
      ];
      final result = wait.check(closer, later);
      expect(result.outcome, WaitOutcome.alert);
      expect(wait.expectedAt, later.add(const Duration(minutes: 4)));
    });

    test('a timetable trip is followed but never "arriving" without GPS', () {
      final trip = live[1]; // 494, 12 min, no GPS
      expect(trip.tripId, 'sched-4466-904');
      final wait = waitFor(trip);
      final at = _t0.add(const Duration(minutes: 10));
      final result = wait.check([
        _bus('494', 2,
            at: at, destino: trip.destination, real: false, tripId: trip.tripId)
      ], at);
      expect(result.outcome, WaitOutcome.waiting);
      expect(wait.statusText(result),
          'Según horario 8:07, sin GPS todavía · BV BATLLE y AV 8 DE OCTUBRE');
    });

    test('the second bus of a line is not mistaken for the first', () {
      final second = _bus('116', 15);
      final wait = waitFor(second);
      final at = _t0.add(const Duration(minutes: 1));
      final result =
          wait.check([_bus('116', 2, at: at), _bus('116', 14, at: at)], at);
      expect(result.outcome, WaitOutcome.waiting);
      expect(result.trip!.etaMinutes, 14);

      // Frequent line: both buses are plausible, the closer match wins
      final frequent = waitFor(_bus('116', 16), alertMinutes: 8);
      final next = frequent
          .check([_bus('116', 7, at: at), _bus('116', 15, at: at)], at);
      expect(next.outcome, WaitOutcome.waiting);
      expect(next.trip!.etaMinutes, 15);
    });

    test('follows the trip id when two buses of the line are 4 min apart', () {
      final wait = waitFor(_bus('116', 10, tripId: 'bus-50-111'));
      // The followed bus is late; the next one is now where it was expected
      final at = _t0.add(const Duration(minutes: 2));
      final next = _bus('116', 8, at: at, tripId: 'bus-50-222');
      final followed = _bus('116', 12, at: at, tripId: 'bus-50-111');
      final result = wait.check([next, followed], at);
      expect(identical(result.trip, followed), isTrue);
      expect(wait.expectedAt, at.add(const Duration(minutes: 12)));
    });

    test('a timetable trip is still followed once its bus has GPS', () {
      final wait = waitFor(_bus('144', 9,
          destino: 'CEMENTERIO DEL NORTE',
          real: false,
          tripId: 'sched-883-2001',
          variantId: 883));
      final at = _t0.add(const Duration(minutes: 3));
      final tracked = _bus('144', 5,
          at: at,
          destino: 'CEMENTERIO DEL NORTE',
          tripId: 'bus-50-222',
          variantId: 883);
      // Same line and label, another variant, right at the expected time
      final other = _bus('144', 6,
          at: at,
          destino: 'CEMENTERIO DEL NORTE',
          tripId: 'bus-50-333',
          variantId: 884);
      final result = wait.check([other, tracked], at);
      expect(identical(result.trip, tracked), isTrue);
      expect(wait.tripId, 'bus-50-222');

      // From now on it is followed by its new id
      final later = at.add(const Duration(minutes: 1));
      final again = wait.check([
        _bus('144', 3, at: later, tripId: 'bus-50-222', variantId: 883),
      ], later);
      expect(again.outcome, WaitOutcome.alert);
    });

    test('follows tells which row is the waited one', () {
      final a = _bus('116', 4), b = _bus('116', 9), c = _bus('121', 9);
      final wait = waitFor(b);
      final board = [a, b, c];
      expect([for (final x in board) wait.follows(x, board, _t0)],
          [false, true, false]);
    });

    test('a trip no longer listed ends the wait after it was due', () {
      final wait = waitFor(_bus('116', 6));
      final other = [_bus('116', 30)]; // next one, too far to be the same
      expect(wait.check(other, _t0.add(const Duration(minutes: 4))).outcome,
          WaitOutcome.waiting);
      expect(wait.check(other, _t0.add(const Duration(minutes: 9))).outcome,
          WaitOutcome.over);
    });

    test('offline keeps waiting; the wait ends after an hour', () {
      final wait = waitFor(_bus('116', 50));
      final offline = wait.check(null, _t0.add(const Duration(minutes: 1)));
      expect(offline.outcome, WaitOutcome.waiting);
      expect(offline.failed, isTrue);
      expect(wait.statusText(offline), startsWith('Sin conexión'));
      final end = _t0.add(BusWait.maxDuration);
      expect(wait.check([_bus('116', 1, at: end)], end).outcome,
          WaitOutcome.over);
    });

    test('survives a round trip through storage', () {
      final wait = waitFor(
          _bus('64D', 9, tripId: 'sched-7-1201', variantId: 7),
          alertMinutes: 3);
      final copy = BusWait.fromJson(jsonDecode(jsonEncode(wait.toJson())));
      expect(copy.toJson(), wait.toJson());
      expect((copy.tripId, copy.variantId), ('sched-7-1201', 7));
    });

    test('a wait saved before trip ids loads and is followed', () {
      final expected = _t0.add(const Duration(minutes: 9));
      final wait = BusWait.fromJson(jsonDecode(jsonEncode({
        'stopId': 3140,
        'stopName': 'BV BATLLE',
        'line': '116',
        'destination': 'POCITOS',
        'alertMinutes': 5,
        'startedAt': _t0.millisecondsSinceEpoch,
        'expectedAt': expected.millisecondsSinceEpoch,
      })));
      expect((wait.tripId, wait.variantId), (null, null));

      final at = _t0.add(const Duration(minutes: 2));
      final result = wait.check(
          [_bus('116', 7, at: at, tripId: 'bus-50-139', variantId: 630)], at);
      expect(result.trip?.tripId, 'bus-50-139');
      expect(wait.tripId, 'bus-50-139');
    });
  });

  group('Android service handler', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const serviceChannel = MethodChannel('flutter_foreground_task/methods');
    const notificationsChannel =
        MethodChannel('dexterous.com/flutter/local_notifications');
    late List<MethodCall> serviceCalls;
    late List<MethodCall> shown;
    late int minutes;

    final client = MockClient((request) async {
      expect(request.url.path, '/transporteRest/siguientesParada/3140');
      return http.Response(_answer([('116', minutes, true)]), 200);
    });

    // What the Android plugin registrant does in the app
    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

    setUp(() {
      serviceCalls = [];
      shown = [];
      FlutterForegroundTask.skipServiceResponseCheck = true;
      messenger.setMockMethodCallHandler(serviceChannel, (call) async {
        serviceCalls.add(call);
        return call.method == 'isRunningService' ? true : null;
      });
      messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
        if (call.method == 'show') shown.add(call);
        return call.method == 'initialize' ? true : null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(serviceChannel, null);
      messenger.setMockMethodCallHandler(notificationsChannel, null);
    });

    Future<BusWaitTaskHandler> startHandler(BusWait wait) async {
      SharedPreferences.setMockInitialValues({});
      await FlutterForegroundTask.saveData(
          key: busWaitDataKey, value: jsonEncode(wait.toJson()));
      final handler = BusWaitTaskHandler();
      await handler.onStart(DateTime.now(), TaskStarter.developer);
      return handler;
    }

    test('updates the ongoing notification, then alerts and stops', () async {
      minutes = 12;
      final wait = BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE',
        trip: _bus('116', 12, at: DateTime.now()),
        alertMinutes: 5,
        now: DateTime.now(),
      );
      await http.runWithClient(() async {
        final handler = await startHandler(wait);

        final update =
            serviceCalls.singleWhere((c) => c.method == 'updateService');
        expect(jsonEncode(update.arguments),
            contains('Llega en 12 min · BV BATLLE'));
        expect(shown, isEmpty);
        expect(serviceCalls.map((c) => c.method), isNot(contains('stopService')));

        minutes = 4;
        handler.onRepeatEvent(DateTime.now());
        await pumpEventQueue();

        expect(shown, hasLength(1));
        expect(shown.single.arguments['title'], 'Línea 116 — 4 min');
        expect(serviceCalls.map((c) => c.method), contains('stopService'));
      }, () => client);
    });

    test('follows its bus by trip id through the proxy', () async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      addTearDown(() => MvdApiService.proxyUrl = '');
      final now = DateTime.now();
      final wait = BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE',
        trip: _bus('116', 5, at: now, tripId: 'bus-50-111'),
        alertMinutes: 4,
        now: now,
      );
      // The followed bus is late; the next one is 4 min away, about when
      // the followed one was expected
      final proxy = MockClient((request) async {
        expect('${request.url}', 'https://proxy.test/v1/stops/3140/arrivals');
        return http.Response.bytes(
            utf8.encode(
                _v1Answer(now, [('bus-50-222', 4), ('bus-50-111', 12)])),
            200);
      });
      await http.runWithClient(() => startHandler(wait), () => proxy);

      expect(shown, isEmpty);
      final update =
          serviceCalls.singleWhere((c) => c.method == 'updateService');
      expect(jsonEncode(update.arguments),
          contains('Llega en 12 min · BV BATLLE'));
    });

    test('"Dejar de esperar" stops the service without alerting', () async {
      minutes = 20;
      final wait = BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE',
        trip: _bus('116', 20, at: DateTime.now()),
        alertMinutes: 5,
        now: DateTime.now(),
      );
      await http.runWithClient(() async {
        final handler = await startHandler(wait);
        handler.onNotificationButtonPressed(BusWaitTaskHandler.stopButtonId);
        await pumpEventQueue();

        expect(serviceCalls.map((c) => c.method), contains('stopService'));
        // No more polling after stop
        final polls = serviceCalls.length;
        handler.onRepeatEvent(DateTime.now());
        await pumpEventQueue();
        expect(serviceCalls.length, polls);
        expect(shown, isEmpty);
      }, () => client);
    });
  });

  group('iOS reminder', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const notificationsChannel =
        MethodChannel('dexterous.com/flutter/local_notifications');
    final scheduled = <DateTime>[];

    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      scheduled.clear();
      messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
        if (call.method == 'zonedSchedule') {
          scheduled.add(
              DateTime.parse(call.arguments['scheduledDateTimeISO8601']));
        }
        return call.method == 'requestNotificationsPermission' ? true : null;
      });
    });

    tearDown(() =>
        messenger.setMockMethodCallHandler(notificationsChannel, null));

    test('is set for the trip\'s expected time minus the alert minutes',
        () async {
      // Whole seconds: the plugin gets the time with milliseconds
      final now = DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000);
      final trip = _bus('116', 20, at: now, tripId: 'bus-50-111');
      final wait = BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE',
        trip: trip,
        alertMinutes: 5,
        now: now,
      );
      final ios = ScheduledBusWait();
      expect(await ios.start(wait, trip), isTrue);
      expect(scheduled.single,
          trip.expectedAt.subtract(const Duration(minutes: 5)).toUtc());

      // Moved with the followed bus, not the one now where it was expected
      final result = await ios.onArrivals(wait, [
        _bus('116', 20, at: now, tripId: 'bus-50-222'),
        _bus('116', 26, at: now, tripId: 'bus-50-111'),
      ]);
      expect(result, isFalse);
      expect(scheduled.last, now.add(const Duration(minutes: 21)).toUtc());
    });
  });
}
