// The /v1 contract from the app's side (proxy/contract/v1/README.md), for
// every case of cases.json:
// - direct mode: DirectSource, served the same upstream captures the proxy
//   tests use, gives the golden with the case's masks, from exactly the
//   listed URLs, or the expected failure;
// - proxy mode: the golden, served as the proxy's answer, gives the model
//   through V1Parser, or the expected ApiFailure.
// The proxy's side of the triangle is proxy/test/contract.test.js.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stm_app/models/arrivals_board.dart';
import 'package:stm_app/models/gps_status.dart';
import 'package:stm_app/models/scheduled_pass.dart';
import 'package:stm_app/models/stop_details.dart';
import 'package:stm_app/services/api/api_result.dart';
import 'package:stm_app/services/api/direct_source.dart';
import 'package:stm_app/services/api/v1_parser.dart';
import 'package:stm_app/services/api/v1_source.dart';
import 'package:stm_app/services/mvd_api_service.dart';

import '../support/contract_cases.dart';

void main() {
  final cases = contractCases();

  tearDown(() {
    MvdApiService.proxyUrl = '';
    MvdApiService.resetBusy();
  });

  group('cases.json', () {
    test('ids are unique', () {
      final ids = cases.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('masks are within direct_masks.json', () {
      final allowed = contractMasks();
      for (final c in cases) {
        expect(allowed, containsAll(c.direct?.mask ?? const <String>[]),
            reason: c.id);
      }
    });

    test('the app has a call for every request it makes', () {
      for (final c in cases.where((c) => c.direct != null || c.dart != null)) {
        expect(_callFor(c.request), isNotNull, reason: c.id);
      }
    });
  });

  group('direct mode', () {
    for (final c in cases.where((c) => c.direct != null)) {
      test(c.id, () async {
        final expected = c.direct!;
        final call = _callFor(c.request)!;
        final requested = <String>[];
        final client = upstreamClient(c, requested);

        if (c.dart?.request == false) {
          // Turned down before any source is asked
          final result = await http.runWithClient(call.app, () => client);
          expect(requested, isEmpty);
          _expectFailure(result, expected.failure!, null);
          return;
        }

        final answer = await http.runWithClient(
            () => call.source(const DirectSource()), () => client);
        expect(requested..sort(), [...expected.upstream]..sort());
        expect(answer.failure?.name, expected.failure);
        if (expected.failure != null) return;

        var golden = applyMask(c.golden, expected.mask);
        var json = answer.json;
        if ((golden as Map).containsKey('fetchedAt')) {
          expect((json as Map)['fetchedAt'], matches(isoMillis));
          golden = withoutFetchedAt(golden);
          json = withoutFetchedAt(json);
        }
        expect(canonicalJson(json), canonicalJson(golden));
      });
    }
  });

  group('proxy mode', () {
    setUp(() => MvdApiService.proxyUrl = proxyBase);

    for (final c in cases.where((c) => c.dart != null)) {
      test(c.id, () async {
        final expected = c.dart!;
        final call = _callFor(c.request)!;
        final requested = <String>[];

        final result = await http.runWithClient(
            call.app, () => proxyClient(c, requested));
        expect(requested,
            expected.request ? ['$proxyBase${c.request}'] : isEmpty);

        if (expected.failure != null) {
          _expectFailure(result, expected.failure!, expected.retryAfter);
          return;
        }
        expect(result, isA<ApiOk<Object>>());
        final model = call.toV1((result as ApiOk<Object>).value);
        // The golden's sample `fetchedAt` too, where the model keeps it
        var golden = call.dartView((c.golden as Map).cast<String, Object?>());
        if (!model.containsKey('fetchedAt')) golden = withoutFetchedAt(golden);
        expect(canonicalJson(model), canonicalJson(golden));
      });
    }
  });
}

void _expectFailure(ApiResult<Object> result, String failure, int? retryAfter) {
  expect(result, isA<ApiError<Object>>());
  final error = result as ApiError<Object>;
  expect(error.failure.name, failure);
  expect(error.retryAfter,
      retryAfter == null ? isNull : Duration(seconds: retryAfter));
}

/// What the app does for one /v1 request path.
class _Call {
  const _Call({
    required this.source,
    required this.app,
    required this.toV1,
    this.dartView = _asIs,
  });

  /// The request to a source: its /v1 JSON, or why there is none.
  final Future<SourceAnswer> Function(V1Source source) source;

  /// The request as the app makes it, through [MvdApiService]: the model,
  /// or why there is none.
  final Future<ApiResult<Object>> Function() app;

  /// The model written back as /v1 JSON, to compare with the golden.
  final Map<String, Object?> Function(Object model) toV1;

  /// The golden as the app reads it, where the app adds a rule of its own.
  final Object? Function(Map<String, Object?> golden) dartView;

  static Object? _asIs(Map<String, Object?> golden) => golden;
}

final _stopPath = RegExp(r'^/v1/stops/(\d+)$');
final _arrivalsPath = RegExp(r'^/v1/stops/(\d+)/arrivals$');
final _schedulePath =
    RegExp(r'^/v1/stops/(\d+)/schedule/(\w+)/(\d+):(\d{2})$');

/// The app's call for [request]; null for a request the app never makes.
_Call? _callFor(String request) {
  if (_stopPath.firstMatch(request) case final m?) {
    final id = int.parse(m[1]!);
    return _Call(
      source: (s) => s.stop(id),
      app: () => MvdApiService.getStopDetails(id),
      toV1: (model) => _stopToV1(model as StopDetails),
    );
  }
  if (_arrivalsPath.firstMatch(request) case final m?) {
    final id = int.parse(m[1]!);
    return _Call(
      source: (s) => s.arrivals(id),
      app: () => MvdApiService.getBoard(id),
      toV1: (model) => _boardToV1(model as ArrivalsBoard),
    );
  }
  if (_schedulePath.firstMatch(request) case final m?) {
    final id = int.parse(m[1]!);
    final day = DayType.values.where((d) => d.proxyValue == m[2]).firstOrNull;
    if (day == null) return null;
    final hour = int.parse(m[3]!), minute = int.parse(m[4]!);
    return _Call(
      source: (s) => s.schedule(id, day, hour, minute),
      // getSchedule gives null for every failure; the source tells which
      app: () => _parsed(MvdApiService.source.schedule(id, day, hour, minute),
          V1Parser.schedule),
      toV1: (model) => _scheduleToV1(model as List<ScheduledPass>),
    );
  }
  return switch (request) {
    '/v1/catalog/stops' => _Call(
        source: (s) => s.catalogStops(),
        // getStopCatalog keeps a copy in Hive and gives no failure
        app: () => _parsed(MvdApiService.source.catalogStops(),
            V1Parser.catalog),
        toV1: (model) => _catalogToV1(model as StopCatalog),
        // A stop without street names is "Parada N"
        dartView: (golden) => {
          ...golden,
          'stops': [
            for (final s in golden['stops'] as List)
              {...s as Map, 'name': s['name'] ?? 'Parada ${s['id']}'},
          ],
        },
      ),
    '/v1/news' => _Call(
        source: (s) => s.news(),
        app: MvdApiService.getNews,
        toV1: (model) => _newsToV1(model as NewsList),
      ),
    '/v1/status/gps' => _Call(
        source: (s) => s.gpsStatus(),
        app: MvdApiService.getGpsStatus,
        toV1: (model) => _gpsToV1(model as List<OperatorGpsStatus>),
      ),
    _ => null,
  };
}

/// [answer] read by [parse], the way MvdApiService reads a source.
Future<ApiResult<Object>> _parsed(Future<SourceAnswer> answer,
    Object? Function(Object? json) parse) async {
  final a = await answer;
  if (a.failure != null) return ApiError(a.failure!, retryAfter: a.retryAfter);
  final value = parse(a.json);
  return value == null ? const ApiError(ApiFailure.failed) : ApiOk(value);
}

Map<String, Object?> _stopToV1(StopDetails stop) => {
      'id': stop.id,
      'name': stop.name,
      'lines': stop.lines,
      'directions': [
        for (final d in stop.directions)
          {
            'line': d.line,
            'destination': d.destination,
            'variantIds': d.variantIds,
          },
      ],
    };

Map<String, Object?> _boardToV1(ArrivalsBoard board) => {
      'id': board.stopId,
      'fetchedAt': board.fetchedAt.toIso8601String(),
      'arrivals': [
        for (final a in board.arrivals)
          {
            'tripId': a.tripId,
            'variantId': a.variantId,
            'line': a.line,
            'destination': a.destination,
            'state': a.state.name,
            'etaMinutes': a.etaMinutes,
            'expectedAt': a.expectedAt.toIso8601String(),
            'clockTime': a.clockTime,
            'accessible': a.accessible,
            'airConditioning': a.airConditioning,
            'zeroEmission': a.zeroEmission,
            'location': switch (a.location) {
              (:final lat, :final lng) => {'lat': lat, 'lng': lng},
              null => null,
            },
          },
      ],
    };

Map<String, Object?> _scheduleToV1(List<ScheduledPass> passes) => {
      'passes': [
        for (final p in passes)
          {
            'line': p.line,
            'destination': p.destination,
            'time': p.time,
            'hhmm': p.hhmm,
          },
      ],
    };

Map<String, Object?> _catalogToV1(StopCatalog catalog) => {
      'fetchedAt': catalog.fetchedAt.toIso8601String(),
      'linesAvailable': catalog.linesAvailable,
      'stops': [
        for (final s in catalog.stops)
          {
            'id': s.id,
            'name': s.name,
            'location': {'lat': s.latitude, 'lng': s.longitude},
            'lines': s.lines,
          },
      ],
    };

Map<String, Object?> _newsToV1(NewsList list) => {
      'fetchedAt': list.fetchedAt.toIso8601String(),
      'news': [
        for (final n in list.news)
          {
            'id': n.id,
            'title': n.title,
            'summary': n.summary,
            'body': n.body,
            'link': n.link,
            'publishedAt': n.date.toUtc().toIso8601String(),
          },
      ],
    };

Map<String, Object?> _gpsToV1(List<OperatorGpsStatus> operators) => {
      'operators': [
        for (final o in operators)
          {'company': o.company, 'percent': o.percent, 'partial': o.partial},
      ],
    };
