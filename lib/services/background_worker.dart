import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'cache_service.dart';
import 'mvd_api_service.dart';
import 'notification_service.dart';
import 'stop_widgets_feed.dart';

const _taskName = 'busEtaCheck';
const _taskUniqueName = 'bus-eta-check';

/// Must be a top-level function — called by WorkManager in a separate isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;

    try {
      await CacheService.init();
      await NotificationService.init();

      await BackgroundWorker.checkAlerts(DateTime.now());
    } catch (e) {
      debugPrint('❌ Background task error: $e');
    }

    return true;
  });
}

class BackgroundWorker {
  static Future<void> init() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (e) {
      // Must never block app start (e.g. iOS without BGTask setup)
      debugPrint('⚠️ WorkManager init error: $e');
    }
  }

  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 2),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    debugPrint('✅ WorkManager tarea registrada');
  }

  /// One background pass: notifies about GPS-tracked buses within each
  /// alert's threshold, only inside the alert's schedule, and refreshes the
  /// home widgets. Every stop involved is requested once, all in parallel.
  static Future<void> checkAlerts(DateTime now) async {
    final stops = CacheService.getStopsWithNotificationsEnabled()
        .where((s) => s.schedule.allows(now))
        .toList();
    final routes = CacheService.getEnabledRoutes();
    final scheduledRoutes =
        routes.where((r) => r.schedule.allows(now)).toList();
    // The stop widgets, at any hour
    final widgetStops = await StopWidgetsFeed.shownStopIds();

    final boards = await MvdApiService.getBoards({
      for (final stop in stops) stop.id,
      for (final route in scheduledRoutes) route.originStopId,
      ...widgetStops,
    });

    // Check individual stop alerts
    for (final stop in stops) {
      // Not checked is not "no buses": nothing to say
      final arrivals = boards[stop.id]?.valueOrNull?.arrivals;
      if (arrivals == null) continue;
      // Only GPS-tracked buses: a timetable estimate is not "arriving"
      final imminent = arrivals.where(
          (a) => a.isRealTime && a.etaMinutes <= stop.etaAlertMinutes);
      for (final bus in imminent) {
        await NotificationService.showBusAlert(
          line: bus.line,
          stopName: stop.name,
          etaMinutes: bus.etaMinutes,
        );
      }
    }

    // Catches its own errors: a widget failure (e.g. iOS without App
    // Group) must not swallow the notifications below
    if (widgetStops.isNotEmpty) {
      // Names change only in the app, but a stop deleted there must not
      // stay on a widget
      await StopWidgetsFeed.saveStops(CacheService.getAllStops(),
          redraw: false);
      await StopWidgetsFeed.updateBoards(
          {for (final id in widgetStops) id: boards[id]!}, now: now);
    }

    // Check route alerts (A → B)
    for (final route in scheduledRoutes) {
      final arrivals = boards[route.originStopId]?.valueOrNull?.arrivals;
      if (arrivals == null) continue;
      // Preferred lines and direction, GPS-tracked, within the threshold
      final imminent = arrivals.where((a) =>
          route.accepts(a) &&
          a.isRealTime &&
          a.etaMinutes <= route.alertMinutes);

      for (final bus in imminent) {
        await NotificationService.showRouteAlert(
          line: bus.line,
          originName: route.originName,
          destinationName: route.destinationName,
          etaMinutes: bus.etaMinutes,
        );
      }
    }
  }

  /// True if any stop or route alert is enabled.
  static bool get hasActiveAlerts =>
      CacheService.getStopsWithNotificationsEnabled().isNotEmpty ||
      CacheService.getEnabledRoutes().isNotEmpty;

  // Counts sync() calls: an older one that is still asking the widgets
  // leaves the decision to the newer
  static int _syncs = 0;

  /// Registers the periodic task when any alert is enabled or a stop
  /// widget is placed, cancels it otherwise. Call after every change to
  /// stops/routes alert state.
  static Future<void> sync() async {
    final generation = ++_syncs;
    try {
      if (hasActiveAlerts) {
        await registerPeriodicTask();
      } else {
        // Asking the widgets is a platform call: not awaited, callers wait
        // for the task only (the app unlocks after this)
        unawaited(_keepForStopWidgets(generation));
      }
    } catch (e) {
      debugPrint('⚠️ WorkManager sync error: $e');
    }
  }

  /// Without alerts: keeps the task while a stop widget is placed.
  static Future<void> _keepForStopWidgets(int generation) async {
    final placed = await StopWidgetsFeed.hasPlacedWidgets();
    if (generation != _syncs) return;
    try {
      if (placed) {
        await registerPeriodicTask();
      } else {
        await Workmanager().cancelByUniqueName(_taskUniqueName);
      }
    } catch (e) {
      debugPrint('⚠️ WorkManager sync error: $e');
    }
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
