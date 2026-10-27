import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/arrivals_board.dart';
import '../models/route_alert.dart';
import 'api/api_result.dart';

/// The route row of the Android home widget: the next bus of the first
/// enabled route at its origin stop. `MVDTransporteWidgetProvider.kt` reads
/// these keys (docs/design/10-superficies.md).
///
/// Written by the background check (at least 15 min apart) and by the app
/// after each refresh, so the row keeps the expected arrival time rather
/// than a countdown; the widget hides it 2 min after that time.
abstract final class WidgetFeed {
  static const _widgetName = 'MVDTransporteWidgetProvider';

  /// Line of the bus (String); null shows the empty state.
  static const keyLine = 'route_line';

  /// Where the bus goes (String): its destination, or the route's name
  /// when the source gives none.
  static const keyDestination = 'route_dest';

  /// Minutes to the stop when checked (int).
  static const keyEtaMinutes = 'route_eta_min';

  /// The bus's clock time at the stop (String, "19:56").
  static const keyClockTime = 'route_eta_at';

  /// When the bus is expected (String: ms since epoch, in decimal).
  static const keyExpectedAtMs = 'route_expected_at_ms';

  /// When the board was last fetched (String: ms since epoch, in decimal).
  static const keyCheckedAtMs = 'route_checked_at_ms';

  /// One of [statusOk], [statusNone], [statusOffline] or [statusOff].
  static const keyStatus = 'route_status';

  /// A bus of the route is shown.
  static const statusOk = 'ok';

  /// The route has no bus coming.
  static const statusNone = 'none';

  /// The board could not be fetched; the last row stays while its bus is
  /// still due.
  static const statusOffline = 'offline';

  /// No enabled route, or no background check any more.
  static const statusOff = 'off';

  /// The row for the first of [enabledRoutes], from its origin's board in
  /// [boards] (a board missing there counts as failed). [now] is when the
  /// boards were fetched.
  static Future<void> update({
    required List<RouteAlert> enabledRoutes,
    required Map<int, ApiResult<ArrivalsBoard>> boards,
    required DateTime now,
  }) async {
    final route = enabledRoutes.firstOrNull;
    if (route == null) return clear(statusOff);

    try {
      final board = boards[route.originStopId]?.valueOrNull;
      if (board == null) {
        final expectedMs = int.tryParse(
            await HomeWidget.getWidgetData<String>(keyExpectedAtMs) ?? '');
        if (expectedMs == null || expectedMs <= now.millisecondsSinceEpoch) {
          await HomeWidget.saveWidgetData<String>(keyLine, null);
        }
        await HomeWidget.saveWidgetData<String>(keyStatus, statusOffline);
      } else {
        final bus = board.arrivals.where(route.accepts).firstOrNull;
        if (bus == null) {
          await HomeWidget.saveWidgetData<String>(keyLine, null);
        } else {
          await HomeWidget.saveWidgetData<String>(keyLine, bus.line);
          await HomeWidget.saveWidgetData<String>(
              keyDestination,
              bus.destination.isEmpty
                  ? route.destinationName
                  : bus.destination);
          await HomeWidget.saveWidgetData<int>(keyEtaMinutes, bus.etaMinutes);
          await HomeWidget.saveWidgetData<String>(keyClockTime, bus.clockTime);
          await HomeWidget.saveWidgetData<String>(
              keyExpectedAtMs, '${bus.expectedAt.millisecondsSinceEpoch}');
        }
        await HomeWidget.saveWidgetData<String>(
            keyCheckedAtMs, '${now.millisecondsSinceEpoch}');
        await HomeWidget.saveWidgetData<String>(
            keyStatus, bus == null ? statusNone : statusOk);
      }
    } catch (e) {
      // e.g. iOS without the App Group
      debugPrint('⚠️ Widget data error: $e');
    }
    await _redraw();
  }

  /// Empty state with [status], e.g. [statusOff] when the background check
  /// is cancelled.
  static Future<void> clear(String status) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyLine, null);
      await HomeWidget.saveWidgetData<String>(keyStatus, status);
    } catch (e) {
      debugPrint('⚠️ Widget data error: $e');
    }
    await _redraw();
  }

  static Future<void> _redraw() async {
    try {
      await HomeWidget.updateWidget(name: _widgetName);
    } catch (e) {
      debugPrint('⚠️ Widget update error: $e');
    }
  }
}
