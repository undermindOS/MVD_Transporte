import 'package:flutter/foundation.dart';

import '../models/bus_stop.dart';
import '../models/catalog_stop.dart';
import 'cache_service.dart';
import 'mvd_api_service.dart';
import 'nearby_stops_service.dart';

/// Where the saved stops are, so the Mapa can place them.
///
/// A stop picked from a list is saved with its location; one typed by
/// number, or saved before the Mapa, has 0.0, 0.0 ([BusStop.hasLocation]).
/// Through the proxy the location comes from the stop catalog kept on the
/// phone ([MvdApiService.getStopCatalog]), and no city host is asked.
/// Without it, from the WFS layer of geoserver, one stop at a time by its
/// number ([NearbyStopsService.fetchStop]): no position is sent.
class StopLocationsService {
  /// A stop is looked up at most this often, found or not.
  static const retryInterval = Duration(minutes: 10);

  /// Now; tests move it.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  // When each stop was last looked up, in this app session
  static final Map<int, DateTime> _attemptedAt = {};

  /// Looks up the stops of [stops] without a location, not looked up in the
  /// last [retryInterval], and saves the locations found. Returns how many
  /// stops got one. A stop not found keeps 0.0 and is not drawn.
  static Future<int> fillMissing(Iterable<BusStop> stops) async {
    final now = clock();
    final missing = <BusStop>[];
    for (final stop in stops) {
      if (stop.hasLocation) continue;
      final last = _attemptedAt[stop.id];
      if (last != null && now.difference(last) < retryInterval) continue;
      // Marked before the request: a second call meanwhile skips it
      _attemptedAt[stop.id] = now;
      missing.add(stop);
    }
    if (missing.isEmpty) return 0;

    var filled = 0;
    if (MvdApiService.usesProxy) {
      final catalog = await MvdApiService.getStopCatalog();
      if (catalog == null) return 0;
      final byId = {for (final s in catalog) s.id: s};
      for (final stop in missing) {
        final found = byId[stop.id];
        if (found != null && await _save(stop, found)) filled++;
      }
    } else {
      // One at a time: geoserver is the city's, and the stops are few
      for (final stop in missing) {
        final found = await NearbyStopsService.fetchStop(stop.id);
        if (found != null && await _save(stop, found)) filled++;
      }
    }
    return filled;
  }

  /// Saves the location of [found] into [stop] and its saved copy. False
  /// when the stop was deleted meanwhile: it is not saved back.
  static Future<bool> _save(BusStop stop, CatalogStop found) async {
    final saved = CacheService.getStop(stop.id);
    if (saved == null) return false;
    for (final s in [stop, saved]) {
      s
        ..latitude = found.latitude
        ..longitude = found.longitude;
    }
    await CacheService.saveStop(saved);
    return true;
  }

  /// Forgets the lookups and restores the clock, as at app start.
  @visibleForTesting
  static void reset() {
    _attemptedAt.clear();
    clock = DateTime.now;
  }
}
