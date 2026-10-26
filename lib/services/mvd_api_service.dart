import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/catalog_stop.dart';
import '../models/scheduled_pass.dart';
import 'cache_service.dart';

/// The stop code does not exist in the STM network.
class StopNotFoundException implements Exception {
  final int stopId;
  const StopNotFoundException(this.stopId);

  @override
  String toString() => 'StopNotFoundException($stopId)';
}

/// Arrivals, timetables and stop names.
///
/// With `--dart-define=MVD_PROXY_URL=https://…` every call goes to the
/// project's proxy (`proxy/`, routes `/v1`). The proxy holds the secret of the
/// official IM API (OAuth2, 14 requests a minute for everybody) and adds
/// comfort data — air conditioning, zero emission — to GPS arrivals.
///
/// Without it the app calls the public endpoints of the official Cómo Ir web
/// app (https://m.montevideo.gub.uy/comoir/) directly: no credentials, no
/// comfort data. Kept until the proxy is deployed — see docs/REVIEW.md.
class MvdApiService {
  /// From `--dart-define=MVD_PROXY_URL=…`; empty = transporteRest directly.
  @visibleForTesting
  static String proxyUrl = const String.fromEnvironment('MVD_PROXY_URL');
  static bool get usesProxy => proxyUrl.isNotEmpty;

  static const _baseUrl = 'https://api.montevideo.gub.uy/transporteRest';
  static const _nextBusesPath = '/siguientesParada';
  static const _stopLinesPath = '/lineas';

  static const _timeout = Duration(seconds: 10);
  static const _headers = {'Accept': 'application/json'};

  // Timetables change rarely: keep each answer for the app session
  static const _scheduleTtl = Duration(hours: 6);
  static final Map<String, (DateTime, List<ScheduledPass>)> _scheduleCache =
      {};

  // The stop catalog (~520 KB from the proxy) is kept on the device for a
  // day, and decoded once per app session
  static const _catalogTtl = Duration(days: 1);
  static const _catalogTimeout = Duration(seconds: 30);
  static List<CatalogStop>? _catalog;

  /// Returns upcoming buses for a stop, soonest first.
  /// Returns null on network/server error so callers can tell
  /// "no buses" apart from "could not check".
  static Future<List<BusArrival>?> getNextArrivals(int stopId) async {
    try {
      final uri = Uri.parse(usesProxy
          ? '$proxyUrl/v1/stops/$stopId/arrivals'
          : '$_baseUrl$_nextBusesPath/$stopId');
      final response =
          await http.get(uri, headers: _headers).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ ETA API ${response.statusCode}: ${response.body}');
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return usesProxy ? parseProxyArrivals(data) : parseArrivals(data);
    } catch (e) {
      debugPrint('❌ ETA API error: $e');
      return null;
    }
  }

  /// Theoretical timetable of a stop: about 50 passes from [hour]:[minute]
  /// on, for the given day type, wrapping past midnight.
  /// Returns null on network/server error.
  static Future<List<ScheduledPass>?> getSchedule(
      int stopId, DayType day, int hour, int minute) async {
    final time = '$hour:${minute.toString().padLeft(2, '0')}';
    final key = '$stopId/${day.apiValue}/$time';
    final hit = _scheduleCache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _scheduleTtl) {
      return hit.$2;
    }

    try {
      final uri = Uri.parse(usesProxy
          ? '$proxyUrl/v1/stops/$stopId/schedule/${day.proxyValue}/$time'
          : '$_baseUrl$_nextBusesPath/$key');
      final response =
          await http.get(uri, headers: _headers).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('❌ Schedule API ${response.statusCode}: ${response.body}');
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final passes =
          usesProxy ? parseProxySchedule(data) : parseSchedule(data);
      _scheduleCache[key] = (DateTime.now(), passes);
      return passes;
    } catch (e) {
      debugPrint('❌ Schedule API error: $e');
      return null;
    }
  }

  /// Resolves stop name and lines from a stop ID.
  /// Returns null on network error; throws [StopNotFoundException]
  /// if the server reports that the stop does not exist.
  static Future<BusStop?> resolveStop(int stopId) async {
    final http.Response response;
    try {
      final uri = Uri.parse(usesProxy
          ? '$proxyUrl/v1/stops/$stopId'
          : '$_baseUrl$_stopLinesPath/$stopId');
      response = await http.get(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      debugPrint('❌ Lineas API error: $e');
      return null;
    }

    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      // transporteRest answers 500 "No existe la ubicación de parada con
      // código 'N'.", the proxy 404 {"error":"stop_not_found"}
      if (body.contains('No existe') || body.contains('"stop_not_found"')) {
        throw StopNotFoundException(stopId);
      }
      debugPrint('❌ Lineas API ${response.statusCode}: $body');
      return null;
    }

    try {
      final data = jsonDecode(body);
      return usesProxy
          ? parseProxyStop(stopId, data)
          : parseStop(stopId, data);
    } catch (e) {
      debugPrint('⚠️ Parse stop error: $e');
      return null;
    }
  }

  /// Every stop with its street names, for the search by streets — only
  /// through the proxy (`/v1/catalog/stops`), null without it.
  /// Downloaded at most once a day; when the proxy cannot be reached an
  /// older copy is used. Returns null when there is neither.
  static Future<List<CatalogStop>?> getStopCatalog() async {
    if (!usesProxy) return null;

    final cached = _cachedCatalog();
    final lastMs = CacheService.get<int>(CacheService.keyStopCatalogFetchedAt);
    if (cached != null &&
        lastMs != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
            _catalogTtl) {
      return cached;
    }

    final List<CatalogStop> fresh;
    try {
      final response = await http
          .get(Uri.parse('$proxyUrl/v1/catalog/stops'), headers: _headers)
          .timeout(_catalogTimeout);
      if (response.statusCode != 200) {
        debugPrint('❌ Catalog API ${response.statusCode}: ${response.body}');
        return cached;
      }
      fresh = parseStopCatalog(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('❌ Catalog API error: $e');
      return cached;
    }
    if (fresh.isEmpty) return cached;

    _catalog = fresh;
    // Only what the search needs: ~270 KB of the proxy's ~520 KB
    await CacheService.set(
        CacheService.keyStopCatalog,
        jsonEncode({
          'stops': [
            for (final s in fresh) {'id': s.id, 'name': s.name},
          ],
        }));
    await CacheService.set(CacheService.keyStopCatalogFetchedAt,
        DateTime.now().millisecondsSinceEpoch);
    return fresh;
  }

  static List<CatalogStop>? _cachedCatalog() {
    if (_catalog != null) return _catalog;
    final raw = CacheService.get<String>(CacheService.keyStopCatalog);
    if (raw == null) return null;
    try {
      final stops = parseStopCatalog(jsonDecode(raw));
      return _catalog = stops.isEmpty ? null : stops;
    } catch (e) {
      debugPrint('⚠️ Catalog cache error: $e');
      return null;
    }
  }

  /// Forgets the decoded catalog; the copy in Hive stays.
  @visibleForTesting
  static void clearCatalogMemory() => _catalog = null;

  /// Stops whose name contains every word of [query], in any order,
  /// ignoring case, accents and punctuation: "18 de julio ejido" finds
  /// "AV 18 DE JULIO y EJIDO". Several words typed in a row that make a
  /// street name come first ("san jose" → "SAN JOSE y ANDES" before "AV
  /// GRAL SAN MARTIN y BV JOSE BATLLE…"), then names where the words start
  /// a word ("rio" → "RIO NEGRO" before "GREGORIO"), then alphabetical.
  /// At most [limit] stops.
  static List<CatalogStop> searchStops(
      List<CatalogStop> catalog, String query,
      {int limit = 50}) {
    final words =
        foldForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final phrase = words.length > 1 ? words.join(' ') : null;

    final hits = <(CatalogStop, bool, int)>[];
    for (final stop in catalog) {
      final key = stop.searchKey;
      if (!words.every(key.contains)) continue;
      final inARow = phrase != null &&
          (key.startsWith(phrase) || key.contains(' $phrase'));
      final wordStarts = words
          .where((w) => key.startsWith(w) || key.contains(' $w'))
          .length;
      hits.add((stop, inARow, wordStarts));
    }

    hits.sort((a, b) {
      if (a.$2 != b.$2) return a.$2 ? -1 : 1;
      final byStarts = b.$3.compareTo(a.$3);
      if (byStarts != 0) return byStarts;
      final byName = a.$1.name.compareTo(b.$1.name);
      return byName != 0 ? byName : a.$1.id.compareTo(b.$1.id);
    });
    return [for (final h in hits.take(limit)) h.$1];
  }

  static const _plainLetters = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ñ': 'n', 'ç': 'c',
    // The catalog writes ORDOÑEZ as "ORDOÐEZ" (stops 5340–5346)
    'ð': 'n',
  };
  static final _accented = RegExp('[${_plainLetters.keys.join()}]');
  static final _combiningMarks = RegExp('[\u0300-\u036f]');
  // "O´HIGGINS" = "ohiggins", whichever apostrophe the user types
  static final _apostrophes = RegExp('[´\'’‘`]');
  static final _separators = RegExp('[^a-z0-9]+');

  /// Lower case, no accents, apostrophes dropped, any other punctuation
  /// ("Nº", "S/N", parentheses) turned into single spaces.
  @visibleForTesting
  static String foldForSearch(String text) => text
      .toLowerCase()
      .replaceAll(_combiningMarks, '')
      .replaceAllMapped(_accented, (m) => _plainLetters[m[0]]!)
      .replaceAll(_apostrophes, '')
      .replaceAll(_separators, ' ')
      .trim();

  /// Parses the proxy's `GET /v1/catalog/stops` (and the copy kept in Hive):
  /// `{"fetchedAt":"…","stops":[{"id":574,"name":"SAN JOSE y ANDES",
  ///   "location":{"lat":-34.9,"lng":-56.2}}]}`
  /// Stops without a name cannot be found by streets and are left out.
  @visibleForTesting
  static List<CatalogStop> parseStopCatalog(dynamic data) {
    final list = data is Map ? data['stops'] : null;
    if (list is! List) return [];
    return [
      for (final item in list)
        if (item is Map &&
            item['id'] is int &&
            item['name'] is String &&
            (item['name'] as String).trim().isNotEmpty)
          CatalogStop(
            id: item['id'] as int,
            name: (item['name'] as String).trim(),
            searchKey: foldForSearch(item['name'] as String),
          ),
    ];
  }

  /// Parses `GET /transporteRest/siguientesParada/{id}`:
  /// `[{"linea":"145","minutos":5,"real":true,"destino":"PLAZA ESPAÑA",
  ///    "idEmpresa":50,"horaDesc":"7:39","coordinates":[lng,lat],
  ///    "accesibilidad":true,"tipoAccesibilidad":2, ...}]`
  @visibleForTesting
  static List<BusArrival> parseArrivals(dynamic data) {
    final arrivals = <BusArrival>[];
    if (data is! List) return arrivals;

    for (final item in data) {
      try {
        if (item is! Map) continue;
        final line = item['linea']?.toString() ?? '';
        final rawMinutes = item['minutos'];
        if (line.isEmpty || rawMinutes == null) continue;

        final etaMinutes = _safeInt(rawMinutes);

        double? lat, lng;
        final coords = item['coordinates'];
        if (coords is List && coords.length >= 2) {
          lng = (coords[0] as num?)?.toDouble();
          lat = (coords[1] as num?)?.toDouble();
        }

        arrivals.add(BusArrival(
          line: line,
          companyCode: _safeInt(item['idEmpresa']),
          etaMinutes: etaMinutes,
          etaSeconds: etaMinutes * 60,
          busLatitude: lat,
          busLongitude: lng,
          destination: item['destino']?.toString() ?? '',
          isRealTime: item['real'] == true,
          scheduledTime: item['horaDesc']?.toString(),
          accessible: item['accesibilidad'] == true,
          accessibilityType: item['tipoAccesibilidad'] == null
              ? null
              : _safeInt(item['tipoAccesibilidad']),
        ));
      } catch (e) {
        debugPrint('⚠️ Parse arrival error: $e');
      }
    }

    arrivals.sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
    return arrivals;
  }

  /// Parses `GET /transporteRest/siguientesParada/{id}/{tipoDia}/{H:MM}` —
  /// the same items as [parseArrivals], with `minutos: null`, `real: false`:
  /// `[{"linea":"145","destino":"PLAZA ESPAÑA","hora":803,"horaDesc":"8:03"}]`
  /// Keeps the API order (chronological, wrapping past midnight).
  @visibleForTesting
  static List<ScheduledPass> parseSchedule(dynamic data) {
    final passes = <ScheduledPass>[];
    if (data is! List) return passes;

    for (final item in data) {
      if (item is! Map) continue;
      final line = item['linea']?.toString() ?? '';
      final time = item['horaDesc']?.toString() ?? '';
      if (line.isEmpty || time.isEmpty) continue;
      passes.add(ScheduledPass(
        line: line,
        destination: item['destino']?.toString() ?? '',
        time: time,
        hhmm: _safeInt(item['hora']),
      ));
    }
    return passes;
  }

  /// Parses `GET /transporteRest/lineas/{id}`:
  /// `{"descripcion":"AV RAMON ANADOR y TIBURCIO GOMEZ",
  ///   "lineas":[{"descripcion":"140","codigo":56}, ...]}`
  @visibleForTesting
  static BusStop? parseStop(int stopId, dynamic data) {
    if (data is! Map) return null;

    final lines = <String>[];
    final list = data['lineas'];
    if (list is List) {
      for (final l in list) {
        final name = l is Map ? l['descripcion']?.toString() : null;
        if (name != null && name.isNotEmpty && !lines.contains(name)) {
          lines.add(name);
        }
      }
    }

    final description = data['descripcion']?.toString().trim() ?? '';
    return BusStop(
      id: stopId,
      name: description.isNotEmpty ? description : 'Parada $stopId',
      lines: lines,
    );
  }

  /// Parses the proxy's `GET /v1/stops/{id}/arrivals`:
  /// `{"fetchedAt":"…","arrivals":[{"line":"117","destination":"PUNTA CARRETAS",
  ///   "etaMinutes":4,"realTime":true,"scheduledTime":"19:56","companyId":50,
  ///   "location":{"lat":-34.9,"lng":-56.2},"accessible":true,
  ///   "accessibilityType":2,
  ///   "vehicle":{"airConditioning":true,"zeroEmission":false}}]}`
  /// `vehicle` is null for timetable estimates and unknown buses.
  @visibleForTesting
  static List<BusArrival> parseProxyArrivals(dynamic data) {
    final arrivals = <BusArrival>[];
    final list = data is Map ? data['arrivals'] : null;
    if (list is! List) return arrivals;

    for (final item in list) {
      if (item is! Map) continue;
      final line = item['line']?.toString() ?? '';
      final minutes = item['etaMinutes'];
      if (line.isEmpty || minutes is! num) continue;

      final location = item['location'];
      final vehicle = item['vehicle'];
      arrivals.add(BusArrival(
        line: line,
        companyCode: _safeInt(item['companyId']),
        etaMinutes: minutes.toInt(),
        etaSeconds: minutes.toInt() * 60,
        busLatitude: location is Map ? (location['lat'] as num?)?.toDouble() : null,
        busLongitude:
            location is Map ? (location['lng'] as num?)?.toDouble() : null,
        destination: item['destination']?.toString() ?? '',
        isRealTime: item['realTime'] == true,
        scheduledTime: item['scheduledTime']?.toString(),
        accessible: item['accessible'] == true,
        accessibilityType: item['accessibilityType'] is num
            ? (item['accessibilityType'] as num).toInt()
            : null,
        airConditioning: vehicle is Map ? _bool(vehicle['airConditioning']) : null,
        zeroEmission: vehicle is Map ? _bool(vehicle['zeroEmission']) : null,
      ));
    }

    arrivals.sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
    return arrivals;
  }

  /// Parses the proxy's `GET /v1/stops/{id}/schedule/{day}/{H:MM}`:
  /// `{"passes":[{"line":"143","destination":"CIUDADELA","time":"8:09","hhmm":809}]}`
  @visibleForTesting
  static List<ScheduledPass> parseProxySchedule(dynamic data) {
    final passes = <ScheduledPass>[];
    final list = data is Map ? data['passes'] : null;
    if (list is! List) return passes;

    for (final item in list) {
      if (item is! Map) continue;
      final line = item['line']?.toString() ?? '';
      final time = item['time']?.toString() ?? '';
      if (line.isEmpty || time.isEmpty) continue;
      passes.add(ScheduledPass(
        line: line,
        destination: item['destination']?.toString() ?? '',
        time: time,
        hhmm: _safeInt(item['hhmm']),
      ));
    }
    return passes;
  }

  /// Parses the proxy's `GET /v1/stops/{id}`:
  /// `{"id":574,"name":"SAN JOSE y ANDES","lines":["116","117"]}`
  @visibleForTesting
  static BusStop? parseProxyStop(int stopId, dynamic data) {
    if (data is! Map) return null;
    final lines = <String>[
      for (final l in data['lines'] is List ? data['lines'] as List : const [])
        if (l is String && l.isNotEmpty) l,
    ];
    final name = data['name']?.toString().trim() ?? '';
    return BusStop(
      id: stopId,
      name: name.isNotEmpty ? name : 'Parada $stopId',
      lines: lines,
    );
  }

  static bool? _bool(dynamic value) => value is bool ? value : null;

  /// Safely parse an int from a dynamic value (may be int, String, or null).
  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
