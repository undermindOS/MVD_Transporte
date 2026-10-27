import 'package:hive_flutter/hive_flutter.dart';
import '../models/bus_stop.dart';
import '../models/route_alert.dart';

class CacheService {
  static const String _settingsBox = 'settings';
  static const String _stopsBox = 'stops';
  static const String _routesBox = 'routes';
  // The stop catalog (~660 KB) has a lazy box of its own: read from disk
  // only when the catalog is needed, never kept in memory with the settings
  static const String _catalogBox = 'catalog';
  static const String _catalogBodyKey = 'body';
  static const String _catalogFetchedAtKey = 'fetched_at_ms';

  static const String keyBiometricEnabled = 'biometric_lock_enabled';
  // Transport news: cached messages (JSON string), paging start, last
  // fetch (ms since epoch) and the highest idMensaje the user has seen
  static const String keyNewsCache = 'news_cache';
  static const String keyNewsFromId = 'news_from_id';
  static const String keyNewsFetchedAt = 'news_fetched_at';
  static const String keyNewsLastReadId = 'news_last_read_id';
  // Stop catalog for the search by streets and the nearby stops: the
  // /v1/catalog/stops body (JSON string) and the last fetch (ms since
  // epoch). Both live in the catalog box ([catalogBody], [saveCatalog]);
  // [remove] with either name removes the copy.
  static const String keyStopCatalog = 'stop_catalog';
  static const String keyStopCatalogFetchedAt = 'stop_catalog_fetched_at';

  // What the settings box holds: 2 moved the catalog out of it
  static const String _keyCacheSchema = 'cache_schema';
  static const int _cacheSchema = 2;

  // When the catalog copy was fetched, null = no copy. Kept in memory so
  // that [remove] drops the copy at once, before the delete reaches the disk
  static int? _catalogFetchedAtMs;

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
    final catalog = await Hive.openLazyBox(_catalogBox);
    _catalogFetchedAtMs = await catalog.get(_catalogFetchedAtKey) as int?;
    await _migrate();
  }

  /// One-time changes to what an older version of the app saved.
  static Future<void> _migrate() async {
    final schema = _settings.get(_keyCacheSchema) as int? ?? 1;
    if (schema >= _cacheSchema) return;
    // Up to 1 the catalog was in the settings box, decoded at every start;
    // it is downloaded again into its own box
    await _settings.deleteAll([keyStopCatalog, keyStopCatalogFetchedAt]);
    await _settings.put(_keyCacheSchema, _cacheSchema);
  }

  // --- Generic settings ---

  static Box get _settings => Hive.box(_settingsBox);

  static T? get<T>(String key) => _settings.get(key) as T?;

  static Future<void> set<T>(String key, T value) =>
      _settings.put(key, value);

  /// Removes a setting; [keyStopCatalog] or [keyStopCatalogFetchedAt]
  /// removes the catalog copy.
  static Future<void> remove(String key) {
    if (key == keyStopCatalog || key == keyStopCatalogFetchedAt) {
      _catalogFetchedAtMs = null;
      return _catalog.deleteAll([_catalogBodyKey, _catalogFetchedAtKey]);
    }
    return _settings.delete(key);
  }

  // --- Stop catalog ---

  static LazyBox get _catalog => Hive.lazyBox(_catalogBox);

  /// When the catalog copy on the device was fetched (ms since epoch);
  /// null when there is no copy.
  static int? get catalogFetchedAtMs => _catalogFetchedAtMs;

  /// The /v1/catalog/stops body kept on the device, or null.
  static Future<String?> catalogBody() async {
    if (_catalogFetchedAtMs == null) return null;
    return await _catalog.get(_catalogBodyKey) as String?;
  }

  /// Keeps [body], fetched at [fetchedAtMs], as the catalog copy.
  static Future<void> saveCatalog(String body, int fetchedAtMs) {
    _catalogFetchedAtMs = fetchedAtMs;
    return _catalog.putAll(
        {_catalogBodyKey: body, _catalogFetchedAtKey: fetchedAtMs});
  }

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
