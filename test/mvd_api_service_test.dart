import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stm_app/models/arrivals_board.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/services/api/api_result.dart';
import 'package:stm_app/services/api/proxy_source.dart';
import 'package:stm_app/services/api/v1_parser.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';

// Samples captured from the live API on 2026-10-17.
const _siguientesParada3140 = '''
[{"time":1792233540000,"linea":"145","coordinates":[-56.142532,-34.88331],"destino":"PLAZA ESPAÑA","accesibilidad":true,"hora":739,"variante":8403,"dia_anterior":null,"tipoAccesibilidad":2,"minutos":5,"real":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y LUCIANO ROMERO","idBus":247,"idEmpresa":50,"horaDesc":"7:39"},
 {"time":1792235220000,"linea":"143","coordinates":null,"destino":"CIUDADELA","accesibilidad":false,"hora":807,"variante":4615,"dia_anterior":"N","tipoAccesibilidad":1,"minutos":33,"real":false,"parada_actual":null,"idBus":null,"idEmpresa":null,"horaDesc":"8:07"},
 {"time":1792233540000,"linea":"494","coordinates":[-56.124596,-34.89771],"destino":"RUTA 1 KM 26 (POR COMPEN)","accesibilidad":true,"hora":739,"variante":4498,"dia_anterior":null,"tipoAccesibilidad":2,"minutos":2,"real":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y VERDI","idBus":200,"idEmpresa":10,"horaDesc":"7:39"}]
''';

const _lineas3140 = '''
{"descripcion":"AV RAMON ANADOR y TIBURCIO GOMEZ","lineas":[{"descripcion":"145","codigo":443},{"descripcion":"140","codigo":56},{"descripcion":"143","codigo":61},{"descripcion":"140","codigo":56}]}
''';

// GET /v1/stops/574 as the proxy answers it once the directions are known
const _stop574 = '{"id":574,"name":"SAN JOSE y ANDES",'
    '"lines":["116","117","121","141","142","144","538"],'
    '"directions":[{"line":"116","destination":"POCITOS","variantIds":[630]}]}';

const _directBase = 'https://api.montevideo.gub.uy/transporteRest';

http.Response _json(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  tearDown(() {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
  });

  group('parseArrivals', () {
    // When the answer came: 7:34 in Montevideo
    final fetchedAt = DateTime.utc(2026, 10, 17, 10, 34);
    final arrivals = MvdApiService.parseArrivals(
        jsonDecode(_siguientesParada3140),
        now: fetchedAt);

    test('parses every item and sorts by ETA', () {
      expect(arrivals.map((a) => a.line), ['494', '145', '143']);
      expect(arrivals.map((a) => a.etaMinutes), [2, 5, 33]);
    });

    test('maps real-time GPS data', () {
      final bus = arrivals.firstWhere((a) => a.line == '145');
      expect(bus.state, ArrivalState.live);
      expect(bus.isRealTime, isTrue);
      expect(bus.destination, 'PLAZA ESPAÑA');
      expect(bus.tripId, 'bus-50-247');
      expect(bus.variantId, 8403);
      // The API's own `time`
      expect(bus.expectedAt,
          DateTime.fromMillisecondsSinceEpoch(1792233540000, isUtc: true));
      expect(bus.clockTime, '7:39');
      expect(bus.etaLabel, '5 min');
    });

    test('marks timetable estimates and shows their clock time', () {
      final bus = arrivals.firstWhere((a) => a.line == '143');
      expect(bus.state, ArrivalState.scheduled);
      expect(bus.isRealTime, isFalse);
      expect(bus.tripId, 'sched-4615-807');
      expect(bus.etaLabel, '8:07');
      expect(bus.airConditioning, isNull);
    });

    test('maps wheelchair accessibility', () {
      expect(arrivals.firstWhere((a) => a.line == '145').accessible, isTrue);
      expect(arrivals.firstWhere((a) => a.line == '143').accessible, isFalse);
    });

    test('accessibility defaults when the fields are missing', () {
      final bus = MvdApiService.parseArrivals([
        {'linea': '1', 'minutos': 3, 'real': true},
      ], now: fetchedAt).single;
      expect(bus.accessible, isFalse);
      // No `time`: when the answer came plus the minutes, on the minute
      expect(bus.expectedAt, DateTime.utc(2026, 10, 17, 10, 37));
      expect(bus.clockTime, '7:37');
      expect(bus.tripId, 'sched-0-737');
    });

    test('a bus at the stop is "arriving"', () {
      final bus = MvdApiService.parseArrivals([
        {'linea': '1', 'minutos': -1, 'real': true, 'idEmpresa': 50,
          'idBus': 9},
      ], now: fetchedAt).single;
      expect(bus.state, ArrivalState.arriving);
      expect(bus.etaMinutes, 0);
      expect(bus.etaLabel, 'Llegando');
    });

    test('ignores malformed payloads', () {
      expect(MvdApiService.parseArrivals({'error': 'x'}), isEmpty);
      expect(
          MvdApiService.parseArrivals([
            {'linea': '1'}, // no minutos
            {'linea': '2', 'minutos': 'abc'},
            'garbage',
          ]),
          isEmpty);
    });
  });

  group('parseArrivals on a saved live response', () {
    // test/fixtures/siguientes_parada_3140.json, captured 2026-10-17
    final arrivals = MvdApiService.parseArrivals(jsonDecode(
        File('test/fixtures/siguientes_parada_3140.json').readAsStringSync()));

    test('flags only the accessible GPS bus', () {
      expect(arrivals.map((a) => a.line), ['145', '494', '143']);
      expect(arrivals.map((a) => a.accessible), [true, false, false]);
      expect(arrivals.map((a) => a.isRealTime), [true, false, false]);
    });
  });

  group('the saved proxy answer through V1Parser', () {
    // test/fixtures/proxy_arrivals.json — /v1 arrivals of stop 574, from
    // the proxy's answer captured 2026-10-19
    final board = V1Parser.arrivals(
        jsonDecode(
            File('test/fixtures/proxy_arrivals.json').readAsStringSync()),
        574)!;
    final arrivals = board.arrivals;

    test('keeps every arrival soonest first, with the fetch time', () {
      expect(arrivals.map((a) => a.line),
          ['121', '538', '144', '116', '117', '142']);
      expect(arrivals.map((a) => a.etaMinutes), [1, 3, 4, 6, 8, 12]);
      expect(board.stopId, 574);
      expect(board.fetchedAt, DateTime.utc(2026, 10, 19, 23, 13, 11, 562));
    });

    test('maps GPS data and accessibility like transporteRest', () {
      final bus = arrivals.first;
      expect(bus.isRealTime, isTrue);
      expect(bus.destination, 'PUNTA CARRETAS');
      expect(bus.tripId, 'bus-50-2101');
      expect(bus.variantId, 7884);
      expect(bus.expectedAt, DateTime.utc(2026, 10, 19, 23, 14));
      expect(bus.accessible, isTrue);
    });

    test('maps comfort of GPS buses', () {
      expect(arrivals.map((a) => a.airConditioning),
          [true, null, null, true, true, null]);
      expect(arrivals.map((a) => a.zeroEmission),
          [true, false, null, false, false, null]);
    });

    test('timetable estimates have no comfort', () {
      final bus = arrivals.firstWhere((a) => a.line == '144');
      expect(bus.isRealTime, isFalse);
      expect(bus.etaLabel, '20:17');
      expect(bus.airConditioning, isNull);
    });

    test('a body of the wrong shape is a failure, a bad item is skipped',
        () {
      expect(V1Parser.arrivals([], 574), isNull);
      expect(V1Parser.arrivals({'error': 'upstream_error'}, 574), isNull);
      final partial = V1Parser.arrivals({
        'arrivals': [
          {'line': '1'}, // no tripId, state, minutes…
          {
            'tripId': 'bus-50-1',
            'line': '2',
            'state': 'live',
            'etaMinutes': 3,
            'expectedAt': '2026-10-19T23:16:00.000Z',
            'clockTime': '20:16',
            'airConditioning': 'garbage',
          },
          'garbage',
        ]
      }, 574, now: DateTime.utc(2026, 10, 19, 23, 13))!;
      expect(partial.arrivals.map((a) => (a.line, a.airConditioning)),
          [('2', null)]);
      // No fetchedAt: now
      expect(partial.fetchedAt, DateTime.utc(2026, 10, 19, 23, 13));
    });
  });

  group('requests through the proxy', () {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      return switch (request.url.path) {
        '/v1/stops/574/arrivals' => http.Response.bytes(
            File('test/fixtures/proxy_arrivals.json').readAsBytesSync(), 200),
        '/v1/stops/574' => _json(_stop574),
        '/v1/stops/4321/schedule/saturday/23:05' => _json(
            '{"passes":[{"line":"143","destination":"CIUDADELA",'
            '"time":"23:09","hhmm":2309}]}'),
        '/v1/stops/7' ||
        '/v1/stops/7/arrivals' =>
          _json('{"error":"upstream_error"}', 502),
        '/v1/stops/8/arrivals' => _json('{"error":"upstream_timeout"}', 504),
        _ => _json('{"error":"stop_not_found"}', 404),
      };
    });
    Future<T> run<T>(Future<T> Function() body) =>
        http.runWithClient(body, () => client);

    setUp(() {
      MvdApiService.proxyUrl = 'https://proxy.test';
      requested.clear();
    });

    test('arrivals come from /v1 with comfort', () async {
      final arrivals = await run(() => MvdApiService.getNextArrivals(574));
      expect(requested, ['https://proxy.test/v1/stops/574/arrivals']);
      expect(arrivals!.first.zeroEmission, isTrue);

      final board = await run(() => MvdApiService.getBoard(574));
      expect(board, isA<ApiOk<ArrivalsBoard>>());
      expect(board.valueOrNull!.arrivals, hasLength(6));
    });

    test('a trailing slash in the proxy URL makes no empty path segment',
        () async {
      MvdApiService.proxyUrl = 'https://proxy.test/';
      await run(() => MvdApiService.getBoard(574));
      expect(requested, ['https://proxy.test/v1/stops/574/arrivals']);
    });

    test('stop name, lines and directions come from /v1', () async {
      final details =
          (await run(() => MvdApiService.getStopDetails(574))).valueOrNull!;
      expect(requested, ['https://proxy.test/v1/stops/574']);
      expect(details.displayName, 'SAN JOSE y ANDES');
      expect(details.lines, ['116', '117', '121', '141', '142', '144', '538']);
      expect(details.directions.single.line, '116');
      expect(details.directions.single.destination, 'POCITOS');
      expect(details.directions.single.variantIds, [630]);

      final stop = await run(() => MvdApiService.resolveStop(574));
      expect(stop!.name, 'SAN JOSE y ANDES');
      expect(stop.lines, ['116', '117', '121', '141', '142', '144', '538']);
    });

    test('an unknown stop is reported as such', () async {
      final result = await run(() => MvdApiService.getStopDetails(99999));
      expect((result as ApiError).failure, ApiFailure.notFound);
      await expectLater(run(() => MvdApiService.resolveStop(99999)),
          throwsA(isA<StopNotFoundException>()));
    });

    test('server errors and timeouts are told apart', () async {
      final failed = await run(() => MvdApiService.getBoard(7));
      expect((failed as ApiError).failure, ApiFailure.failed);
      final timeout = await run(() => MvdApiService.getBoard(8));
      expect((timeout as ApiError).failure, ApiFailure.timeout);
      expect(await run(() => MvdApiService.getNextArrivals(7)), isNull);
      expect(await run(() => MvdApiService.resolveStop(7)), isNull);
    });

    test('timetables use the proxy day names', () async {
      final passes = await run(
          () => MvdApiService.getSchedule(4321, DayType.sabado, 23, 5));
      expect(requested,
          ['https://proxy.test/v1/stops/4321/schedule/saturday/23:05']);
      expect(passes!.single.time, '23:09');
      expect(passes.single.hhmm, 2309);
    });
  });

  group('proxy failures', () {
    // Status, body and headers of the answer → the failure the UI gets
    Future<(ApiFailure?, Duration?)> answer(Object reply) async {
      final client = MockClient((_) async => switch (reply) {
            http.Response r => r,
            Exception e => throw e,
            _ => throw ArgumentError(reply),
          });
      final a = await http.runWithClient(
          () => ProxySource('https://proxy.test').catalogStops(),
          () => client);
      return (a.failure, a.retryAfter);
    }

    http.Response error(int status, String code,
            {Map<String, String> headers = const {}}) =>
        http.Response('{"error":"$code"}', status, headers: headers);

    test('follows docs/design/contrato-v1.md', () async {
      expect(await answer(error(404, 'stop_not_found')),
          (ApiFailure.notFound, null));
      expect(await answer(error(404, 'not_found')), (ApiFailure.failed, null));
      expect(
          await answer(error(400, 'bad_request')), (ApiFailure.failed, null));
      expect(await answer(error(429, 'rate_limited')),
          (ApiFailure.busy, const Duration(seconds: 60)));
      expect(
          await answer(error(503, 'upstream_busy',
              headers: {'retry-after': '42'})),
          (ApiFailure.busy, const Duration(seconds: 42)));
      expect(await answer(error(503, 'not_configured')),
          (ApiFailure.unavailable, null));
      expect(await answer(http.Response('<html>', 503)).then((a) => a.$1),
          ApiFailure.failed);
      expect(await answer(error(502, 'upstream_error')),
          (ApiFailure.failed, null));
      expect(await answer(error(500, 'internal_error')),
          (ApiFailure.failed, null));
      expect(await answer(error(504, 'upstream_timeout')),
          (ApiFailure.timeout, null));
      expect(await answer(http.Response('not json', 200)),
          (ApiFailure.failed, null));
      expect(await answer(TimeoutException('slow')),
          (ApiFailure.timeout, null));
      expect(await answer(http.ClientException('offline')),
          (ApiFailure.offline, null));
    });
  });

  group('requests without the proxy', () {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      return switch (request.url.toString()) {
        '$_directBase/lineas/3140' => _json(_lineas3140),
        '$_directBase/lineas/7' => _json('{"lineas":[]}'),
        '$_directBase/lineas/99999' => http.Response.bytes(
            utf8.encode(
                "No existe la ubicación de parada con código '99999'."),
            500),
        '$_directBase/siguientesParada/3140' => _json(_siguientesParada3140),
        '$_directBase/siguientesParada/574' => _json('{}'),
        // A usable row, then one whose time is past any date
        '$_directBase/siguientesParada/4189' => _json(
            '[{"linea":"116","destino":"POCITOS","minutos":3,"real":false,'
            '"variante":630,"hora":2001,"horaDesc":"20:01"},'
            '{"linea":"121","destino":"PUNTA CARRETAS","minutos":5,'
            '"real":false,"variante":881,"hora":2003,"horaDesc":"20:03",'
            '"time":1e20}]'),
        '$_directBase/siguientesParada/3140/HABIL/8:05' => _json(
            '[{"linea":"143","destino":"CIUDADELA","hora":809,'
            '"horaDesc":"8:09","minutos":null,"real":false}]'),
        '$_directBase/siguientesParada/6325' => throw TimeoutException('slow'),
        '$_directBase/siguientesParada/546' =>
          throw http.ClientException('offline'),
        _ => _json('{ "tipo": "BadRequestException", "mensaje": '
            '"... NoExisteTransporteException" }', 500),
      };
    });
    Future<T> run<T>(Future<T> Function() body) =>
        http.runWithClient(body, () => client);

    setUp(requested.clear);

    test('stop name and lines come from transporteRest/lineas', () async {
      final details =
          (await run(() => MvdApiService.getStopDetails(3140))).valueOrNull!;
      expect(requested, ['$_directBase/lineas/3140']);
      expect(details.name, 'AV RAMON ANADOR y TIBURCIO GOMEZ');
      // Deduplicated, in natural order, like the proxy
      expect(details.lines, ['140', '143', '145']);
      // Only the proxy knows the directions
      expect(details.directions, isEmpty);
    });

    test('a stop without a description gets a placeholder name', () async {
      final stop = await run(() => MvdApiService.resolveStop(7));
      expect(stop!.name, 'Parada 7');
      expect(stop.lines, isEmpty);
    });

    test('"No existe" means the stop does not exist', () async {
      final result = await run(() => MvdApiService.getStopDetails(99999));
      expect((result as ApiError).failure, ApiFailure.notFound);
      await expectLater(run(() => MvdApiService.resolveStop(99999)),
          throwsA(isA<StopNotFoundException>()));
    });

    test('arrivals of a stop', () async {
      final board = (await run(() => MvdApiService.getBoard(3140))).valueOrNull!;
      expect(requested, ['$_directBase/siguientesParada/3140']);
      expect(board.arrivals.map((a) => a.line), ['494', '145', '143']);
      expect(board.arrivals.map((a) => a.airConditioning), everyElement(isNull));
    });

    test('an answer of the wrong shape is a failure, not "no buses"',
        () async {
      final result = await run(() => MvdApiService.getBoard(574));
      expect((result as ApiError).failure, ApiFailure.failed);
      final other = await run(() => MvdApiService.getBoard(4));
      expect((other as ApiError).failure, ApiFailure.failed);
    });

    test('a stop with an unusable row does not take the others down',
        () async {
      final boards = await run(() => MvdApiService.getBoards([4189, 3140]));
      expect(boards.keys, unorderedEquals([4189, 3140]));
      expect(boards[3140]!.valueOrNull!.arrivals, hasLength(3));
      // The bad row alone is dropped, as the proxy drops it
      expect(boards[4189]!.valueOrNull!.arrivals.map((a) => a.line), ['116']);
    });

    test('timeouts and lost connections are told apart', () async {
      final timeout = await run(() => MvdApiService.getBoard(6325));
      expect((timeout as ApiError).failure, ApiFailure.timeout);
      final offline = await run(() => MvdApiService.getBoard(546));
      expect((offline as ApiError).failure, ApiFailure.offline);
    });

    test('timetables use the transporteRest day names', () async {
      final passes = await run(
          () => MvdApiService.getSchedule(3140, DayType.habil, 8, 5));
      expect(requested, ['$_directBase/siguientesParada/3140/HABIL/8:05']);
      expect(passes!.single.time, '8:09');
      expect(passes.single.hhmm, 809);
    });
  });

  group('stop ids', () {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      return _json('[]');
    });

    setUp(requested.clear);

    test('only 1 to 9999999 are stops', () {
      expect(MvdApiService.isValidStopId(0), isFalse);
      expect(MvdApiService.isValidStopId(1), isTrue);
      expect(MvdApiService.isValidStopId(9999999), isTrue);
      expect(MvdApiService.isValidStopId(10000000), isFalse);
    });

    for (final proxy in [false, true]) {
      test('others are never requested (${proxy ? 'proxy' : 'direct'})',
          () async {
        if (proxy) MvdApiService.proxyUrl = 'https://proxy.test';
        await http.runWithClient(() async {
          for (final id in [0, 10000000]) {
            final board = await MvdApiService.getBoard(id);
            expect((board as ApiError).failure, ApiFailure.notFound);
            final details = await MvdApiService.getStopDetails(id);
            expect((details as ApiError).failure, ApiFailure.notFound);
            expect(await MvdApiService.getNextArrivals(id), isNull);
            expect(
                await MvdApiService.getSchedule(id, DayType.habil, 8, 0),
                isNull);
            await expectLater(MvdApiService.resolveStop(id),
                throwsA(isA<StopNotFoundException>()));
          }
        }, () => client);
        expect(requested, isEmpty);
      });
    }
  });

  group('getBoards', () {
    late Map<String, Completer<http.Response>> pending;
    final requested = <String>[];
    final client = MockClient((request) {
      requested.add(request.url.path);
      return pending
          .putIfAbsent(request.url.path, Completer<http.Response>.new)
          .future;
    });
    String board(int id) => '{"id":$id,"fetchedAt":"2026-10-19T22:52:10.000Z",'
        '"arrivals":[]}';

    setUp(() {
      MvdApiService.proxyUrl = 'https://proxy.test';
      pending = {};
      requested.clear();
    });

    test('asks each stop once, all at the same time', () async {
      await http.runWithClient(() async {
        final boards = MvdApiService.getBoards([574, 3140, 574]);
        await pumpEventQueue();
        // Both requests are out before either answers
        expect(requested..sort(),
            ['/v1/stops/3140/arrivals', '/v1/stops/574/arrivals']);

        pending['/v1/stops/574/arrivals']!.complete(_json(board(574)));
        pending['/v1/stops/3140/arrivals']!
            .complete(_json('{"error":"upstream_error"}', 502));
        final result = await boards;
        expect(result.keys, unorderedEquals([574, 3140]));
        expect(result[574]!.valueOrNull!.stopId, 574);
        expect((result[3140] as ApiError).failure, ApiFailure.failed);
      }, () => client);
    });

    test('a stop asked twice at once is requested once', () async {
      await http.runWithClient(() async {
        final first = MvdApiService.getBoards([574]);
        final second = MvdApiService.getBoards([3140, 574]);
        await pumpEventQueue();
        expect(requested.where((p) => p == '/v1/stops/574/arrivals'),
            hasLength(1));

        pending.remove('/v1/stops/574/arrivals')!.complete(_json(board(574)));
        pending['/v1/stops/3140/arrivals']!.complete(_json(board(3140)));
        expect((await first)[574]!.valueOrNull, isNotNull);
        expect((await second)[574]!.valueOrNull, isNotNull);

        // Once answered, the next refresh asks again
        final later = MvdApiService.getBoards([574]);
        await pumpEventQueue();
        expect(requested.where((p) => p == '/v1/stops/574/arrivals'),
            hasLength(2));
        pending.remove('/v1/stops/574/arrivals')!
            .complete(_json(board(574)));
        await later;
      }, () => client);
    });
  });

  group('rate limit', () {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.path);
      return _json('{"error":"rate_limited"}', 429)
        ..headers.addAll({'retry-after': '120'});
    });

    test('after a 429 nothing is requested until Retry-After', () async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      await http.runWithClient(() async {
        final first = await MvdApiService.getBoard(574) as ApiError;
        expect(first.failure, ApiFailure.busy);
        expect(first.retryAfter, const Duration(seconds: 120));

        final again = await MvdApiService.getStopDetails(3140) as ApiError;
        expect(again.failure, ApiFailure.busy);
        expect(again.retryAfter!.inSeconds, inInclusiveRange(118, 120));
        expect(await MvdApiService.getNextArrivals(574), isNull);
      }, () => client);
      expect(requested, ['/v1/stops/574/arrivals']);
    });
  });

  group('BusArrival.etaLabel', () {
    BusArrival arrival(int min, ArrivalState state) => BusArrival(
        tripId: 'bus-50-1',
        line: '1',
        state: state,
        etaMinutes: min,
        expectedAt: DateTime.utc(2026, 10, 19, 23, 1),
        clockTime: '20:01');

    test('real-time countdown', () {
      expect(arrival(0, ArrivalState.arriving).etaLabel, 'Llegando');
      expect(arrival(0, ArrivalState.live).etaLabel, 'Llegando');
      expect(arrival(1, ArrivalState.live).etaLabel, '1 min');
      expect(arrival(12, ArrivalState.live).etaLabel, '12 min');
    });

    test('a timetable estimate shows its clock time', () {
      expect(arrival(9, ArrivalState.scheduled).etaLabel, '20:01');
      expect(arrival(0, ArrivalState.scheduled).etaLabel, '20:01');
    });
  });

  test('montevideoClock is UTC−3, hour without a leading zero', () {
    expect(MvdApiService.montevideoClock(DateTime.utc(2026, 10, 19, 23, 1)),
        '20:01');
    expect(MvdApiService.montevideoClock(DateTime.utc(2026, 10, 20, 3, 5)),
        '0:05');
  });

  test('V1Parser.stop falls back to a placeholder name', () {
    final stop = V1Parser.stop({'id': 7, 'name': null}, 7)!;
    expect(stop.displayName, 'Parada 7');
    expect(stop.lines, isEmpty);
    expect(stop.directions, isEmpty);
    expect(V1Parser.stop([], 7), isNull);
  });

  group('stop catalog on a saved live proxy response', () {
    // test/fixtures/proxy_catalog_stops.json: GET /v1/catalog/stops,
    // captured 2026-10-19 (4972 stops), before it had lines
    final parsed = V1Parser.catalog(jsonDecode(
        File('test/fixtures/proxy_catalog_stops.json').readAsStringSync()))!;
    final catalog = parsed.stops;
    List<int> ids(String query, {int limit = 50}) => [
          for (final s
              in MvdApiService.searchStops(catalog, query, limit: limit))
            s.id
        ];

    test('keeps every stop with its location', () {
      expect(catalog, hasLength(4972));
      final stop = catalog.singleWhere((s) => s.id == 574);
      expect(stop.name, 'SAN JOSE y ANDES');
      expect(stop.searchKey, 'san jose y andes');
      expect(stop.latitude, closeTo(-34.90739436, 1e-8));
      expect(stop.longitude, closeTo(-56.198255, 1e-8));
      // Without linesAvailable and lines: no lines
      expect(parsed.linesAvailable, isFalse);
      expect(stop.lines, isEmpty);
    });

    test('stops without street names are listed but never found', () {
      // Stops 23993 and 23994 have no street names
      final stop = catalog.singleWhere((s) => s.id == 23993);
      expect(stop.name, 'Parada 23993');
      expect(stop.searchKey, isEmpty);
      expect(ids('parada'), isEmpty);
      expect(ids('23993'), isEmpty);
    });

    test('finds a stop by both streets, in any order', () {
      expect(ids('san jose andes'), [574]);
      expect(ids('Andes San José'), [574]);
      expect(ids('18 de julio ejido'), [3179]);
      expect(ids('  EJIDO, 18 de Julio '), [3179]);
    });

    test('ignores accents, Ñ and apostrophes', () {
      // "RAMÓN CLAIRAC" in the catalog
      expect(ids('ramon clairac'), containsAll([648, 5818, 5819]));
      // "BV JOSE BATLLE Y ORDOÑEZ" and the misspelt "J BATLLE Y ORDOÐEZ"
      expect(ids('batlle ordoñez', limit: 200),
          containsAll([1199, 5340, 5342]));
      // "BV JOSE BATLLE Y ORDOÑEZ y PANTALEON ARTIGAS",
      // "J BATLLE Y ORDOÐEZ y JOSE ARTIGAS"
      expect(ids('ordonez artigas'), [3114, 5342]);
      // "CNO O´HIGGINS y CNO SANGUINETTI", then the other way round
      const ohiggins = [689, 615, 616, 617, 5065, 6809, 6810];
      expect(ids("o'higgins sanguinetti"), ohiggins);
      expect(ids('ohiggins sanguinetti'), ohiggins);
      expect(ids('higgins sanguinetti'), ohiggins);
    });

    test('a street name typed in a row comes first', () {
      // The 8 stops on San José ("SAN JOSE y ANDES", "EJIDO y SAN JOSE")
      // before "AV GRAL SAN MARTIN y BV JOSE BATLLE…", which has both
      // words but not as one name
      final sanJose = MvdApiService.searchStops(catalog, 'san josé');
      expect(sanJose, hasLength(18));
      expect(sanJose.take(8).map((s) => s.searchKey),
          everyElement(contains('san jose')));
      expect(sanJose.skip(8).map((s) => s.searchKey),
          everyElement(isNot(contains('san jose'))));
      expect(sanJose.map((s) => s.id), contains(574));
      // In a row anywhere in the name counts too
      final julio = MvdApiService.searchStops(catalog, '18 de julio');
      expect(julio.first.name, contains('18 DE JULIO'));
    });

    test('word starts first, then alphabetical', () {
      final rio = MvdApiService.searchStops(catalog, 'rio');
      expect(rio, hasLength(50));
      // "RIO NEGRO", "RIO DE JANEIRO"… before "GREGORIO", "HILARIO"
      expect(rio.map((s) => s.searchKey),
          everyElement(matches(RegExp(r'(^| )rio'))));
      final names = rio.map((s) => s.name).toList();
      expect(names, orderedEquals([...names]..sort()));
    });

    test('finds nothing for an empty query or unknown streets', () {
      expect(ids(''), isEmpty);
      expect(ids(' , '), isEmpty);
      expect(ids('calle que no existe'), isEmpty);
    });

    test('foldForSearch', () {
      expect(MvdApiService.foldForSearch('ESPAÑA Nº 18 (CERVANTES)'),
          'espana n 18 cervantes');
      expect(MvdApiService.foldForSearch('Güemes S/N'), 'guemes s n');
      expect(MvdApiService.foldForSearch('CNO O´HIGGINS'), 'cno ohiggins');
      // "é" typed as "e" + combining accent
      expect(MvdApiService.foldForSearch('José'), 'jose');
    });
  });

  group('with storage', () {
    late Directory hiveDir;
    final catalogBody =
        File('test/fixtures/proxy_catalog_stops.json').readAsBytesSync();
    // With lines, as the proxy answers now
    final withLines = utf8.encode('{"fetchedAt":"2026-10-27T13:22:26.000Z",'
        '"linesAvailable":true,"stops":[{"id":574,"name":"SAN JOSE y ANDES",'
        '"location":{"lat":-34.90739436,"lng":-56.198255},'
        '"lines":["116","117","121","141","142","144","538"]}]}');
    var proxyUp = true;
    List<int>? catalogAnswer;
    http.Response? catalogFailure;
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      if (!proxyUp) throw http.ClientException('offline');
      return switch (request.url.path) {
        '/v1/catalog/stops' => catalogFailure ??
            http.Response.bytes(catalogAnswer ?? catalogBody, 200),
        '/v1/stops/574' => _json(_stop574),
        '/v1/stops/574/arrivals' => _json('{"arrivals":[]}'),
        '/v1/stops/6325' => _json('{"error":"upstream_error"}', 502),
        _ => _json('{"error":"not_found"}', 404),
      };
    });
    Future<int?> load() async => (await http.runWithClient(
            MvdApiService.getStopCatalog, () => client))
        ?.length;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('mvd_catalog_test');
      await CacheService.init(path: hiveDir.path);
    });

    setUp(() async {
      MvdApiService.proxyUrl = 'https://proxy.test';
      MvdApiService.clearCatalogMemory();
      await CacheService.remove(CacheService.keyStopCatalog);
      await CacheService.remove(CacheService.keyStopCatalogFetchedAt);
      proxyUp = true;
      catalogAnswer = null;
      catalogFailure = null;
      requested.clear();
    });

    tearDownAll(() async {
      await hiveDir.delete(recursive: true);
    });

    test('the catalog is not available without the proxy', () async {
      MvdApiService.proxyUrl = '';
      expect(await load(), isNull);
      expect(requested, isEmpty);
    });

    test('the catalog is downloaded once a day and kept on the device',
        () async {
      expect(await load(), 4972);
      expect(requested, ['https://proxy.test/v1/catalog/stops']);

      // Same app session, then a new one (decoded from Hive): no download
      expect(await load(), 4972);
      MvdApiService.clearCatalogMemory();
      expect(await load(), 4972);
      expect(requested, hasLength(1));

      // A day later it is downloaded again
      await CacheService.saveCatalog(
          utf8.decode(catalogBody),
          DateTime.now()
              .subtract(const Duration(days: 1, minutes: 1))
              .millisecondsSinceEpoch);
      expect(await load(), 4972);
      expect(requested, hasLength(2));
    });

    test('the copy lives in its own lazy box, not in the settings', () async {
      expect(await load(), 4972);
      expect(CacheService.get<String>(CacheService.keyStopCatalog), isNull);
      expect(CacheService.catalogFetchedAtMs, isNotNull);
      expect(await CacheService.catalogBody(), contains('"stops"'));

      // Removing either key drops the copy at once
      unawaited(CacheService.remove(CacheService.keyStopCatalogFetchedAt));
      expect(CacheService.catalogFetchedAtMs, isNull);
      expect(await CacheService.catalogBody(), isNull);
    });

    test('the copy on the device keeps lines and location', () async {
      catalogAnswer = withLines;
      expect(await load(), 1);
      MvdApiService.clearCatalogMemory();
      final stop = (await http.runWithClient(
              MvdApiService.getStopCatalog, () => client))!
          .single;
      expect(requested, hasLength(1));
      expect(stop.lines, ['116', '117', '121', '141', '142', '144', '538']);
      expect(stop.latitude, closeTo(-34.90739436, 1e-8));
    });

    test('an old copy is used while the proxy cannot be reached', () async {
      expect(await load(), 4972);
      await CacheService.saveCatalog(utf8.decode(catalogBody), 0);
      MvdApiService.clearCatalogMemory();

      proxyUp = false;
      expect(await load(), 4972);
      expect(requested, hasLength(2));
    });

    test('the catalog is null with no copy and no proxy reachable',
        () async {
      proxyUp = false;
      expect(await load(), isNull);
    });

    test('a busy catalog does not hold back the arrivals', () async {
      catalogFailure = _json('{"error":"upstream_busy"}', 503)
        ..headers.addAll({'retry-after': '42'});
      expect(await load(), isNull);
      final board = await http.runWithClient(
          () => MvdApiService.getBoard(574), () => client);
      expect(board.valueOrNull, isNotNull);
      expect(requested.last, 'https://proxy.test/v1/stops/574/arrivals');
    });

    test('stops saved as "Parada N" get their name and lines', () async {
      await CacheService.saveStop(BusStop(id: 574, name: 'Parada 574'));
      await CacheService.saveStop(BusStop(id: 6325, name: 'Parada 6325'));
      await CacheService.saveStop(BusStop(
          id: 3140,
          name: 'AV RAMON ANADOR y TIBURCIO GOMEZ',
          lines: ['140', '143', '145'],
          notificationsEnabled: true));

      final healed = await http.runWithClient(
          MvdApiService.healPlaceholderStops, () => client);
      expect(healed, 1);
      // 3140 is fine already; 6325 could not be resolved and waits
      expect(requested.map(Uri.parse).map((u) => u.path),
          unorderedEquals(['/v1/stops/574', '/v1/stops/6325']));
      final stop = CacheService.getStop(574)!;
      expect(stop.name, 'SAN JOSE y ANDES');
      expect(stop.lines, ['116', '117', '121', '141', '142', '144', '538']);
      expect(CacheService.getStop(6325)!.name, 'Parada 6325');
      expect(CacheService.getStop(3140)!.notificationsEnabled, isTrue);

      for (final id in [574, 6325, 3140]) {
        await CacheService.deleteStop(id);
      }
    });
  });
}
