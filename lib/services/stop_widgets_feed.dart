import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/arrivals_board.dart';
import '../models/bus_stop.dart';
import 'api/api_result.dart';
import 'background_worker.dart';
import 'mvd_api_service.dart';

/// The stop widgets of Android: Próximo (2 × 2), Parada (4 × 2) and Mis
/// paradas (4 × 4). `TimbreStopWidget.kt` and `StopWidgetData.kt` read these
/// keys (docs/design/10-superficies.md).
///
/// The app writes the saved stops and every board it fetches; the widgets
/// choose which stops to show and write their ids back ([keyShownStops]),
/// so the background check and the refresh button fetch only those.
/// Arrivals keep their due time on the phone's clock: the widget drops a
/// bus a minute after it, with no network.
abstract final class StopWidgetsFeed {
  /// The providers, in `com.liberontech.stmapp`.
  static const providers = [
    'TimbreProximoWidget',
    'TimbreParadaWidget',
    'TimbreMisParadasWidget',
  ];

  /// Saved stops in the order of Mis paradas (String: a JSON list of
  /// `{"id", "name"}`).
  static const keySavedStops = 'stops_saved';

  /// Stops the placed widgets show (String: ids joined by commas), written
  /// by the widgets.
  static const keyShownStops = 'stops_shown';

  /// How many stop widgets are on the home screen (String, decimal),
  /// written by the widgets.
  static const keyPlacedWidgets = 'stop_widgets_placed';

  /// The board of stop [id] (String: JSON, see [_boardJson]).
  static String keyBoard(int id) => 'stop_board_$id';

  /// Buses kept per stop: Mis paradas shows up to 6.
  static const maxArrivals = 6;

  /// Writes [stops] for the widgets and, with [redraw], redraws them.
  static Future<void> saveStops(
    List<BusStop> stops, {
    bool redraw = true,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        keySavedStops,
        jsonEncode([
          for (final stop in stops) {'id': stop.id, 'name': stop.name},
        ]),
      );
    } catch (e) {
      debugPrint('⚠️ Stop widgets data error: $e');
    }
    if (redraw) await _redraw();
  }

  /// Writes the boards in [results] and redraws the widgets. [now] is when
  /// they were fetched, on the phone's clock: minus a board's fetchedAt, it
  /// is how far the phone's clock is from the source's. A failed stop keeps
  /// its buses and is marked failed; a busy answer (429) changes nothing.
  static Future<void> updateBoards(
    Map<int, ApiResult<ArrivalsBoard>> results, {
    required DateTime now,
  }) async {
    if (results.isEmpty) return;
    try {
      for (final MapEntry(key: id, value: result) in results.entries) {
        switch (result) {
          case ApiOk(:final value):
            await HomeWidget.saveWidgetData<String>(
              keyBoard(id),
              jsonEncode(_boardJson(value, now)),
            );
          case ApiError(failure: ApiFailure.busy):
            break;
          case ApiError():
            final kept = await HomeWidget.getWidgetData<String>(keyBoard(id));
            final board = kept == null
                ? <String, Object?>{'arrivals': const []}
                : jsonDecode(kept) as Map<String, Object?>;
            board['failedAtMs'] = now.millisecondsSinceEpoch;
            await HomeWidget.saveWidgetData<String>(
              keyBoard(id),
              jsonEncode(board),
            );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Stop widgets data error: $e');
    }
    await _redraw();
  }

  /// The stops the placed widgets show; empty without widgets or on iOS.
  static Future<Set<int>> shownStopIds() async {
    try {
      final shown = await HomeWidget.getWidgetData<String>(keyShownStops);
      return {
        for (final part in (shown ?? '').split(','))
          ?int.tryParse(part.trim()),
      };
    } catch (e) {
      debugPrint('⚠️ Stop widgets data error: $e');
      return const {};
    }
  }

  /// True while a stop widget is on the home screen: the background check
  /// keeps running for it.
  static Future<bool> hasPlacedWidgets() async {
    try {
      final placed = await HomeWidget.getWidgetData<String>(keyPlacedWidgets);
      return (int.tryParse(placed ?? '') ?? 0) > 0;
    } catch (e) {
      debugPrint('⚠️ Stop widgets data error: $e');
      return false;
    }
  }

  /// Fetches the stops the widgets show and writes them: the refresh
  /// button, and a widget showing a stop it has no board for.
  static Future<void> refreshShown() async {
    final ids = await shownStopIds();
    if (ids.isEmpty) return;
    final results = await MvdApiService.getBoards(ids);
    await updateBoards(results, now: DateTime.now());
  }

  static Map<String, Object?> _boardJson(ArrivalsBoard board, DateTime now) {
    final offset = now.difference(board.fetchedAt);
    return {
      'checkedAtMs': now.millisecondsSinceEpoch,
      'arrivals': [
        for (final bus in board.arrivals.take(maxArrivals))
          {
            'line': bus.line,
            'dest':
                bus.destination.isEmpty ? 'Línea ${bus.line}' : bus.destination,
            'clock': bus.clockTime,
            // expectedAt is on the source's clock; the widget compares
            // with the phone's
            'dueMs': bus.expectedAt.add(offset).millisecondsSinceEpoch,
            'acc': bus.accessible,
          },
      ],
    };
  }

  static Future<void> _redraw() async {
    for (final provider in providers) {
      try {
        await HomeWidget.updateWidget(androidName: provider);
      } catch (e) {
        debugPrint('⚠️ Widget update error: $e');
      }
    }
  }
}

/// Registers [stopWidgetsCallback] for the widgets' buttons. Android only:
/// iOS has no widgets.
Future<void> initStopWidgets() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await HomeWidget.registerInteractivityCallback(stopWidgetsCallback);
  } catch (e) {
    debugPrint('⚠️ Widget callback error: $e');
  }
}

/// Runs in a background isolate when a widget asks for data
/// (`timbre://refresh`): fetches its stops and keeps the background check
/// running while widgets are placed.
@pragma('vm:entry-point')
Future<void> stopWidgetsCallback(Uri? uri) async {
  if (uri?.host != 'refresh') return;
  await StopWidgetsFeed.refreshShown();
  if (await StopWidgetsFeed.hasPlacedWidgets()) {
    try {
      await BackgroundWorker.registerPeriodicTask();
    } catch (e) {
      debugPrint('⚠️ WorkManager register error: $e');
    }
  }
}
