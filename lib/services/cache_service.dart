import 'package:hive_flutter/hive_flutter.dart';
import '../models/bus_stop.dart';
import '../models/route_alert.dart';

class CacheService {
  static const String _settingsBox = 'settings';
  static const String _stopsBox = 'stops';
  static const String _routesBox = 'routes';

  static const String keyBiometricEnabled = 'biometric_lock_enabled';
  // Transport news: cached messages (JSON string), paging start, last
  // fetch (ms since epoch) and the highest idMensaje the user has seen
  static const String keyNewsCache = 'news_cache';
  static const String keyNewsFromId = 'news_from_id';
  static const String keyNewsFetchedAt = 'news_fetched_at';
  static const String keyNewsLastReadId = 'news_last_read_id';
  // Stop catalog for the search by streets: the /v1/catalog/stops body
  // (JSON string) and the last fetch (ms since epoch)
  static const String keyStopCatalog = 'stop_catalog';
  static const String keyStopCatalogFetchedAt = 'stop_catalog_fetched_at';

  /// [path] overrides the storage directory (tests run without path_provider).
  static Future<void> init({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    // Guard against double init (hot restart, background isolate reuse)
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(BusStopAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(RouteAlertAdapter());
    await Hive.openBox(_settingsBox);
    await Hive.openBox<BusStop>(_stopsBox);
    await Hive.openBox<RouteAlert>(_routesBox);
  }

  // --- Generic settings ---

  static Box get _settings => Hive.box(_settingsBox);

  static T? get<T>(String key) => _settings.get(key) as T?;

  static Future<void> set<T>(String key, T value) =>
      _settings.put(key, value);

  static Future<void> remove(String key) => _settings.delete(key);

  // --- Bus stops ---

  static Box<BusStop> get _stops => Hive.box<BusStop>(_stopsBox);

  static List<BusStop> getAllStops() => _stops.values.toList();

  static List<BusStop> getStopsWithNotificationsEnabled() =>
      _stops.values.where((s) => s.notificationsEnabled).toList();

  static Future<void> saveStop(BusStop stop) =>
      _stops.put(stop.id, stop);

  static Future<void> deleteStop(int stopId) =>
      _stops.delete(stopId);

  static BusStop? getStop(int stopId) => _stops.get(stopId);

  // --- Route alerts ---

  static Box<RouteAlert> get _routes => Hive.box<RouteAlert>(_routesBox);

  static List<RouteAlert> getAllRoutes() => _routes.values.toList();

  static List<RouteAlert> getEnabledRoutes() =>
      _routes.values.where((r) => r.enabled).toList();

  static Future<void> saveRoute(RouteAlert route) =>
      _routes.put(route.id, route);

  static Future<void> deleteRoute(int routeId) => _routes.delete(routeId);

  static RouteAlert? getRoute(int routeId) => _routes.get(routeId);

  static int nextRouteId() {
    if (_routes.isEmpty) return 1;
    return (_routes.keys.cast<int>().reduce((a, b) => a > b ? a : b)) + 1;
  }
}
