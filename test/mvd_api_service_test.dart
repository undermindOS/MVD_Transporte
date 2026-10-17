import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/bus_arrival.dart';
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
