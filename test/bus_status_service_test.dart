import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/bus_status_service.dart';

void main() {
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
