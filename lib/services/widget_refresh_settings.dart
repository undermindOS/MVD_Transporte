import 'package:home_widget/home_widget.dart';

import 'stop_widgets_feed.dart';

/// One persistent setting shared with StopWidgetWork.kt. No Hive or app unlock
/// is required by either the periodic task or the refresh button.
abstract final class WidgetRefreshSettings {
  static const keyMinutes = 'widget_refresh_minutes';
  static const options = [15, 30, 60, 0];
  static const defaultMinutes = 15;

  static Future<int> load() async {
    try {
      final minutes = await HomeWidget.getWidgetData<int>(keyMinutes);
      return options.contains(minutes) ? minutes! : defaultMinutes;
    } catch (_) {
      return defaultMinutes;
    }
  }

  static Future<void> save(int minutes) async {
    if (!options.contains(minutes)) throw ArgumentError.value(minutes);
    final saved = await HomeWidget.saveWidgetData<int>(keyMinutes, minutes);
    if (saved != true) throw StateError('No se pudo guardar la frecuencia');
    // The native providers apply the new schedule, including Manual, even
    // when the existing interval was shorter. The snapshot is left intact.
    await StopWidgetsFeed.redraw();
  }

  static String label(int minutes) => switch (minutes) {
    0 => 'Manual',
    60 => '1 h',
    _ => '$minutes min',
  };
}
