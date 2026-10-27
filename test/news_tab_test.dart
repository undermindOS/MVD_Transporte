import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/bus_status_service.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/transport_news_service.dart';
import 'package:stm_app/ui/stops_page.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_news_tab_test');
    await CacheService.init(path: hiveDir.path);

    // Saved live page (ids 171–180), fetched "just now" so the page shows
    // the cache without going to the network
    final page = TransportNewsService.parsePage(jsonDecode(
        File('test/fixtures/mensajes_from170.json').readAsStringSync()))!;
    await CacheService.set(
        CacheService.keyNewsCache,
        jsonEncode(TransportNewsService.merge([], page.messages)
            .map((n) => n.toJson())
            .toList()));
    await CacheService.set(
        CacheService.keyNewsFetchedAt, DateTime.now().millisecondsSinceEpoch);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  testWidgets('Novedades: unread badge, newest first, detail sheet',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        MaterialApp(home: StopsPage(onOpenStopInComoIr: (_) {})));
    await tester.pump();

    // Never opened: all 10 unread, said as such, not a bare number
    expect(find.text('10'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('10 novedades sin leer')),
        findsOneWidget);
    handle.dispose();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Novedades'));
    await tester.pumpAndSettle();

    // Opening the tab marks them read; no "add" button for news
    expect(TransportNewsService.lastReadId, 180);
    expect(find.text('10'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Newest first: 180 (2 Oct) above 179 (24 Sep)
    final newest = tester.getTopLeft(find.text('Líneas patrimoniales')).dy;
    final older = tester
        .getTopLeft(find.text('Desvíos por la Marcha por la Diversidad 2026'))
        .dy;
    expect(newest, lessThan(older));

    await tester.tap(find.text('Líneas patrimoniales'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Día del Patrimonio'), findsWidgets);
    expect(find.text('Ver más'), findsOneWidget);
  });

  testWidgets('GPS warning above saved stops when an operator is partial',
      (tester) async {
    // Real file IO does not complete inside the fake-async test zone
    await tester.runAsync(
        () => CacheService.saveStop(BusStop(id: 3140, name: 'Parada 3140')));
    BusStatusService.seed(const [
      OperatorGpsStatus('COETC', 100),
      OperatorGpsStatus('CUTCSA', 40),
    ]);

    await tester.pumpWidget(
        MaterialApp(home: StopsPage(onOpenStopInComoIr: (_) {})));
    await tester.pump();

    expect(find.textContaining('Datos GPS parciales (CUTCSA 40 %)'),
        findsOneWidget);
    // Above the stop card
    expect(
        tester.getTopLeft(find.textContaining('Datos GPS parciales')).dy,
        lessThan(tester.getTopLeft(find.text('Parada 3140')).dy));

    await tester.runAsync(() => CacheService.deleteStop(3140));
  });
}
