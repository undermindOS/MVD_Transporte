import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/schedule_page.dart';

// Live responses of /transporteRest/siguientesParada/3140/{tipoDia}/{H:MM},
// captured 2026-10-17.
dynamic _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  final habil = _fixture('siguientes_parada_3140_habil_8-00.json');
  final sabado = _fixture('siguientes_parada_3140_sabado_23-30.json');

  group('parseSchedule', () {
    test('parses a weekday timetable in API order', () {
      final passes = MvdApiService.parseSchedule(habil);
      expect(passes, hasLength(50));
      expect(passes.first.line, '145');
      expect(passes.first.destination, 'PLAZA ESPAÑA');
      expect(passes.first.time, '8:03');
      expect(passes.first.hhmm, 803);
      expect(passes.last.time, '11:18');
    });

    test('keeps the wrap past midnight', () {
      final passes = MvdApiService.parseSchedule(sabado);
      expect(passes.take(3).map((p) => p.time), ['23:31', '23:54', '0:17']);
      expect(passes[2].hhmm, 17);
    });

    test('timetable items are not arrivals (minutos is null)', () {
      // Why a separate parser: parseArrivals skips items without minutos
      expect(MvdApiService.parseArrivals(habil), isEmpty);
    });

    test('ignores malformed payloads', () {
      expect(MvdApiService.parseSchedule({'x': 1}), isEmpty);
      expect(
          MvdApiService.parseSchedule([
            {'linea': '1'}, // no horaDesc
            'garbage',
          ]),
          isEmpty);
    });
  });

  group('DayType', () {
    test('follows the weekday like Cómo Ir', () {
      expect(DayType.of(DateTime(2026, 10, 16)), DayType.habil); // Friday
      expect(DayType.of(DateTime(2026, 10, 17)), DayType.sabado);
      expect(DayType.of(DateTime(2026, 10, 18)), DayType.domingo);
      expect(DayType.domingo.apiValue, 'DOMINGO');
    });
  });

  group('SchedulePage', () {
    final stop = BusStop(id: 3140, name: 'AV RAMON ANADOR y TIBURCIO GOMEZ');
    final requests = <String>[];

    Future<void> pump(WidgetTester tester,
        {List<ScheduledPass>? Function(DayType day)? answer}) {
      requests.clear();
      return tester.pumpWidget(MaterialApp(
        home: SchedulePage(
          stop: stop,
          // Saturday 23:33 → SABADO from 23:30
          now: DateTime(2026, 10, 17, 23, 33),
          fetch: (id, day, h, m) async {
            requests.add('$id/${day.apiValue}/$h:$m');
            return answer == null
                ? MvdApiService.parseSchedule(sabado)
                : answer(day);
          },
        ),
      ));
    }

    testWidgets('starts at today and now, marks midnight', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(requests, ['3140/SABADO/23:30']);
      expect(find.text('Desde 23:30'), findsOneWidget);
      expect(find.text('23:31'), findsOneWidget);
      expect(find.text('Después de medianoche'), findsOneWidget);
    });

    testWidgets('changing the day reloads', (tester) async {
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Domingos'));
      await tester.pumpAndSettle();
      expect(requests.last, '3140/DOMINGO/23:30');
    });

    testWidgets('network error is not "no buses"', (tester) async {
      await pump(tester, answer: (_) => null);
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar el horario'), findsOneWidget);
      expect(find.text('Sin pasadas para este horario'), findsNothing);
    });
  });
}
