// "Buscar por calles" with real fonts on a phone screen and the largest
// system text: the field, the results and the "too many" hint fit, and the
// stop names are not cut. A file of its own for the Hive reason told at the
// top of test/stop_search_test.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

import 'support/layout.dart';

void main() {
  late Directory hiveDir;
  final catalog =
      File('test/fixtures/proxy_catalog_stops.json').readAsBytesSync();
  final client = MockClient((request) async => switch (request.url.path) {
        '/v1/catalog/stops' => http.Response.bytes(catalog, 200),
        _ => http.Response('{"error":"not_found"}', 404),
      });

  setUpAll(() async {
    await loadBundledFonts();
    hiveDir = await Directory.systemTemp.createTemp('mvd_stop_search_layout');
    await CacheService.init(path: hiveDir.path);
  });

  tearDownAll(() async {
    MvdApiService.proxyUrl = '';
    await hiveDir.delete(recursive: true);
  });

  testWidgets('Text at 2x: the search by streets fits', (tester) async {
    MvdApiService.proxyUrl = 'https://proxy.test';
    usePhoneScreen(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTimbreTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: StopsPage(onOpenStopInComoIr: (_) {}),
      ));
      await tester.tap(find.byTooltip('Agregar parada'));
      await tester.pumpAndSettle();

      final streets = find.widgetWithText(TextField, 'Buscar por calles');
      await tester.enterText(streets, 'san jose andes');
      await tester.pump();
      // The catalog download and its copy in Hive (see stop_search_test)
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      final name = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('SAN JOSE y ANDES')));
      expect(name.didExceedMaxLines, isFalse);

      // A broad search: more than fit, and the hint to narrow it down
      await tester.enterText(streets, 'av');
      await tester.pump();
      expect(find.text('Hay más de 50: agregá la otra calle'), findsOneWidget);
    }, () => client);
  });
}
