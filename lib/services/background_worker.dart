import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'cache_service.dart';
import 'mvd_api_service.dart';
import 'notification_service.dart';

const _taskName = 'busEtaCheck';
const _taskUniqueName = 'bus-eta-check';
const _widgetName = 'MVDTransporteWidgetProvider';

/// Must be a top-level function — called by WorkManager in a separate isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;

    try {
      await CacheService.init();
      await NotificationService.init();

      // Check individual stop alerts
      final stops = CacheService.getStopsWithNotificationsEnabled();
      for (final stop in stops) {
        final arrivals =
            await MvdApiService.getNextArrivals(stop.id) ?? const [];
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

      // Check route alerts (A → B)
      final routes = CacheService.getEnabledRoutes();
      bool widgetRouteUpdated = false;
      for (final route in routes) {
        final arrivals =
            await MvdApiService.getNextArrivals(route.originStopId) ??
                const [];

        // Filter by preferred lines if specified
        final relevant =
            arrivals.where((a) => route.acceptsLine(a.line)).toList();

        // Push soonest bus for the first enabled route to the home widget.
        // Own try: a widget failure (e.g. iOS without App Group) must not
        // swallow the notifications below.
        if (!widgetRouteUpdated) {
          widgetRouteUpdated = true;
          try {
            await _updateWidgetRoute(
              relevant.isEmpty ? null : relevant.first.line,
              relevant.isEmpty ? null : relevant.first.etaMinutes,
              route.destinationName,
            );
          } catch (e) {
            debugPrint('⚠️ Widget update error: $e');
          }
        }

        final imminent = relevant
            .where((a) => a.isRealTime && a.etaMinutes <= route.alertMinutes);

        for (final bus in imminent) {
          await NotificationService.showRouteAlert(
            line: bus.line,
            originName: route.originName,
            destinationName: route.destinationName,
            etaMinutes: bus.etaMinutes,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Background task error: $e');
    }

    return true;
  });
}

/// The widget refreshes only when this task runs (≥15 min apart), so store
/// the expected arrival clock time — a bare "5 min" would go stale.
Future<void> _updateWidgetRoute(
    String? line, int? etaMinutes, String destination) async {
  if (line == null || etaMinutes == null) {
    await HomeWidget.saveWidgetData<String>('route_line', null);
  } else {
    final at = DateTime.now().add(Duration(minutes: etaMinutes));
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    await HomeWidget.saveWidgetData<String>('route_line', line);
    await HomeWidget.saveWidgetData<int>('route_eta_min', etaMinutes);
    await HomeWidget.saveWidgetData<String>('route_eta_at', '$hh:$mm');
    await HomeWidget.saveWidgetData<String>('route_dest', destination);
  }
  await HomeWidget.updateWidget(name: _widgetName);
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

  /// True if any stop or route alert is enabled.
  static bool get hasActiveAlerts =>
      CacheService.getStopsWithNotificationsEnabled().isNotEmpty ||
      CacheService.getEnabledRoutes().isNotEmpty;

  /// Registers the periodic task when any alert is enabled, cancels it
  /// otherwise. Call after every change to stops/routes alert state.
  static Future<void> sync() async {
    try {
      if (hasActiveAlerts) {
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
