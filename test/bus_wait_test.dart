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
import 'package:stm_app/services/bus_wait_task.dart';
import 'package:stm_app/services/mvd_api_service.dart';

BusArrival _bus(String line, int minutes,
        {String destino = 'POCITOS', bool real = true}) =>
    BusArrival(
      line: line,
      companyCode: 50,
      etaMinutes: minutes,
      etaSeconds: minutes * 60,
      destination: destino,
      isRealTime: real,
      scheduledTime: '8:07',
    );

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
  final t0 = DateTime(2026, 10, 18, 8, 0);

  BusWait waitFor(BusArrival trip, {int alertMinutes = 5}) => BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE y AV 8 DE OCTUBRE',
        trip: trip,
        alertMinutes: alertMinutes,
        now: t0,
      );

  group('BusWait', () {
    final live = MvdApiService.parseArrivals(jsonDecode(
        File('test/fixtures/siguientes_parada_3140.json').readAsStringSync()));

    test('follows a GPS trip from the live answer and alerts at the threshold',
        () {
      final trip = live.first; // 145 → BV ARTIGAS Y BV ESPAÑA, 7 min, GPS
      final wait = waitFor(trip);
      expect(wait.title, 'Esperando el 145 → BV ARTIGAS Y BV ESPAÑA');
      expect(wait.expectedAt, t0.add(const Duration(minutes: 7)));

      final first = wait.check(live, t0);
      expect(first.outcome, WaitOutcome.waiting);
      expect(identical(first.trip, trip), isTrue);
      expect(wait.statusText(first),
          'Llega en 7 min · BV BATLLE y AV 8 DE OCTUBRE');

      final later = t0.add(const Duration(minutes: 3));
      final closer = [_bus('145', 4, destino: trip.destination), ...live.skip(1)];
      final result = wait.check(closer, later);
      expect(result.outcome, WaitOutcome.alert);
      expect(wait.expectedAt, later.add(const Duration(minutes: 4)));
    });

    test('a timetable trip is followed but never "arriving" without GPS', () {
      final trip = live[1]; // 494, 12 min, no GPS
      final wait = waitFor(trip);
      final at = t0.add(const Duration(minutes: 10));
      final result = wait.check(
          [_bus('494', 2, destino: trip.destination, real: false)], at);
      expect(result.outcome, WaitOutcome.waiting);
      expect(wait.statusText(result),
          'Según horario 8:07, sin GPS todavía · BV BATLLE y AV 8 DE OCTUBRE');
    });

    test('the second bus of a line is not mistaken for the first', () {
      final second = _bus('116', 15);
      final wait = waitFor(second);
      final at = t0.add(const Duration(minutes: 1));
      final result = wait.check([_bus('116', 2), _bus('116', 14)], at);
      expect(result.outcome, WaitOutcome.waiting);
      expect(result.trip!.etaMinutes, 14);

      // Frequent line: both buses are plausible, the closer match wins
      final frequent = waitFor(_bus('116', 16), alertMinutes: 8);
      final next = frequent.check([_bus('116', 7), _bus('116', 15)], at);
      expect(next.outcome, WaitOutcome.waiting);
      expect(next.trip!.etaMinutes, 15);
    });

    test('a trip no longer listed ends the wait after it was due', () {
      final wait = waitFor(_bus('116', 6));
      final other = [_bus('116', 30)]; // next one, too far to be the same
      expect(wait.check(other, t0.add(const Duration(minutes: 4))).outcome,
          WaitOutcome.waiting);
      expect(wait.check(other, t0.add(const Duration(minutes: 9))).outcome,
          WaitOutcome.over);
    });

    test('offline keeps waiting; the wait ends after an hour', () {
      final wait = waitFor(_bus('116', 50));
      final offline = wait.check(null, t0.add(const Duration(minutes: 1)));
      expect(offline.outcome, WaitOutcome.waiting);
      expect(offline.failed, isTrue);
      expect(wait.statusText(offline), startsWith('Sin conexión'));
      expect(
          wait.check([_bus('116', 1)], t0.add(BusWait.maxDuration)).outcome,
          WaitOutcome.over);
    });

    test('survives a round trip through storage', () {
      final wait = waitFor(_bus('64D', 9), alertMinutes: 3);
      final copy = BusWait.fromJson(jsonDecode(jsonEncode(wait.toJson())));
      expect(copy.toJson(), wait.toJson());
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
        trip: _bus('116', 12),
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

    test('"Dejar de esperar" stops the service without alerting', () async {
      minutes = 20;
      final wait = BusWait.forTrip(
        stopId: 3140,
        stopName: 'BV BATLLE',
        trip: _bus('116', 20),
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
}
