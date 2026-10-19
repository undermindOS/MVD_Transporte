import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/services/mvd_api_service.dart';

// Samples captured from the live API on 2026-10-17.
const _siguientesParada3140 = '''
[{"time":1792233540000,"linea":"145","coordinates":[-56.142532,-34.88331],"destino":"PLAZA ESPAÑA","accesibilidad":true,"hora":739,"variante":8403,"dia_anterior":null,"tipoAccesibilidad":2,"minutos":5,"real":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y LUCIANO ROMERO","idBus":247,"idEmpresa":50,"horaDesc":"7:39"},
 {"time":1792235220000,"linea":"143","coordinates":null,"destino":"CIUDADELA","accesibilidad":false,"hora":807,"variante":4615,"dia_anterior":"N","tipoAccesibilidad":1,"minutos":33,"real":false,"parada_actual":null,"idBus":null,"idEmpresa":null,"horaDesc":"8:07"},
 {"time":1792233540000,"linea":"494","coordinates":[-56.124596,-34.89771],"destino":"RUTA 1 KM 26 (POR COMPEN)","accesibilidad":true,"hora":739,"variante":4498,"dia_anterior":null,"tipoAccesibilidad":2,"minutos":2,"real":true,"parada_actual":"BV JOSE BATLLE Y ORDOÑEZ y VERDI","idBus":200,"idEmpresa":10,"horaDesc":"7:39"}]
''';

const _lineas3140 = '''
{"descripcion":"AV RAMON ANADOR y TIBURCIO GOMEZ","lineas":[{"descripcion":"140","codigo":56},{"descripcion":"143","codigo":61},{"descripcion":"145","codigo":443}]}
''';

void main() {
  group('parseArrivals', () {
    final arrivals =
        MvdApiService.parseArrivals(jsonDecode(_siguientesParada3140));

    test('parses every item and sorts by ETA', () {
      expect(arrivals.map((a) => a.line), ['494', '145', '143']);
      expect(arrivals.map((a) => a.etaMinutes), [2, 5, 33]);
    });

    test('maps real-time GPS data', () {
      final bus = arrivals.firstWhere((a) => a.line == '145');
      expect(bus.isRealTime, isTrue);
      expect(bus.destination, 'PLAZA ESPAÑA');
      expect(bus.companyName, 'CUTCSA');
      expect(bus.busLongitude, closeTo(-56.142532, 1e-6));
      expect(bus.busLatitude, closeTo(-34.88331, 1e-6));
    });

    test('marks timetable estimates and shows their clock time', () {
      final bus = arrivals.firstWhere((a) => a.line == '143');
      expect(bus.isRealTime, isFalse);
      expect(bus.busLatitude, isNull);
      expect(bus.etaLabel, '8:07');
    });

    test('maps wheelchair accessibility', () {
      final accessible = arrivals.firstWhere((a) => a.line == '145');
      expect(accessible.accessible, isTrue);
      expect(accessible.accessibilityType, 2);

      final notAccessible = arrivals.firstWhere((a) => a.line == '143');
      expect(notAccessible.accessible, isFalse);
      expect(notAccessible.accessibilityType, 1);
    });

    test('accessibility defaults when the fields are missing', () {
      final bus = MvdApiService.parseArrivals([
        {'linea': '1', 'minutos': 3, 'real': true},
      ]).single;
      expect(bus.accessible, isFalse);
      expect(bus.accessibilityType, isNull);
    });

    test('ignores malformed payloads', () {
      expect(MvdApiService.parseArrivals({'error': 'x'}), isEmpty);
      expect(
          MvdApiService.parseArrivals([
            {'linea': '1'}, // no minutos
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
      expect(arrivals.map((a) => a.accessibilityType), [2, 1, 1]);
    });
  });

  group('parseStop', () {
    test('uses the street-corner description as name', () {
      final stop = MvdApiService.parseStop(3140, jsonDecode(_lineas3140))!;
      expect(stop.id, 3140);
      expect(stop.name, 'AV RAMON ANADOR y TIBURCIO GOMEZ');
      expect(stop.lines, ['140', '143', '145']);
    });

    test('falls back to a placeholder name', () {
      final stop = MvdApiService.parseStop(7, {'lineas': []})!;
      expect(stop.name, 'Parada 7');
    });
  });

  group('parseProxyArrivals on a saved live proxy response', () {
    // test/fixtures/proxy_arrivals.json — proxy /v1 over transporteRest and
    // the official IM API, stop 574, captured 2026-10-19
    final arrivals = MvdApiService.parseProxyArrivals(jsonDecode(
        File('test/fixtures/proxy_arrivals.json').readAsStringSync()));

    test('keeps every arrival soonest first', () {
      expect(arrivals.map((a) => a.line),
          ['121', '538', '144', '116', '117', '142']);
      expect(arrivals.map((a) => a.etaMinutes), [1, 3, 4, 6, 8, 12]);
    });

    test('maps GPS data and accessibility like transporteRest', () {
      final bus = arrivals.first;
      expect(bus.isRealTime, isTrue);
      expect(bus.destination, 'PUNTA CARRETAS');
      expect(bus.companyName, 'CUTCSA');
      expect(bus.busLatitude, closeTo(-34.907887, 1e-6));
      expect(bus.busLongitude, closeTo(-56.203384, 1e-6));
      expect(bus.accessible, isTrue);
      expect(bus.accessibilityType, 2);
    });

    test('maps comfort of GPS buses', () {
      expect(arrivals.map((a) => a.airConditioning),
          [true, null, null, true, true, null]);
      expect(arrivals.map((a) => a.zeroEmission),
          [true, false, null, false, false, null]);
    });

    test('timetable estimates have no position and no comfort', () {
      final bus = arrivals.firstWhere((a) => a.line == '144');
      expect(bus.isRealTime, isFalse);
      expect(bus.busLatitude, isNull);
      expect(bus.etaLabel, '20:17');
      expect(bus.companyName, 'STM');
    });

    test('ignores malformed payloads', () {
      expect(MvdApiService.parseProxyArrivals([]), isEmpty);
      expect(MvdApiService.parseProxyArrivals({'error': 'upstream_error'}),
          isEmpty);
      expect(
          MvdApiService.parseProxyArrivals({
            'arrivals': [
              {'line': '1'}, // no etaMinutes
              {'line': '2', 'etaMinutes': 3, 'vehicle': 'garbage'},
              'garbage',
            ]
          }).map((a) => (a.line, a.airConditioning)),
          [('2', null)]);
    });
  });

  group('requests through the proxy', () {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.toString());
      return switch (request.url.path) {
        '/v1/stops/574/arrivals' => http.Response.bytes(
            File('test/fixtures/proxy_arrivals.json').readAsBytesSync(), 200),
        '/v1/stops/574' => http.Response.bytes(
            utf8.encode('{"id":574,"name":"SAN JOSE y ANDES",'
                '"lines":["116","117"]}'),
            200),
        '/v1/stops/4321/schedule/saturday/23:05' => http.Response(
            '{"passes":[{"line":"143","destination":"CIUDADELA",'
            '"time":"23:09","hhmm":2309}]}',
            200),
        _ => http.Response('{"error":"stop_not_found"}', 404),
      };
    });

    setUp(() {
      MvdApiService.proxyUrl = 'https://proxy.test';
      requested.clear();
    });
    tearDown(() => MvdApiService.proxyUrl = '');

    test('arrivals come from /v1 with comfort', () async {
      final arrivals = await http.runWithClient(
          () => MvdApiService.getNextArrivals(574), () => client);
      expect(requested, ['https://proxy.test/v1/stops/574/arrivals']);
      expect(arrivals!.first.zeroEmission, isTrue);
    });

    test('stop name and lines come from /v1', () async {
      final stop = await http.runWithClient(
          () => MvdApiService.resolveStop(574), () => client);
      expect(requested, ['https://proxy.test/v1/stops/574']);
      expect(stop!.name, 'SAN JOSE y ANDES');
      expect(stop.lines, ['116', '117']);
    });

    test('an unknown stop is reported as such', () async {
      await expectLater(
          http.runWithClient(
              () => MvdApiService.resolveStop(99999), () => client),
          throwsA(isA<StopNotFoundException>()));
    });

    test('timetables use the proxy day names', () async {
      final passes = await http.runWithClient(
          () => MvdApiService.getSchedule(4321, DayType.sabado, 23, 5),
          () => client);
      expect(requested,
          ['https://proxy.test/v1/stops/4321/schedule/saturday/23:05']);
      expect(passes!.single.time, '23:09');
      expect(passes.single.hhmm, 2309);
    });
  });

  group('parseProxyStop', () {
    test('falls back to a placeholder name', () {
      final stop = MvdApiService.parseProxyStop(7, {'id': 7, 'name': null})!;
      expect(stop.name, 'Parada 7');
      expect(stop.lines, isEmpty);
    });
  });

  group('BusArrival.etaLabel', () {
    BusArrival realTime(int min) => BusArrival(
        line: '1', companyCode: 50, etaMinutes: min, etaSeconds: min * 60);

    test('real-time countdown', () {
      expect(realTime(0).etaLabel, 'Llegando');
      expect(realTime(1).etaLabel, '1 min');
      expect(realTime(12).etaLabel, '12 min');
    });
  });
}
