import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/bus_wait.dart';
import 'mvd_api_service.dart';
import 'notification_service.dart';

/// Key of the running [BusWait] in the plugin's storage, readable from the
/// service isolate and the UI isolate.
const busWaitDataKey = 'bus_wait';

/// Must be a top-level function — runs in the foreground service isolate.
@pragma('vm:entry-point')
void busWaitTaskStart() {
  FlutterForegroundTask.setTaskHandler(BusWaitTaskHandler());
}

/// Polls the stop and updates the ongoing notification until the bus is
/// close (then notifies), the trip has passed, or the user stops it.
class BusWaitTaskHandler extends TaskHandler {
  static const pollInterval = Duration(seconds: 30);
  static const stopButtonId = 'stop';
  /// Sent to the UI isolate as `{endedKey: startedAt in ms}`.
  static const endedKey = 'busWaitEnded';

  BusWait? _wait;
  // Identifies this wait in the "ended" message: when a wait replaces
  // another, the old service's message must not end the new one
  int? _startedAtMs;
  bool _checking = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final json = await FlutterForegroundTask.getData<String>(key: busWaitDataKey);
    if (json == null) {
      await FlutterForegroundTask.stopService();
      return;
    }
    _wait = BusWait.fromJson(jsonDecode(json));
    _startedAtMs = _wait!.startedAt.millisecondsSinceEpoch;
    await NotificationService.init();
    await _check();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _check();

  Future<void> _check() async {
    final wait = _wait;
    if (wait == null || _checking) return;
    _checking = true;
    try {
      final arrivals = await MvdApiService.getNextArrivals(wait.stopId);
      final result = wait.check(arrivals, DateTime.now());
      switch (result.outcome) {
        case WaitOutcome.alert:
          await NotificationService.showBusAlert(
            line: wait.line,
            stopName: wait.stopName,
            etaMinutes: result.trip!.etaMinutes,
          );
          await _finish();
        case WaitOutcome.over:
          await _finish();
        case WaitOutcome.waiting:
          // expectedAt moved: keep it for an app restart
          await FlutterForegroundTask.saveData(
              key: busWaitDataKey, value: jsonEncode(wait.toJson()));
          await FlutterForegroundTask.updateService(
            notificationTitle: wait.title,
            notificationText: wait.statusText(result),
          );
      }
    } catch (e) {
      debugPrint('❌ BusWait check error: $e');
    } finally {
      _checking = false;
    }
  }

  Future<void> _finish() async {
    _wait = null;
    await FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == stopButtonId) _finish();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // The stored wait is left as is: it means nothing once the service is
    // not running, and a replacing wait may already have overwritten it
    if (_startedAtMs != null) {
      FlutterForegroundTask.sendDataToMain({endedKey: _startedAtMs});
    }
  }
}
