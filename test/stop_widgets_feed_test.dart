// What the app writes for the Android stop widgets (StopWidgetsFeed) and
// what it reads back from them. The Kotlin side of the same keys is pinned
// by android/app/src/test/.../StopWidgetDataTest.kt. The home_widget plugin
// is faked.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/models/arrivals_board.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/bus_stop.dart';
import 'package:stm_app/services/api/api_result.dart';
import 'package:stm_app/services/stop_widgets_feed.dart';

// When the source answered (19:52 in Montevideo)
final _fetchedAt = DateTime.utc(2026, 10, 19, 22, 52);

BusArrival _bus(
  String line,
  int minutes, {
  String destination = 'POCITOS',
  bool accessible = false,
}) =>
    BusArrival(
      tripId: 'bus-50-$line',
      line: line,
      destination: destination,
      state: ArrivalState.live,
      etaMinutes: minutes,
      expectedAt: _fetchedAt.add(Duration(minutes: minutes)),
      clockTime: '19:${52 + minutes}',
      accessible: accessible,
    );

ArrivalsBoard _board(List<BusArrival> arrivals) =>
    ArrivalsBoard(stopId: 574, fetchedAt: _fetchedAt, arrivals: arrivals);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('home_widget');
  final widget = <String, Object?>{};
  final redrawn = <String>[];

  Map<String, Object?> board(int id) =>
      jsonDecode(widget[StopWidgetsFeed.keyBoard(id)] as String)
          as Map<String, Object?>;

  setUp(() {
    widget.clear();
    redrawn.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'saveWidgetData':
          widget[args!['id'] as String] = args['data'];
        case 'getWidgetData':
          return widget[args!['id'] as String];
        case 'updateWidget':
          redrawn.add(args!['android'] as String);
      }
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('saved stops go to the widgets in the order of Mis paradas', () async {
    await StopWidgetsFeed.saveStops([
      BusStop(id: 3140, name: 'AV RAMON ANADOR y TIBURCIO GOMEZ'),
      BusStop(id: 574, name: 'SAN JOSE y ANDES'),
    ]);
    expect(jsonDecode(widget[StopWidgetsFeed.keySavedStops] as String), [
      {'id': 3140, 'name': 'AV RAMON ANADOR y TIBURCIO GOMEZ'},
      {'id': 574, 'name': 'SAN JOSE y ANDES'},
    ]);
    expect(redrawn, [
      'TimbreProximoWidget',
      'TimbreParadaWidget',
      'TimbreMisParadasWidget',
    ]);

    redrawn.clear();
    await StopWidgetsFeed.saveStops(const [], redraw: false);
    expect(widget[StopWidgetsFeed.keySavedStops], '[]');
    expect(redrawn, isEmpty);
  });

  test('a bus is due on the phone\'s clock', () async {
    // The phone runs 2 min ahead of the source
    final now = _fetchedAt.add(const Duration(minutes: 2));
    await StopWidgetsFeed.updateBoards({
      574: ApiOk(_board([_bus('121', 1, accessible: true)])),
    }, now: now);

    expect(board(574), {
      'checkedAtMs': now.millisecondsSinceEpoch,
      'arrivals': [
        {
          'line': '121',
          'dest': 'POCITOS',
          'clock': '19:53',
          'dueMs':
              _fetchedAt.add(const Duration(minutes: 3)).millisecondsSinceEpoch,
          'acc': true,
        },
      ],
    });
    expect(redrawn, StopWidgetsFeed.providers);
  });

  test('six buses at most; no destination reads as the line', () async {
    await StopWidgetsFeed.updateBoards({
      574: ApiOk(
        _board([
          _bus('116', 1, destination: ''),
          for (var i = 2; i <= 8; i++) _bus('12$i', i),
        ]),
      ),
    }, now: _fetchedAt);

    final arrivals = board(574)['arrivals'] as List;
    expect(arrivals, hasLength(StopWidgetsFeed.maxArrivals));
    expect((arrivals.first as Map)['dest'], 'Línea 116');
  });

  test('a failed stop keeps its buses and says when it failed', () async {
    await StopWidgetsFeed.updateBoards({
      574: ApiOk(_board([_bus('121', 5)])),
    }, now: _fetchedAt);
    final later = _fetchedAt.add(const Duration(minutes: 1));
    await StopWidgetsFeed.updateBoards({
      574: const ApiError(ApiFailure.offline),
    }, now: later);

    expect(board(574)['checkedAtMs'], _fetchedAt.millisecondsSinceEpoch);
    expect(board(574)['failedAtMs'], later.millisecondsSinceEpoch);
    expect(board(574)['arrivals'], hasLength(1));

    // Never fetched: an empty board, failed
    await StopWidgetsFeed.updateBoards({
      3140: const ApiError(ApiFailure.timeout),
    }, now: later);
    expect(board(3140), {
      'arrivals': <Object?>[],
      'failedAtMs': later.millisecondsSinceEpoch,
    });
  });

  test('a busy answer (429) changes nothing', () async {
    await StopWidgetsFeed.updateBoards({
      574: const ApiError(ApiFailure.busy, retryAfter: Duration(seconds: 30)),
    }, now: _fetchedAt);
    expect(widget, isEmpty);
  });

  test(
    'reads which stops the widgets show, and whether any is placed',
    () async {
      expect(await StopWidgetsFeed.shownStopIds(), isEmpty);
      expect(await StopWidgetsFeed.hasPlacedWidgets(), isFalse);

      widget
        ..[StopWidgetsFeed.keyShownStops] = '574,3140,'
        ..[StopWidgetsFeed.keyPlacedWidgets] = '2';
      expect(await StopWidgetsFeed.shownStopIds(), {574, 3140});
      expect(await StopWidgetsFeed.hasPlacedWidgets(), isTrue);

      widget[StopWidgetsFeed.keyPlacedWidgets] = '0';
      expect(await StopWidgetsFeed.hasPlacedWidgets(), isFalse);
    },
  );

  test('without the plugin (iOS, tests) nothing throws', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await StopWidgetsFeed.saveStops([BusStop(id: 574, name: 'SAN JOSE')]);
    await StopWidgetsFeed.updateBoards({
      574: ApiOk(_board([_bus('121', 5)])),
    }, now: _fetchedAt);
    expect(await StopWidgetsFeed.shownStopIds(), isEmpty);
    expect(await StopWidgetsFeed.hasPlacedWidgets(), isFalse);
  });
}
