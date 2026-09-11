import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'cache_service.dart';
import 'mvd_api_service.dart';
import 'notification_service.dart';

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

      // Check individual stop alerts
      final stops = CacheService.getStopsWithNotificationsEnabled();
      for (final stop in stops) {
        final arrivals = await MvdApiService.getNextArrivals(stop.id);
        final imminent =
            arrivals.where((a) => a.etaMinutes <= stop.etaAlertMinutes);
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
            await MvdApiService.getNextArrivals(route.originStopId);

        // Filter by preferred lines if specified
        final relevant = route.preferredLines.isEmpty
            ? arrivals
            : arrivals
                .where((a) => route.preferredLines.contains(a.line))
                .toList();

        // Push soonest bus for the first enabled route to the home widget
        if (!widgetRouteUpdated && relevant.isNotEmpty) {
          final soonest = relevant.first;
          await HomeWidget.saveWidgetData<String>('route_line', soonest.line);
          await HomeWidget.saveWidgetData<int>(
              'route_eta_min', soonest.etaMinutes);
          await HomeWidget.saveWidgetData<String>(
              'route_dest', route.destinationName);
          await HomeWidget.updateWidget(name: 'MVDTransporteWidgetProvider');
          widgetRouteUpdated = true;
        }

        final imminent =
            relevant.where((a) => a.etaMinutes <= route.alertMinutes);

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

class BackgroundWorker {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
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

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
