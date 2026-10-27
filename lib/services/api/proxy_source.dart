import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/scheduled_pass.dart';
import 'api_result.dart';
import 'contract_rules.dart';
import 'v1_source.dart';

/// The project's proxy (`proxy/`, routes `/v1`): it holds the secret of the
/// official IM API and answers in the /v1 shapes directly.
class ProxySource implements V1Source {
  /// [baseUrl] from `--dart-define=MVD_PROXY_URL=…`; a trailing `/` is
  /// dropped, so `https://proxy.example/` works too.
  ProxySource(String baseUrl) : baseUrl = baseUrl.replaceFirst(_trailing, '');

  static final _trailing = RegExp(r'/+$');

  final String baseUrl;

  static const _timeout = Duration(seconds: 10);
  static const _catalogTimeout = Duration(seconds: 30);
  static const _newsTimeout = Duration(seconds: 20);
  static const _headers = {'Accept': 'application/json'};

  /// Without a `Retry-After` header.
  static const defaultRetryAfter = Duration(seconds: 60);

  @override
  Future<SourceAnswer> stop(int id) => _get('/v1/stops/$id', _timeout);

  @override
  Future<SourceAnswer> arrivals(int id) =>
      _get('/v1/stops/$id/arrivals', _timeout);

  @override
  Future<SourceAnswer> schedule(int id, DayType day, int hour, int minute) =>
      _get(ContractRules.schedulePath(id, day.proxyValue, hour, minute)
          .proxyPath, _timeout);

  @override
  Future<SourceAnswer> catalogStops() =>
      _get('/v1/catalog/stops', _catalogTimeout);

  @override
  Future<SourceAnswer> news() => _get('/v1/news', _newsTimeout);

  @override
  Future<SourceAnswer> gpsStatus() => _get('/v1/status/gps', _timeout);

  Future<SourceAnswer> _get(String path, Duration timeout) async {
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(timeout);
    } on TimeoutException {
      return answerFailure(ApiFailure.timeout);
    } on SocketException {
      return answerFailure(ApiFailure.offline);
    } on http.ClientException {
      return answerFailure(ApiFailure.offline);
    } catch (e) {
      debugPrint('❌ Proxy error: $e');
      return answerFailure(ApiFailure.failed);
    }

    final status = response.statusCode;
    if (status == 200) {
      try {
        return answerJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (e) {
        debugPrint('⚠️ Proxy answer is not JSON: $e');
        return answerFailure(ApiFailure.failed);
      }
    }
    final failure = failureOf(status, _errorCode(response));
    return answerFailure(
      failure,
      retryAfter: failure == ApiFailure.busy
          ? retryAfterOf(response.headers['retry-after'])
          : null,
    );
  }

  /// docs/design/contrato-v1.md, "Errores": the proxy's status and
  /// `{"error":"<code>"}` as an [ApiFailure].
  @visibleForTesting
  static ApiFailure failureOf(int status, String? code) {
    switch (status) {
      case 404 when code == 'stop_not_found':
        return ApiFailure.notFound;
      case 429:
        return ApiFailure.busy;
      case 503 when code == 'upstream_busy':
        return ApiFailure.busy;
      case 503 when code == 'not_configured':
        return ApiFailure.unavailable;
      case 504:
        return ApiFailure.timeout;
      case 400 || 404:
        // The app built a request the proxy does not know: a bug
        debugPrint('❌ Proxy $status $code');
        return ApiFailure.failed;
      default:
        return ApiFailure.failed;
    }
  }

  /// `Retry-After` in seconds; [defaultRetryAfter] when missing or not a
  /// number of seconds.
  static Duration retryAfterOf(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    return seconds == null || seconds < 0
        ? defaultRetryAfter
        : Duration(seconds: seconds);
  }

  static String? _errorCode(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final code = body is Map ? body['error'] : null;
      return code is String ? code : null;
    } catch (_) {
      return null;
    }
  }
}
