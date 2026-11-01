import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stm_app/services/bus_status_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';

// GET /v1/status/gps: the contract's golden, one operator partial
final _proxyAnswer = jsonEncode({
  'fetchedAt': '2026-10-27T13:23:30.000Z',
  'operators': [
    {'company': 'COETC', 'percent': 100, 'partial': false},
    {'company': 'UCOT', 'percent': 40, 'partial': true},
  ],
});

void main() {
  setUp(BusStatusService.reset);

  tearDown(() {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
  });

  group('getStatus', () {
    final requests = <Uri>[];
    var answer = http.Response(_proxyAnswer, 200);
    final client = MockClient((request) async {
      requests.add(request.url);
      return answer;
    });
    Future<List<OperatorGpsStatus>?> get() =>
        http.runWithClient(BusStatusService.getStatus, () => client);

    setUp(() {
      requests.clear();
      answer = http.Response(_proxyAnswer, 200);
    });

    test('through the proxy, from /v1/status/gps', () async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      final status = await get();
      expect(requests.map((u) => '$u'), ['https://proxy.test/v1/status/gps']);
      expect(status!.map((s) => '${s.company} ${s.percent} ${s.isPartial}'),
          ['COETC 100 false', 'UCOT 40 true']);
      expect(BusStatusService.partialWarning(status),
          startsWith('Datos GPS parciales (UCOT 40 %)'));
    });

    test('without the proxy, from pci buses/control', () async {
      answer = http.Response(
          File('test/fixtures/buses_control.json').readAsStringSync(), 200);
      final status = await get();
      expect(requests.single.host, 'pci.montevideo.gub.uy');
      expect(status!.map((s) => s.company),
          ['COETC', 'COME', 'CUTCSA', 'UCOT']);
    });

    test('at most one request a minute, failed or not', () async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      answer = http.Response('{"error":"upstream_error"}', 502);
      expect(await get(), isNull);
      answer = http.Response(_proxyAnswer, 200);
      expect(await get(), isNull);
      expect(requests, hasLength(1));

      BusStatusService.reset();
      expect(await get(), hasLength(2));
      expect(requests, hasLength(2));
    });

    test('a failure keeps the last good status', () async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      const good = [OperatorGpsStatus('COETC', 100)];
      final aMinuteAgo = DateTime.now().subtract(BusStatusService.minInterval);
      // The proxy fails, or answers something that is not a status
      for (final failure in [
        http.Response('{"error":"upstream_error"}', 502),
        http.Response('{"operators":"garbage"}', 200),
      ]) {
        answer = failure;
        BusStatusService.seed(good, at: aMinuteAgo);
        expect(await get(), same(good));
      }
      expect(requests, hasLength(2));
    });
  });

  group('parse', () {
    test('saved live response: every operator at 100 %', () {
      // test/fixtures/buses_control.json, captured 2026-10-17
      final status = BusStatusService.parse(jsonDecode(
          File('test/fixtures/buses_control.json').readAsStringSync()));
      expect(status.map((s) => s.company), ['COETC', 'COME', 'CUTCSA', 'UCOT']);
      expect(status.map((s) => s.percent), [100, 100, 100, 100]);
      expect(BusStatusService.partialWarning(status), isNull);
    });

    test('clamps values and skips malformed items', () {
      final status = BusStatusService.parse([
        {'empresa': 'CUTCSA', 'valor': 140},
        {'empresa': 'UCOT', 'valor': -3},
        {'empresa': 'COME', 'valor': 'x'},
        {'valor': 50},
        'garbage',
      ]);
      expect(status.map((s) => '${s.company} ${s.percent}'),
          ['CUTCSA 100', 'UCOT 0']);
      expect(BusStatusService.parse({'error': 1}), isEmpty);
    });
  });

  group('partialWarning', () {
    test('names only the operators below 70 %', () {
      final warning = BusStatusService.partialWarning([
        const OperatorGpsStatus('COETC', 100),
        const OperatorGpsStatus('CUTCSA', 40),
        const OperatorGpsStatus('UCOT', 69),
        const OperatorGpsStatus('COME', 70),
      ]);
      expect(warning, startsWith('Datos GPS parciales (CUTCSA 40 %, UCOT 69 %)'));
      expect(warning, isNot(contains('COME')));
    });

    test('nothing to say without data', () {
      expect(BusStatusService.partialWarning(null), isNull);
      expect(BusStatusService.partialWarning(const []), isNull);
    });
  });
}
