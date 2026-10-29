// "Mis paradas" through the proxy: each stop is asked once, in parallel,
// only while the page is on screen; a failed refresh keeps the last buses
// as estimates; a gone stop and a busy proxy are told apart; the waited
// bus is found by its trip id; the home widget follows each refresh. HTTP
// answers are /v1 boards built around the current time, so "a minute
// ago" is real; the home widget channel is faked.
//
// The stops and the route are saved before the first test: in a widget
// test only the first test of a file can wait for a Hive write.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/models/bus_wait.dart';
import 'package:stm_app/models/route_alert.dart';
import 'package:stm_app/services/bus_wait_service.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/mvd_api_service.dart';
import 'package:stm_app/ui/stops_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/line_badge.dart';

/// One bus of a board: [eta] minutes away; it is due [due] minutes after
/// the board was fetched (default: [eta]).
typedef _Trip = ({
  String tripId,
  String line,
  String destination,
  String state,
  int eta,
  String clock,
  int? due,
});

_Trip _trip(String tripId, String line, String destination, String state,
        int eta, String clock, {int? due}) =>
    (
      tripId: tripId,
      line: line,
      destination: destination,
      state: state,
      eta: eta,
      clock: clock,
      due: due,
    );

// Stop 574: the 116 with GPS, the 144 by the timetable, and a 121 that
// was at the stop two minutes ago
final _trips574 = [
  _trip('bus-50-777', '121', 'PUNTA CARRETAS', 'arriving', 0, '19:50',
      due: -2),
  _trip('bus-50-139', '116', 'POCITOS', 'live', 9, '20:01'),
  _trip('sched-883-2004', '144', 'CEMENTERIO DEL NORTE', 'scheduled', 12,
      '20:04'),
];
final _trips3140 = [
  _trip('bus-20-5', '143', 'CIUDADELA', 'live', 3, '19:55'),
];

/// GET /v1/stops/{id}/arrivals fetched at [fetchedAt] (default: now).
String _board(int stopId, List<_Trip> trips, {DateTime? fetchedAt}) {
  final at = (fetchedAt ?? DateTime.now()).toUtc();
  return jsonEncode({
    'id': stopId,
    'fetchedAt': at.toIso8601String(),
    'arrivals': [
      for (final t in trips)
        {
          'tripId': t.tripId,
          'variantId': null,
          'line': t.line,
          'destination': t.destination,
          'state': t.state,
          'etaMinutes': t.eta,
          'expectedAt':
              at.add(Duration(minutes: t.due ?? t.eta)).toIso8601String(),
          'clockTime': t.clock,
          'accessible': false,
          'airConditioning': null,
          'zeroEmission': null,
        }
    ],
  });
}

void main() {
  late Directory hiveDir;
  final requests = <String>[];
  // What the home widget would read
  final widgetData = <String, Object?>{};
  late Future<http.Response> Function(http.Request request) answer;

  // Boards fetched now, unless a test says otherwise
  Future<http.Response> boards(http.Request request,
      {DateTime? fetchedAt}) async {
    return switch (request.url.path) {
      '/v1/stops/574/arrivals' =>
        http.Response(_board(574, _trips574, fetchedAt: fetchedAt), 200),
      '/v1/stops/3140/arrivals' =>
        http.Response(_board(3140, _trips3140, fetchedAt: fetchedAt), 200),
      _ => http.Response('{"error":"not_found"}', 404),
    };
  }

  final client = MockClient((request) {
    requests.add(request.url.path);
    return answer(request);
  });
  List<String> arrivalRequests() =>
      requests.where((p) => p.endsWith('/arrivals')).toList();

  Widget app({bool active = true}) => MaterialApp(
      theme: buildTimbreTheme(),
      home: StopsPage(active: active, onOpenStopInComoIr: (_) {}));

  Finder liveMinutes(int m) =>
      find.byWidgetPredicate((w) => w is MinutosEnVivo && w.minutes == m);
  final litBadges = find.byWidgetPredicate((w) => w is LineBadge && w.live);

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('mvd_stops_board_test');
    await CacheService.init(path: hiveDir.path);
    await CacheService.saveStop(BusStop(id: 574, name: 'SAN JOSE y ANDES'));
    await CacheService.saveStop(
        BusStop(id: 3140, name: 'AV RAMON ANADOR y TIBURCIO GOMEZ'));
    // From a saved stop: it adds no request of its own
    await CacheService.saveRoute(RouteAlert(
      id: 1,
      originStopId: 574,
      originName: 'SAN JOSE y ANDES',
      destinationName: 'Trabajo',
      preferredLines: ['116'],
    ));
    MvdApiService.proxyUrl = 'https://proxy.test';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'saveWidgetData':
          widgetData[args!['id'] as String] = args['data'];
        case 'getWidgetData':
          return widgetData[args!['id'] as String] ?? args['defaultValue'];
      }
      return true;
    });
  });

  setUp(() {
    requests.clear();
    widgetData.clear();
    answer = boards;
  });

  tearDown(MvdApiService.resetBusy);

  tearDownAll(() async {
    MvdApiService.proxyUrl = '';
    await hiveDir.delete(recursive: true);
  });

  testWidgets('on open each stop is asked once, the route reads its origin',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();

      expect(arrivalRequests(),
          unorderedEquals(['/v1/stops/574/arrivals', '/v1/stops/3140/arrivals']));
      expect(liveMinutes(9), findsOneWidget);
      expect(liveMinutes(3), findsOneWidget);

      // The route card: its origin's board, through its line
      await tester.tap(find.text('Rutas'));
      await tester.pumpAndSettle();
      expect(find.text('116'), findsOneWidget);
      expect(find.text('144'), findsNothing);
      expect(arrivalRequests(), hasLength(2));
    }, () => client);
  });

  testWidgets('pull to refresh asks for every stop at once', (tester) async {
    final pending = <Completer<http.Response>>[];
    var holding = false;
    answer = (request) {
      if (!holding || !request.url.path.endsWith('/arrivals')) {
        return boards(request);
      }
      final reply = Completer<http.Response>();
      pending.add(reply);
      return reply.future;
    };

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      holding = true;

      await tester.fling(
          find.text('SAN JOSE y ANDES'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Both requests are out before the first answer comes back
      expect(pending, hasLength(2));

      for (final reply in pending) {
        reply.complete(http.Response(_board(574, _trips574), 200));
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    }, () => client);
  });

  testWidgets('off screen nothing is polled; back on screen it refreshes',
      (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTimbreTheme(),
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, on, _) =>
              StopsPage(active: on, onOpenStopInComoIr: (_) {}),
        ),
      ));
      await tester.pump();
      expect(arrivalRequests(), hasLength(2));

      // Another tab or a page on top: no ticks
      active.value = false;
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(arrivalRequests(), hasLength(2));

      // Back: refreshed at once, then every 30 s
      active.value = true;
      await tester.pump();
      expect(arrivalRequests(), hasLength(4));
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), hasLength(6));
    }, () => client);
  });

  testWidgets('a failed refresh keeps the last buses as estimates',
      (tester) async {
    final fetchedAt = DateTime.now().toUtc();
    var failing = false;
    answer = (request) async => failing
        ? http.Response('{"error":"upstream_error"}', 502)
        : boards(request, fetchedAt: fetchedAt);

    await http.runWithClient(() async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app());
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);
      expect(find.byType(LlegandoChip), findsOneWidget);

      failing = true;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();

      // What failed and since when, in red, on both cards
      final error = 'No se pudo actualizar. Datos de las '
          '${MvdApiService.montevideoClock(fetchedAt)}. '
          'Deslizá para reintentar.';
      expect(find.text(error), findsNWidgets(2));
      final note = tester.widget<Text>(find.text(error).first);
      expect(note.style?.color, TimbreColors.rojoLed);
      // The old rows as estimates: never lit, never live minutes
      expect(find.text('~20:01'), findsOneWidget);
      expect(find.text('~20:04'), findsOneWidget);
      expect(find.text('~19:55'), findsOneWidget);
      expect(find.byType(MinutosEnVivo), findsNothing);
      expect(find.byType(LlegandoChip), findsNothing);
      expect(litBadges, findsNothing);
      // The bus due two minutes ago is gone
      expect(find.text('~19:50'), findsNothing);
      expect(find.text('PUNTA CARRETAS'), findsNothing);
      expect(find.bySemanticsLabel('Línea 116 a Pocitos, alrededor de las '
          '20:01, estimado'), findsOneWidget);
      handle.dispose();

      // Back online: live again, no error
      failing = false;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(find.text(error), findsNothing);
      expect(liveMinutes(9), findsOneWidget);
      expect(find.text('~20:01'), findsNothing);
    }, () => client);
  });

  testWidgets('buses older than 5 min are not shown after a failure',
      (tester) async {
    // 5 min after the board reached the phone, on the phone's clock
    var later = Duration.zero;
    StopsPage.clock = () => DateTime.now().add(later);
    addTearDown(() => StopsPage.clock = DateTime.now);
    var failing = false;
    answer = (request) async {
      if (failing) throw http.ClientException('offline');
      return boards(request);
    };

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);

      failing = true;
      later = const Duration(minutes: 5);
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(find.text('No se pudo actualizar. Deslizá para reintentar'),
          findsNWidgets(2));
      expect(find.textContaining('Datos de las'), findsNothing);
      expect(find.text('~20:01'), findsNothing);
      expect(find.text('116'), findsNothing);
    }, () => client);
  });

  testWidgets('a phone clock 6 min ahead of the source: after a failure the '
      'board that just arrived still shows its estimates', (tester) async {
    var later = Duration.zero;
    StopsPage.clock = () => DateTime.now().add(later);
    addTearDown(() => StopsPage.clock = DateTime.now);
    var failing = false;
    // The source stamped the boards 6 min before the phone's clock
    final fetchedAt = DateTime.now().subtract(const Duration(minutes: 6));
    answer = (request) async {
      if (failing) throw http.ClientException('offline');
      return boards(request, fetchedAt: fetchedAt);
    };

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);

      failing = true;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(
          find.text('No se pudo actualizar. Datos de las '
              '${MvdApiService.montevideoClock(fetchedAt)}. '
              'Deslizá para reintentar.'),
          findsNWidgets(2));
      // Due 9 min after the source's stamp: still an estimate
      expect(find.text('~20:01'), findsOneWidget);
      // Due 3 min after it: kept on the source's clock (gone on the phone's)
      expect(find.text('~19:55'), findsOneWidget);
      // Due 2 min before it: gone, on the source's clock
      expect(find.text('~19:50'), findsNothing);
      // 4.5 min on the phone: the bus due 3 min after the stamp is gone
      later = const Duration(minutes: 4, seconds: 30);
      await tester.pumpWidget(app(active: false));
      expect(find.textContaining('Datos de las'), findsNWidgets(2));
      expect(find.text('~19:55'), findsNothing);
      expect(find.text('~20:01'), findsOneWidget);
    }, () => client);
  });

  testWidgets('a phone clock 12 min ahead, no failure: a board 2 min on the '
      'phone keeps the bus due 9 min after the source stamped it',
      (tester) async {
    var later = Duration.zero;
    StopsPage.clock = () => DateTime.now().add(later);
    addTearDown(() => StopsPage.clock = DateTime.now);
    final fetchedAt = DateTime.now().subtract(const Duration(minutes: 12));
    answer = (request) async => boards(request, fetchedAt: fetchedAt);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);

      // Off screen for 2 min: nothing new, the rows turn to estimates
      later = const Duration(minutes: 2);
      await tester.pumpWidget(app(active: false));
      expect(liveMinutes(9), findsNothing);
      expect(find.text('~20:01'), findsOneWidget);
    }, () => client);
  });

  testWidgets('a stop that no longer exists says how to remove it',
      (tester) async {
    answer = (request) async => request.url.path == '/v1/stops/574/arrivals'
        ? http.Response('{"error":"stop_not_found"}', 404)
        : boards(request);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();

      expect(
          find.text(
              'Esta parada ya no existe. Deslizá la tarjeta para borrarla.'),
          findsOneWidget);
      expect(liveMinutes(3), findsOneWidget);
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
    }, () => client);
  });

  testWidgets('a busy proxy: ticks wait for Retry-After, nothing is said',
      (tester) async {
    var busy = false;
    answer = (request) async => busy
        ? http.Response('{"error":"rate_limited"}', 429,
            headers: {'retry-after': '1'})
        : boards(request);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();

      busy = true;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(arrivalRequests(), hasLength(4));
      // The last buses stay as they were, without an error
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
      expect(liveMinutes(9), findsOneWidget);

      // The service would ask again: the page itself waits the second out
      busy = false;
      MvdApiService.resetBusy();
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), hasLength(4));

      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await tester.pump(StopsPage.autoRefreshInterval);
      expect(arrivalRequests(), hasLength(6));
    }, () => client);
  });

  testWidgets('back on screen, an old board is not live while it refreshes',
      (tester) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    // How far the phone's clock has moved on
    var later = Duration.zero;
    StopsPage.clock = () => DateTime.now().add(later);
    addTearDown(() => StopsPage.clock = DateTime.now);
    final pending = <String, Completer<http.Response>>{};
    var holding = false;
    answer = (request) {
      if (!holding) return boards(request);
      return (pending[request.url.path] = Completer<http.Response>()).future;
    };
    Future<void> answerPending() async {
      for (final MapEntry(key: path, value: reply) in pending.entries) {
        reply.complete(await boards(http.Request('GET',
            Uri.parse('https://proxy.test$path'))));
      }
      pending.clear();
      await tester.pump();
    }

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTimbreTheme(),
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, on, _) =>
              StopsPage(active: on, onOpenStopInComoIr: (_) {}),
        ),
      ));
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);
      holding = true;

      // Two minutes under Horarios: estimates until the new board comes
      active.value = false;
      await tester.pump();
      later = const Duration(minutes: 2);
      active.value = true;
      await tester.pump();
      expect(pending, hasLength(2));
      expect(find.byType(MinutosEnVivo), findsNothing);
      expect(find.byType(LlegandoChip), findsNothing);
      expect(litBadges, findsNothing);
      expect(find.text('~20:01'), findsOneWidget);
      expect(find.text('~19:55'), findsOneWidget);
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
      await answerPending();
      expect(liveMinutes(9), findsOneWidget);

      // Six minutes: those buses are too old even as estimates
      active.value = false;
      await tester.pump();
      later += const Duration(minutes: 6);
      active.value = true;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(find.text('~20:01'), findsNothing);
      expect(find.text('116'), findsNothing);
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
      await answerPending();
      expect(liveMinutes(9), findsOneWidget);
    }, () => client);
  });

  testWidgets('a proxy busy for minutes: the old buses stop looking live',
      (tester) async {
    var later = Duration.zero;
    StopsPage.clock = () => DateTime.now().add(later);
    addTearDown(() => StopsPage.clock = DateTime.now);
    var busy = false;
    answer = (request) async => busy
        ? http.Response('{"error":"rate_limited"}', 429,
            headers: {'retry-after': '1'})
        : boards(request);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      expect(liveMinutes(9), findsOneWidget);

      busy = true;
      later = const Duration(minutes: 2);
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(arrivalRequests(), hasLength(4));
      expect(find.byType(MinutosEnVivo), findsNothing);
      expect(litBadges, findsNothing);
      expect(find.text('~20:01'), findsOneWidget);
      expect(find.textContaining('No se pudo actualizar'), findsNothing);

      // Still busy five minutes on: the cards wait, still without a word
      later = const Duration(minutes: 6);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)));
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(arrivalRequests(), hasLength(6));
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(find.text('~20:01'), findsNothing);
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
    }, () => client);
  });

  testWidgets('the home widget follows each refresh', (tester) async {
    // The source stamped the boards 6 min before the phone's clock
    final fetchedAt =
        DateTime.now().toUtc().subtract(const Duration(minutes: 6));
    var failing = false;
    answer = (request) async => failing
        ? http.Response('{"error":"upstream_timeout"}', 504)
        : boards(request, fetchedAt: fetchedAt);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();

      // The route's next bus at its origin: its own destination and time
      expect(widgetData['route_status'], 'ok');
      expect(widgetData['route_line'], '116');
      expect(widgetData['route_dest'], 'POCITOS');
      expect(widgetData['route_eta_min'], 9);
      expect(widgetData['route_eta_at'], '20:01');
      // Due 9 min after the stamp, kept on the phone's clock: 6 min later.
      // Real time: the board takes a moment to reach the widget
      final dueOnPhone = fetchedAt
          .add(const Duration(minutes: 9 + 6))
          .millisecondsSinceEpoch;
      expect(int.parse(widgetData['route_expected_at_ms']! as String),
          inInclusiveRange(dueOnPhone, dueOnPhone + 5000));

      // Offline: the row stays while its bus is still due
      failing = true;
      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      await tester.pump();
      expect(widgetData['route_status'], 'offline');
      expect(widgetData['route_line'], '116');
    }, () => client);
  });

  testWidgets('a wait started from a board stamped 6 min before the phone '
      'takes that offset, and each refresh hands over the stamp',
      (tester) async {
    final fake = _FakeWaitPlatform();
    final previous = BusWaitService.platform;
    BusWaitService.platform = fake;
    addTearDown(() {
      BusWaitService.platform = previous;
      BusWaitService.current.value = null;
    });
    final fetchedAt =
        DateTime.now().toUtc().subtract(const Duration(minutes: 6));
    answer = (request) async => boards(request, fetchedAt: fetchedAt);

    await http.runWithClient(() async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('116'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avisarme cuando llegue'));
      await tester.pumpAndSettle();
      // Real time: the board reached the phone a moment after the stamp
      expect(fake.started.single.clockOffset.inSeconds,
          inInclusiveRange(360, 365));

      await tester.pump(StopsPage.autoRefreshInterval);
      await tester.pump();
      expect(fake.fetchedAts, [fetchedAt]);
    }, () => client);
  });

  testWidgets('the waited bus is found by its trip id', (tester) async {
    final previous = BusWaitService.platform;
    BusWaitService.platform = _FakeWaitPlatform();
    addTearDown(() {
      BusWaitService.platform = previous;
      BusWaitService.current.value = null;
    });
    // Two 116 to POCITOS 4 min apart
    final fetchedAt = DateTime.now().toUtc();
    answer = (request) async => request.url.path == '/v1/stops/574/arrivals'
        ? http.Response(
            _board(
                574,
                [
                  _trip('bus-50-139', '116', 'POCITOS', 'live', 2, '19:54'),
                  _trip('bus-50-222', '116', 'POCITOS', 'live', 6, '19:58'),
                ],
                fetchedAt: fetchedAt),
            200)
        : boards(request);
    // Waiting for the later one, expected when the earlier one comes:
    // its time alone would pick the wrong bus
    BusWaitService.current.value = BusWait(
      stopId: 574,
      stopName: 'SAN JOSE y ANDES',
      line: '116',
      destination: 'POCITOS',
      tripId: 'bus-50-222',
      alertMinutes: 3,
      startedAt: DateTime.now(),
      expectedAt: fetchedAt.add(const Duration(minutes: 2)),
    );

    await http.runWithClient(() async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app());
      await tester.pump();

      expect(
          find.bySemanticsLabel('Línea 116 a Pocitos, llega en 6 minutos, '
              'con GPS, estás esperando este ómnibus'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              'Línea 116 a Pocitos, llega en 2 minutos, con GPS'),
          findsOneWidget);
      handle.dispose();
    }, () => client);
  });
}

class _FakeWaitPlatform implements BusWaitPlatform {
  final started = <BusWait>[];

  /// The board's stamp of each [onArrivals].
  final fetchedAts = <DateTime?>[];

  @override
  Future<void> init({required ValueChanged<DateTime> onEnded}) async {}

  @override
  Future<BusWait?> restore() async => null;

  @override
  Future<bool> start(BusWait wait, BusArrival trip) async {
    started.add(wait);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> onArrivals(BusWait wait, List<BusArrival>? arrivals,
      {DateTime? fetchedAt}) async {
    fetchedAts.add(fetchedAt);
    return false;
  }
}
