import '../../models/scheduled_pass.dart';
import 'api_result.dart';

/// What a source answered: /v1 JSON, or why there is none. [retryAfter]
/// comes with [ApiFailure.busy].
typedef SourceAnswer = ({
  Object? json,
  ApiFailure? failure,
  Duration? retryAfter,
});

/// Where /v1 JSON comes from: the project's proxy (`ProxySource`), or the
/// city's servers turned into the same JSON on the phone (`DirectSource`).
/// `V1Parser` reads the answer either way.
abstract interface class V1Source {
  /// `GET /v1/stops/{id}`.
  Future<SourceAnswer> stop(int id);

  /// `GET /v1/stops/{id}/arrivals`.
  Future<SourceAnswer> arrivals(int id);

  /// `GET /v1/stops/{id}/schedule/{day}/{H:MM}`.
  Future<SourceAnswer> schedule(int id, DayType day, int hour, int minute);

  /// `GET /v1/catalog/stops`.
  Future<SourceAnswer> catalogStops();

  /// `GET /v1/news`.
  Future<SourceAnswer> news();

  /// `GET /v1/status/gps`.
  Future<SourceAnswer> gpsStatus();
}

/// The answer of a source that worked.
SourceAnswer answerJson(Object? json) =>
    (json: json, failure: null, retryAfter: null);

/// The answer of a source that failed.
SourceAnswer answerFailure(ApiFailure failure, {Duration? retryAfter}) =>
    (json: null, failure: failure, retryAfter: retryAfter);
