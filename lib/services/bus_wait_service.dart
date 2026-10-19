import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bus_arrival.dart';
import '../models/bus_wait.dart';
import 'bus_wait_task.dart';
import 'notification_service.dart';

enum WaitStart { started, alreadyClose, failed }

/// "Estoy esperando": notify when the bus the user waits for is close.
///
/// Android: a foreground service (type dataSync) polls every 30 s with the
/// screen off and keeps an ongoing notification. iOS cannot poll in the
/// background without a push server, so the app schedules a reminder for
/// the predicted time and moves it whenever it refreshes in the foreground.
class BusWaitService {
  /// The running wait, or null. The UI listens to it.
  static final current = ValueNotifier<BusWait?>(null);

  @visibleForTesting
  static BusWaitPlatform platform =
      defaultTargetPlatform == TargetPlatform.android
          ? AndroidBusWait()
          : ScheduledBusWait();

  static Future<void> init() async {
    try {
      await platform.init(onEnded: (startedAt) {
        if (current.value?.startedAt == startedAt) current.value = null;
      });
      current.value = await platform.restore();
    } catch (e) {
      debugPrint('⚠️ BusWait init error: $e');
    }
  }

  /// Starts waiting for [trip] at the stop; replaces a running wait.
  static Future<WaitStart> start(BusWait wait, BusArrival trip) async {
    // Already within the threshold: the user is looking at it right now
    if (wait.check([trip], DateTime.now()).outcome == WaitOutcome.alert) {
      return WaitStart.alreadyClose;
    }
    if (current.value != null) await stop();
    if (!await platform.start(wait, trip)) return WaitStart.failed;
    current.value = wait;
    return WaitStart.started;
  }

  static Future<void> stop() async {
    current.value = null;
    await platform.stop();
  }

  /// Fresh arrivals of [stopId] while the app is open.
  static Future<void> onArrivals(
      int stopId, List<BusArrival>? arrivals) async {
    final wait = current.value;
    if (wait == null || wait.stopId != stopId) return;
    final ended = await platform.onArrivals(wait, arrivals);
    if (ended) current.value = null;
  }

  /// Back from the background: the wait may have ended meanwhile.
  static Future<void> sync() async {
    if (current.value == null) return;
    current.value = await platform.restore();
  }
}

abstract class BusWaitPlatform {
  /// [onEnded]: the wait started at that time finished outside the app's
  /// control.
  Future<void> init({required ValueChanged<DateTime> onEnded});

  /// The wait still running, if any (e.g. after an app restart).
  Future<BusWait?> restore();

  Future<bool> start(BusWait wait, BusArrival trip);

  Future<void> stop();

  /// Returns true when the wait is over.
  Future<bool> onArrivals(BusWait wait, List<BusArrival>? arrivals);
}

/// Foreground service: polls by itself, the app only starts and stops it.
class AndroidBusWait implements BusWaitPlatform {
  static const _serviceId = 700;

  @override
  Future<void> init({required ValueChanged<DateTime> onEnded}) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bus_wait',
        channelName: 'Esperando un ómnibus',
        channelDescription:
            'Aviso fijo mientras la app sigue a tu ómnibus («Estoy esperando»)',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
            BusWaitTaskHandler.pollInterval.inMilliseconds),
        // Without a wake lock the 30 s timer stops while the CPU sleeps
        allowWakeLock: true,
        // A killed wait stays dead: no restart alarms, no boot start
        allowAutoRestart: false,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback((data) {
      final ms = data is Map ? data[BusWaitTaskHandler.endedKey] : null;
      if (ms is int) onEnded(DateTime.fromMillisecondsSinceEpoch(ms));
    });
  }

  @override
  Future<BusWait?> restore() async {
    if (!await FlutterForegroundTask.isRunningService) return null;
    final json =
        await FlutterForegroundTask.getData<String>(key: busWaitDataKey);
    return json == null ? null : BusWait.fromJson(jsonDecode(json));
  }

  @override
  Future<bool> start(BusWait wait, BusArrival trip) async {
    // Android 13+: without it the ongoing notification is hidden
    await NotificationService.requestPermissions();
    await FlutterForegroundTask.saveData(
        key: busWaitDataKey, value: jsonEncode(wait.toJson()));
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: wait.title,
      notificationText:
          wait.statusText(WaitCheck(WaitOutcome.waiting, trip: trip)),
      notificationButtons: const [
        NotificationButton(
            id: BusWaitTaskHandler.stopButtonId, text: 'Dejar de esperar'),
      ],
      callback: busWaitTaskStart,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('⚠️ BusWait service error: ${result.error}');
      return false;
    }
    return true;
  }

  @override
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> onArrivals(BusWait wait, List<BusArrival>? arrivals) async =>
      false; // the service checks on its own
}

/// iOS: a reminder at the predicted time, moved on every foreground refresh.
class ScheduledBusWait implements BusWaitPlatform {
  static const _prefsKey = 'bus_wait';

  @override
  Future<void> init({required ValueChanged<DateTime> onEnded}) async {}

  @override
  Future<BusWait?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json == null) return null;
    final wait = BusWait.fromJson(jsonDecode(json));
    final now = DateTime.now();
    final over = now.difference(wait.startedAt) >= BusWait.maxDuration ||
        now.isAfter(wait.expectedAt.add(BusWait.passedGrace));
    if (over) {
      await prefs.remove(_prefsKey);
      return null;
    }
    return wait;
  }

  @override
  Future<bool> start(BusWait wait, BusArrival trip) async {
    if (!await NotificationService.requestPermissions()) return false;
    await _schedule(wait);
    return true;
  }

  @override
  Future<void> stop() async {
    await NotificationService.cancelWaitReminder();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  @override
  Future<bool> onArrivals(BusWait wait, List<BusArrival>? arrivals) async {
    final result = wait.check(arrivals, DateTime.now());
    switch (result.outcome) {
      case WaitOutcome.alert:
        await stop();
        await _alert(wait, result.trip!);
        return true;
      case WaitOutcome.over:
        await stop();
        return true;
      case WaitOutcome.waiting:
        if (!result.failed) await _schedule(wait);
        return false;
    }
  }

  Future<void> _schedule(BusWait wait) async {
    final at =
        wait.expectedAt.subtract(Duration(minutes: wait.alertMinutes));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(wait.toJson()));
    await NotificationService.scheduleWaitReminder(
      at: at.isAfter(DateTime.now())
          ? at
          : DateTime.now().add(const Duration(seconds: 5)),
      line: wait.line,
      stopName: wait.stopName,
      alertMinutes: wait.alertMinutes,
    );
  }

  Future<void> _alert(BusWait wait, BusArrival trip) =>
      NotificationService.showBusAlert(
        line: wait.line,
        stopName: wait.stopName,
        etaMinutes: trip.etaMinutes,
      );
}
