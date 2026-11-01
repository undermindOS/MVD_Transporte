import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/place.dart';
import 'cache_service.dart';

/// The person's places (Casa, Trabajo, favourites) and how far they walk
/// to a stop, kept in the settings box. Only on the phone.
abstract final class PlacesService {
  /// The walking limits the planner offers, in minutes at each end.
  static const walkOptions = [5, 10, 15];
  static const defaultWalkMinutes = 10;

  /// Casa, then Trabajo, then the favourites in the order they were kept.
  /// [load] fills it; every change here updates it.
  static final places = ValueNotifier<List<Place>>(const []);

  /// Reads the saved places into [places].
  static void load() {
    final raw = CacheService.get<String>(CacheService.keyPlaces);
    places.value = _sorted(_decode(raw));
  }

  /// Keeps [place]: a Casa or Trabajo replaces the one there was, a
  /// favourite with the same id is replaced.
  static Future<void> save(Place place) {
    final next = [
      for (final p in places.value)
        if (p.id != place.id) p,
      place,
    ];
    return _write(next);
  }

  static Future<void> delete(String id) => _write([
    for (final p in places.value)
      if (p.id != id) p,
  ]);

  /// Minutes the person walks at most to the first stop and from the last
  /// one: one of [walkOptions].
  static int get walkMinutes {
    final saved = CacheService.get<int>(CacheService.keyWalkMinutes);
    return walkOptions.contains(saved) ? saved! : defaultWalkMinutes;
  }

  static Future<void> setWalkMinutes(int minutes) {
    if (!walkOptions.contains(minutes)) throw ArgumentError.value(minutes);
    return CacheService.set<int>(CacheService.keyWalkMinutes, minutes);
  }

  static Future<void> _write(List<Place> list) {
    places.value = _sorted(list);
    return CacheService.set<String>(
      CacheService.keyPlaces,
      jsonEncode([for (final p in places.value) p.toJson()]),
    );
  }

  static List<Place> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?Place.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }

  static List<Place> _sorted(List<Place> list) => List.unmodifiable([
    ...list.where((p) => p.kind == PlaceKind.casa).take(1),
    ...list.where((p) => p.kind == PlaceKind.trabajo).take(1),
    ...list.where((p) => p.kind == PlaceKind.favorito),
  ]);
}
