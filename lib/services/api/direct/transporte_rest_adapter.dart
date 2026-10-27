import '../contract_rules.dart';

/// transporteRest — the open backend of the official Cómo Ir web app
/// (https://m.montevideo.gub.uy/comoir/), no credentials — turned into /v1
/// JSON for the direct mode. The same mapping as `proxy/src/transporte_rest.js`.
abstract final class TransporteRestAdapter {
  static const baseUrl = 'https://api.montevideo.gub.uy/transporteRest';

  static String stopUrl(int id) => '$baseUrl/lineas/$id';

  static String arrivalsUrl(int id) => '$baseUrl/siguientesParada/$id';

  /// transporteRest answers an unknown stop with 500 "No existe la
  /// ubicación de parada con código 'N'.".
  static bool isStopNotFound(String body) =>
      body.trimLeft().startsWith('No existe');

  /// `GET /lineas/{id}` as a /v1 stop:
  /// `{"descripcion":"SAN JOSE y ANDES",
  ///   "lineas":[{"descripcion":"116","codigo":38}, ...]}`
  /// Lines deduplicated, in natural order. No directions: only the proxy
  /// knows them. Null when the answer is not an object.
  static Map<String, Object?>? stopToV1(Object? raw, int id) {
    if (raw is! Map) return null;
    final lines = <String>{
      for (final l in raw['lineas'] is List ? raw['lineas'] as List : const [])
        if (l is Map && ContractRules.text(l['descripcion']).isNotEmpty)
          ContractRules.text(l['descripcion']),
    }.toList()
      ..sort(ContractRules.compareLines);
    final name = ContractRules.trimText(ContractRules.text(raw['descripcion']));
    return {
      'id': id,
      'name': name.isEmpty ? null : name,
      'lines': lines,
      'directions': const <Object?>[],
    };
  }

  /// `GET /siguientesParada/{id}` as /v1 arrivals, soonest first:
  /// `[{"linea":"145","minutos":5,"real":true,"destino":"PLAZA ESPAÑA",
  ///    "idEmpresa":50,"idBus":247,"variante":8403,"hora":739,
  ///    "horaDesc":"7:39","time":1792233540000,"accesibilidad":true, ...}]`
  /// [fetchedAt] is when the answer came. Null when it is not a list.
  static Map<String, Object?>? arrivalsToV1(Object? raw, int id,
      {required DateTime fetchedAt}) {
    if (raw is! List) return null;
    final rows = <(Map<String, Object?>, int)>[];
    for (var i = 0; i < raw.length; i++) {
      final arrival = ContractRules.arrival(raw[i], fetchedAt);
      if (arrival != null) rows.add((arrival, i));
    }
    // Stable: same minutes keep the API order
    rows.sort((a, b) {
      final byEta =
          (a.$1['etaMinutes'] as int).compareTo(b.$1['etaMinutes'] as int);
      return byEta != 0 ? byEta : a.$2.compareTo(b.$2);
    });
    return {
      'id': id,
      'fetchedAt': fetchedAt.toUtc().toIso8601String(),
      'arrivals': [for (final r in rows) r.$1],
    };
  }

  /// `GET /siguientesParada/{id}/{HABIL|SABADO|DOMINGO}/{H:MM}` as a /v1
  /// timetable — the same items as arrivals, with `minutos: null`:
  /// `[{"linea":"145","destino":"PLAZA ESPAÑA","hora":803,"horaDesc":"8:03"}]`
  /// Keeps the API order (chronological, wrapping past midnight). Null when
  /// the answer is not a list.
  static Map<String, Object?>? scheduleToV1(Object? raw) {
    if (raw is! List) return null;
    final passes = <Map<String, Object?>>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final line = ContractRules.text(row['linea']);
      final hora = ContractRules.toIntLoose(row['hora']);
      var time = ContractRules.clock(row['horaDesc']);
      if (time.isEmpty && hora != null) {
        time = '${hora ~/ 100}:${(hora % 100).toString().padLeft(2, '0')}';
      }
      final hhmm = hora ?? ContractRules.hhmmOf(time);
      if (line.isEmpty || time.isEmpty || hhmm == null) continue;
      passes.add({
        'line': line,
        'destination': ContractRules.text(row['destino']),
        'time': time,
        'hhmm': hhmm,
      });
    }
    return {'passes': passes};
  }
}
