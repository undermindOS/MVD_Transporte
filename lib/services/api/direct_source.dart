import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/scheduled_pass.dart';
import 'api_result.dart';
import 'contract_rules.dart';
import 'direct/news_adapter.dart';
import 'direct/pci_adapter.dart';
import 'direct/transporte_rest_adapter.dart';
import 'proxy_source.dart';
import 'v1_source.dart';

/// Without a proxy: the public endpoints of the official Cómo Ir web app,
/// called from the phone and turned into /v1 JSON by the adapters in
/// `direct/`. No credentials, so no comfort data, no directions and no
/// stop catalog. Kept until the proxy is deployed — see docs/REVIEW.md.
class DirectSource implements V1Source {
  const DirectSource();

  static const _timeout = Duration(seconds: 10);
  static const _headers = {'Accept': 'application/json'};

  @override
  Future<SourceAnswer> stop(int id) async {
    final raw = await _get(TransporteRestAdapter.stopUrl(id),
        transporteRest: true);
    if (raw.failure != null) return raw;
    return _converted(TransporteRestAdapter.stopToV1(raw.json, id));
  }

  @override
  Future<SourceAnswer> arrivals(int id) async {
    final raw = await _get(TransporteRestAdapter.arrivalsUrl(id),
        transporteRest: true);
    if (raw.failure != null) return raw;
    return _converted(TransporteRestAdapter.arrivalsToV1(raw.json, id,
        fetchedAt: DateTime.now()));
  }

  @override
  Future<SourceAnswer> schedule(
      int id, DayType day, int hour, int minute) async {
    final raw = await _get(
        ContractRules.schedulePath(id, day.proxyValue, hour, minute).directUrl,
        transporteRest: true);
    if (raw.failure != null) return raw;
    return _converted(TransporteRestAdapter.scheduleToV1(raw.json));
  }

  /// Only the proxy has the catalog (it needs the official API's secret).
  @override
  Future<SourceAnswer> catalogStops() async =>
      answerFailure(ApiFailure.unavailable);

  /// The jump paging from id 0: the same list the proxy gives on a cold
  /// start.
  @override
  Future<SourceAnswer> news() async {
    SourceAnswer? failed;
    final result = await NewsAdapter.fetchNewest(0, (from) async {
      final raw = await _get(NewsAdapter.pageUrl(from));
      if (raw.failure != null) {
        failed = raw;
        return null;
      }
      final page = NewsAdapter.pageToV1(raw.json);
      if (page == null) failed = answerFailure(ApiFailure.failed);
      return page;
    });
    if (result == null) return failed ?? answerFailure(ApiFailure.failed);
    return answerJson(
        NewsAdapter.messagesToV1(result.page, fetchedAt: DateTime.now()));
  }

  @override
  Future<SourceAnswer> gpsStatus() async {
    final raw = await _get(PciAdapter.url);
    if (raw.failure != null) return raw;
    return _converted(
        PciAdapter.controlToV1(raw.json, fetchedAt: DateTime.now()));
  }

  static SourceAnswer _converted(Map<String, Object?>? v1) =>
      v1 == null ? answerFailure(ApiFailure.failed) : answerJson(v1);

  /// The decoded JSON of [url], or why there is none.
  static Future<SourceAnswer> _get(String url,
      {bool transporteRest = false}) async {
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(_timeout);
    } on TimeoutException {
      return answerFailure(ApiFailure.timeout);
    } on SocketException {
      return answerFailure(ApiFailure.offline);
    } on http.ClientException {
      return answerFailure(ApiFailure.offline);
    } catch (e) {
      debugPrint('❌ Direct API error: $e');
      return answerFailure(ApiFailure.failed);
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      if (transporteRest && TransporteRestAdapter.isStopNotFound(body)) {
        return answerFailure(ApiFailure.notFound);
      }
      debugPrint('❌ Direct API ${response.statusCode}');
      if (response.statusCode == 429) {
        return answerFailure(ApiFailure.busy,
            retryAfter:
                ProxySource.retryAfterOf(response.headers['retry-after']));
      }
      return answerFailure(ApiFailure.failed);
    }

    try {
      return answerJson(jsonDecode(body));
    } catch (e) {
      debugPrint('⚠️ Direct API answer is not JSON: $e');
      return answerFailure(ApiFailure.failed);
    }
  }
}
