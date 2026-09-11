import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'bus_alerts';
  static const _channelName = 'Alertas de colectivo';
  static const _channelDesc =
      'Notificaciones cuando tu colectivo está por llegar';

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);

    // Create the notification channel (Android 8+)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    bool granted = true;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
    }
    if (ios != null) {
      granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return granted;
  }

  static Future<void> showBusAlert({
    required String line,
    required String stopName,
    required int etaMinutes,
  }) async {
    final title = 'Línea $line — $etaMinutes min';
    final body = etaMinutes <= 1
        ? 'Tu colectivo está llegando a $stopName'
        : 'Tu colectivo llega en $etaMinutes min a $stopName';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF0066CC),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    final id = _stableNotificationId('stop_${line}_$stopName');
    await _plugin.show(id, title, body, details);
    debugPrint('🔔 Notificación enviada: $title');
  }

  /// Notification for a saved A→B route: bus is arriving at origin stop.
  static Future<void> showRouteAlert({
    required String line,
    required String originName,
    required String destinationName,
    required int etaMinutes,
  }) async {
    final title = 'Línea $line → $destinationName';
    final body = etaMinutes <= 1
        ? 'Tu colectivo está llegando a $originName'
        : 'Sale en $etaMinutes min desde $originName';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF0066CC),
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    final id = _stableNotificationId('route_${line}_$destinationName');
    await _plugin.show(id, title, body, details);
    debugPrint('🗺️ Alerta ruta: $title');
  }

  static Future<void> cancelAll() => _plugin.cancelAll();

  /// Produce a stable, positive notification ID in [0, 2^31-1].
  static int _stableNotificationId(String key) {
    // Simple djb2-style hash that always produces a positive 31-bit int.
    var hash = 5381;
    for (var i = 0; i < key.length; i++) {
      hash = ((hash << 5) + hash + key.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }
}
