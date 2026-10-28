// "Mis paradas" with real fonts on a phone screen: the boards, the error
// after a failed refresh with the last buses as estimates, and the "Estoy
// esperando" sheet keep every word visible with the largest system fonts.
// Any overflow fails the test.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/widgets/cartel.dart';

import 'support/layout.dart';

// The bus at the stop now, one with GPS and one by timetable
const _arrivals574 = '[{"linea":"494","destino":"DELTA DEL TIGRE","minutos":0,'
    '"real":true,"idEmpresa":70,"horaDesc":"8:00"},'
    '{"linea":"121","destino":"PUNTA CARRETAS","minutos":12,'
    '"real":true,"idEmpresa":50,"horaDesc":"8:12","aireAcondicionado":true,'
    '"emisionCero":true},'
    '{"linea":"144","destino":"CEMENTERIO DEL NORTE","minutos":20,'
    '"real":false,"idEmpresa":50,"horaDesc":"20:17"}]';

void main() {
  late Directory hiveDir;
  // The next refresh fails
  var failing = false;

  final client = MockClient((request) async {
    if (failing) return http.Response('', 500);
    if (request.url.path == '/transporteRest/siguientesParada/574') {
      return http.Response(_arrivals574, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    return http.Response('[]', 200);
  });

  setUpAll(() async {
    await loadBundledFonts();
    hiveDir = await Directory.systemTemp.createTemp('mvd_stops_layout');
    await CacheService.init(path: hiveDir.path);
  });

  setUp(() => failing = false);

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpBoard(WidgetTester tester, double scale) async {
    usePhoneScreen(tester);
    CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpWidget(MaterialApp(
      theme: buildTimbreTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: StopsPage(onOpenStopInComoIr: (_) {}),
    ));
    await tester.pump();
    await tester.pump();
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Text at ${scale}x: the board rows fit', (tester) async {
      await http.runWithClient(() async {
        await pumpBoard(tester, scale);
        expect(find.byType(LlegandoChip), findsOneWidget);
        expect(find.text('20:17'), findsOneWidget);
        // The destinations are readable, not cut to a letter or two
        for (final d in ['DELTA DEL TIGRE', 'PUNTA CARRETAS']) {
          final text = tester.renderObject<RenderParagraph>(find.text(d));
          expect(text.didExceedMaxLines, isFalse, reason: '$d at ${scale}x');
        }
      }, () => client);
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('Text at ${scale}x: the error and the estimates fit',
        (tester) async {
      await http.runWithClient(() async {
        await pumpBoard(tester, scale);
        failing = true;
        await tester.pump(StopsPage.autoRefreshInterval);
        await tester.pump();

        final error =
            find.textContaining('No se pudo actualizar. Datos de las');
        expect(error, findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
            isFalse);
        for (final time in ['~8:00', '~8:12', '~20:17']) {
          expect(find.text(time), findsOneWidget, reason: time);
        }
        for (final d in ['DELTA DEL TIGRE', 'PUNTA CARRETAS']) {
          final text = tester.renderObject<RenderParagraph>(find.text(d));
          expect(text.didExceedMaxLines, isFalse, reason: '$d at ${scale}x');
        }
      }, () => client);
    });
  }

  testWidgets('Text at 2x: the tab labels are whole, the bar scrolls',
      (tester) async {
    await http.runWithClient(() async {
      await pumpBoard(tester, 2);
      for (final label in ['Paradas', 'Rutas', 'Novedades']) {
        final text = tester.renderObject<RenderParagraph>(find.text(label));
        expect(text.size.width,
            greaterThanOrEqualTo(text.getMaxIntrinsicWidth(0) - 0.5),
            reason: label);
      }
    }, () => client);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final destination in ['PUNTA CARRETAS', 'DELTA DEL TIGRE']) {
      testWidgets('Text at ${scale}x: the "Estoy esperando" sign keeps '
          '$destination', (tester) async {
        await http.runWithClient(() async {
          await pumpBoard(tester, scale);
          await tester.tap(find.text(destination));
          await tester.pumpAndSettle();
          expect(find.text('Avisarme cuando llegue'), findsOneWidget);
          // The sign keeps the destination: a second line below 150 %, a
          // line of its own above
          final sign = tester.renderObject<RenderParagraph>(find.descendant(
              of: find.byType(CartelTira), matching: find.text(destination)));
          expect(sign.didExceedMaxLines, isFalse);
        }, () => client);
      });
    }
  }
}
