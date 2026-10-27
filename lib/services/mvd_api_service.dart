import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/arrivals_board.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/catalog_stop.dart';
import '../models/gps_status.dart';
import '../models/scheduled_pass.dart';
import '../models/stop_details.dart';
import 'api/api_result.dart';
import 'api/contract_rules.dart';
import 'api/direct/transporte_rest_adapter.dart';
import 'api/direct_source.dart';
import 'api/proxy_source.dart';
import 'api/v1_parser.dart';
import 'api/v1_source.dart';
import 'cache_service.dart';

/// The stop code does not exist in the STM network.
class StopNotFoundException implements Exception {
  final int stopId;
  const StopNotFoundException(this.stopId);

  @override
  String toString() => 'StopNotFoundException($stopId)';
}

/// Arrivals, timetables, stop names, the stop catalog, transport news and
/// the GPS status.
///
/// With `--dart-define=MVD_PROXY_URL=https://…` every call goes to the
/// project's proxy (`proxy/`, routes `/v1`). The proxy holds the secret of the
/// official IM API (OAuth2, 14 requests a minute for everybody) and adds
/// comfort data — air conditioning, zero emission — to GPS arrivals.
///
/// Without it the app calls the public endpoints of the official Cómo Ir web
/// app (https://m.montevideo.gub.uy/comoir/) directly: no credentials, no
/// comfort data. Kept until the proxy is deployed — see docs/REVIEW.md.
///
/// Either way the answer is /v1 JSON ([V1Source]) read by [V1Parser]
/// (docs/design/contrato-v1.md).
class MvdApiService {
  /// From `--dart-define=MVD_PROXY_URL=…`; empty = transporteRest directly.
  @visibleForTesting
  static String proxyUrl = const String.fromEnvironment('MVD_PROXY_URL');
  static bool get usesProxy => proxyUrl.isNotEmpty;

  /// Where /v1 JSON comes from, decided on each call.
  static V1Source get source =>
      usesProxy ? ProxySource(proxyUrl) : const DirectSource();

  // Timetables change rarely: keep each answer for the app session
  static const _scheduleTtl = Duration(hours: 6);
  static final Map<String, (DateTime, List<ScheduledPass>)> _scheduleCache =
      {};

  // The stop catalog (~660 KB from the proxy) is kept on the device for a
  // day, and decoded once per app session
  static const _catalogTtl = Duration(days: 1);
  static List<CatalogStop>? _catalog;

  // After a 429 nothing is requested until then, in this isolate
  static DateTime? _busyUntil;

  // Boards being fetched by getBoards, so a stop is requested once at a time
  static final Map<int, Future<ApiResult<ArrivalsBoard>>> _boardsInFlight =
      {};

  /// Stop numbers that can exist; others are never requested.
  static bool isValidStopId(int id) => ContractRules.isValidStopId(id);

  /// [utc] on the Montevideo clock (UTC−3 all year), "H:MM".
  static String montevideoClock(DateTime utc) =>
      ContractRules.montevideoClock(utc);

  /// Upcoming buses of a stop, soonest first.
  static Future<ApiResult<ArrivalsBoard>> getBoard(int stopId) =>
      _call(stopId, () => source.arrivals(stopId),
          (json) => V1Parser.arrivals(json, stopId));

  /// The boards of several stops: each stop once, all in parallel. A stop
  /// already being fetched by another call shares that request.
  static Future<Map<int, ApiResult<ArrivalsBoard>>> getBoards(
      Iterable<int> stopIds) async {
    final ids = stopIds.toSet().toList();
    final results = await Future.wait([
      for (final id in ids)
        // A block: returning the removed future would make it wait for itself
        _boardsInFlight[id] ??= getBoard(id).whenComplete(() {
          _boardsInFlight.remove(id);
        }),
    ]);
    return {for (var i = 0; i < ids.length; i++) ids[i]: results[i]};
  }

  /// Name, lines and directions of a stop.
  static Future<ApiResult<StopDetails>> getStopDetails(int stopId) =>
      _call(stopId, () => source.stop(stopId),
          (json) => V1Parser.stop(json, stopId));

  /// Saved stops still named "Parada N" with no lines (saved while offline)
  /// get their name and lines. Returns how many were updated.
  static Future<int> healPlaceholderStops() async {
    var healed = 0;
    final placeholders = CacheService.getAllStops()
        .where((s) => s.name == 'Parada ${s.id}' && s.lines.isEmpty)
        .toList();
    for (final stop in placeholders) {
      final details = (await getStopDetails(stop.id)).valueOrNull;
      if (details == null ||
          (details.name == null && details.lines.isEmpty)) {
        continue;
      }
      stop
        ..name = details.displayName
        ..lines = [...details.lines];
      await CacheService.saveStop(stop);
      healed++;
    }
    return healed;
  }

  /// One /v1 request: the stop id checked first, nothing sent while busy,
  /// the answer read by [parse] (null = wrong shape).
  static Future<ApiResult<T>> _call<T>(
      int stopId,
      Future<SourceAnswer> Function() request,
      T? Function(Object? json) parse) async {
    if (!isValidStopId(stopId)) return const ApiError(ApiFailure.notFound);
    return _request(request, parse);
  }

  /// [request] after the busy check. With [backOff] a busy answer stops
  /// every request for its `retryAfter`: on every route but the catalog it
  /// can only be the proxy's 429, its limit per phone, which covers every
  /// route. The catalog's 503 upstream_busy is about the catalog alone.
  static Future<ApiResult<T>> _request<T>(
      Future<SourceAnswer> Function() request,
      T? Function(Object? json) parse,
      {bool backOff = true}) async {
    final busyUntil = _busyUntil;
    if (busyUntil != null) {
      final wait = busyUntil.difference(DateTime.now());
      if (wait > Duration.zero) {
        return ApiError(ApiFailure.busy, retryAfter: wait);
      }
      _busyUntil = null;
    }

    final answer = await request();
    final failure = answer.failure;
    if (failure != null) {
      if (backOff && failure == ApiFailure.busy && answer.retryAfter != null) {
        _busyUntil ??= DateTime.now().add(answer.retryAfter!);
      }
      return ApiError(failure, retryAfter: answer.retryAfter);
    }
    final value = parse(answer.json);
    if (value == null) {
      debugPrint('⚠️ Unexpected /v1 answer');
      return const ApiError(ApiFailure.failed);
    }
    return ApiOk(value);
  }

  /// Forgets a 429: the next call is sent.
  @visibleForTesting
  static void resetBusy() => _busyUntil = null;

  /// Returns upcoming buses for a stop, soonest first.
  /// Returns null on network/server error so callers can tell
  /// "no buses" apart from "could not check".
  static Future<List<BusArrival>?> getNextArrivals(int stopId) async =>
      (await getBoard(stopId)).valueOrNull?.arrivals;

  /// Theoretical timetable of a stop: about 50 passes from [hour]:[minute]
  /// on, for the given day type, wrapping past midnight.
  /// Returns null on network/server error.
  static Future<List<ScheduledPass>?> getSchedule(
      int stopId, DayType day, int hour, int minute) async {
    final key =
        '$stopId/${day.apiValue}/$hour:${minute.toString().padLeft(2, '0')}';
    final hit = _scheduleCache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _scheduleTtl) {
      return hit.$2;
    }

    final result = await _call(stopId,
        () => source.schedule(stopId, day, hour, minute), V1Parser.schedule);
    final passes = result.valueOrNull;
    if (passes != null) _scheduleCache[key] = (DateTime.now(), passes);
    return passes;
  }

  /// Resolves stop name and lines from a stop ID.
  /// Returns null on network error; throws [StopNotFoundException]
  /// if the server reports that the stop does not exist.
  static Future<BusStop?> resolveStop(int stopId) async {
    switch (await getStopDetails(stopId)) {
      case ApiOk(:final value):
        return value.toBusStop();
      case ApiError(failure: ApiFailure.notFound):
        throw StopNotFoundException(stopId);
      case ApiError():
        return null;
    }
  }

  /// Every stop with its street names, lines and location, for the search
  /// by streets and the nearby stops — only through the proxy
  /// (`/v1/catalog/stops`), null without it.
  /// Downloaded at most once a day; when the proxy cannot be reached an
  /// older copy is used. Returns null when there is neither.
  static Future<List<CatalogStop>?> getStopCatalog() async {
    if (!usesProxy) return null;

    final cached = await _cachedCatalog();
    final lastMs = CacheService.catalogFetchedAtMs;
    if (cached != null &&
        lastMs != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
            _catalogTtl) {
      return cached;
    }

    Object? body;
    final result = await _request(source.catalogStops, (json) {
      body = json;
      return V1Parser.catalog(json);
    }, backOff: false);
    final fresh = result.valueOrNull?.stops;
    if (fresh == null || fresh.isEmpty) return cached;

    _catalog = fresh;
    // The /v1 body as it came, read again by V1Parser
    await CacheService.saveCatalog(
        jsonEncode(body), DateTime.now().millisecondsSinceEpoch);
    return fresh;
  }

  static Future<List<CatalogStop>?> _cachedCatalog() async {
    if (_catalog != null) return _catalog;
    final raw = await CacheService.catalogBody();
    if (raw == null) return null;
    try {
      final stops = V1Parser.catalog(jsonDecode(raw))?.stops;
      return _catalog = stops == null || stops.isEmpty ? null : stops;
    } catch (e) {
      debugPrint('⚠️ Catalog cache error: $e');
      return null;
    }
  }

  /// Forgets the decoded catalog; the copy in Hive stays.
  @visibleForTesting
  static void clearCatalogMemory() => _catalog = null;

  /// The newest transport news, newest first: the last page of the
  /// notification backend (`/v1/news`, or the jump paging from id 0
  /// without the proxy).
  static Future<ApiResult<NewsList>> getNews() =>
      _request(source.news, V1Parser.news);

  /// The share of each operator's buses whose GPS data arrives.
  static Future<ApiResult<List<OperatorGpsStatus>>> getGpsStatus() =>
      _request(source.gpsStatus, V1Parser.gpsStatus);

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

  /// Lower case, no accents, apostrophes dropped, any other punctuation
  /// ("Nº", "S/N", parentheses) turned into single spaces.
  @visibleForTesting
  static String foldForSearch(String text) => CatalogStop.fold(text);

  /// A raw `GET /transporteRest/siguientesParada/{id}` answer through the
  /// direct-mode adapter and [V1Parser], soonest first; [now] is when it
  /// came. Empty when malformed.
  @visibleForTesting
  static List<BusArrival> parseArrivals(dynamic data, {DateTime? now}) {
    final v1 = TransporteRestAdapter.arrivalsToV1(data, 0,
        fetchedAt: now ?? DateTime.now());
    return V1Parser.arrivals(v1, 0)?.arrivals ?? [];
  }

  /// A raw `GET /transporteRest/siguientesParada/{id}/{tipoDia}/{H:MM}`
  /// answer through the direct-mode adapter and [V1Parser], in the API
  /// order (chronological, wrapping past midnight). Empty when malformed.
  @visibleForTesting
  static List<ScheduledPass> parseSchedule(dynamic data) =>
      V1Parser.schedule(TransporteRestAdapter.scheduleToV1(data)) ?? [];
}
