import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'rutas/itinerary.dart';
import 'rutas/transit_data.dart';
import 'rutas/trip_planner.dart';

/// What the Mapa asks the planner: from where, to where, when, and how far
/// the person walks at each end.
typedef TripQuery = ({
  GeoPoint from,
  GeoPoint to,
  DateTime departAt,
  int maxWalkMinutes,
});

/// The trips the planner found, the date of the timetable it used, and
/// whether A or B has no stop within the walking limit (then no bus can
/// help, whatever the hour).
typedef TripAnswer = ({
  List<Itinerary> options,
  DateTime sourceDate,
  bool noStopNearFrom,
  bool noStopNearTo,
});

/// Plans trips on the phone, from the IM timetable bundled in the app
/// (assets/rutas/horarios.bin): nothing about the trip leaves the phone.
///
/// The timetable is decoded once, in a worker isolate that stays for the
/// app's life and answers each [plan]; the UI never waits on it.
abstract final class TripService {
  static const asset = 'assets/rutas/horarios.bin';

  /// Tests answer here, with no isolate (worker isolates never answer
  /// inside fake async).
  @visibleForTesting
  static Future<TripAnswer> Function(TripQuery query) planner = _inWorker;

  static Future<TripAnswer> plan(TripQuery query) => planner(query);

  static Future<_Worker>? _worker;

  static Future<TripAnswer> _inWorker(TripQuery query) async {
    final worker = _worker ??= _Worker.start();
    try {
      return await (await worker).plan(query);
    } catch (_) {
      // A worker that failed to start is tried again next time
      _worker = null;
      rethrow;
    }
  }
}

class _Worker {
  _Worker._(this._requests, this._replies);

  final SendPort _requests;
  final Stream<Object?> _replies;
  var _next = 0;

  static Future<_Worker> start() async {
    final bytes = await rootBundle.load(TripService.asset);
    final replies = ReceivePort();
    await Isolate.spawn(_main, (
      replies.sendPort,
      TransferableTypedData.fromList([
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ]),
    ), errorsAreFatal: false);
    final stream = replies.asBroadcastStream();
    final first = await stream.first;
    if (first is! SendPort) throw StateError('$first');
    return _Worker._(first, stream);
  }

  Future<TripAnswer> plan(TripQuery query) async {
    final id = _next++;
    final reply = _replies.firstWhere((r) => r is (int, Object?) && r.$1 == id);
    _requests.send((id, query));
    final (_, answer) = await reply as (int, Object?);
    if (answer is TripAnswer) return answer;
    throw StateError('$answer');
  }

  static void _main((SendPort, TransferableTypedData) args) {
    final (replies, bytes) = args;
    final data = TransitData.decode(bytes.materialize().asUint8List());
    final planner = TripPlanner(data);
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    requests.listen((message) {
      final (id, query) = message as (int, TripQuery);
      Object? answer;
      try {
        List<Itinerary> plan(int maxTransfers) => planner.plan(
          from: query.from,
          to: query.to,
          departAt: query.departAt,
          maxWalkMinutes: query.maxWalkMinutes,
          maxTransfers: maxTransfers,
        );
        // One change of bus at most, unless there is no trip like that: a
        // third bus to walk a little less is noise
        var options = plan(1);
        if (options.every((o) => o.walkOnly)) options = plan(2);
        final reach = query.maxWalkMinutes * TransitData.walkMetresPerMinute;
        bool far(GeoPoint p) => data.stopsNear(p.lat, p.lon, reach).isEmpty;
        answer = (
          options: options,
          sourceDate: data.sourceDate,
          noStopNearFrom: far(query.from),
          noStopNearTo: far(query.to),
        );
      } catch (e) {
        answer = '${e.runtimeType}';
      }
      replies.send((id, answer));
    });
  }
}
