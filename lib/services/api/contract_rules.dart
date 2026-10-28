/// The derivation rules of the /v1 contract (docs/design/contrato-v1.md).
///
/// Mirror of `proxy/src/rules.js`: the proxy applies them to build /v1
/// answers, the app to turn the city's answers into the same JSON when it
/// has no proxy. Both sides run every vector file of
/// `proxy/contract/v1/vectors/`, so a change here goes with the same change
/// there and in the vectors.
abstract final class ContractRules {
  static const _directBase = 'https://api.montevideo.gub.uy/transporteRest';

  static final _intText = RegExp(r'^-?\d+$');

  // Past ±(2^53 − 1) JS rounds and Dart overflows: neither has the value
  static const _maxSafeInt = 9007199254740991;

  /// The widest time a JS Date holds, and a DateTime too: ±10^8 days
  static const maxDateMs = 8640000000000000;

  /// A number truncated toward zero, or a text that is an integer once
  /// trimmed ("007" → 7); anything else is null ("5.0", true, ""), and so
  /// is an integer past ±(2^53 − 1).
  /// Vectors: `int_coercion.json`.
  static int? toIntLoose(Object? value) {
    if (value is num) {
      return value >= -_maxSafeInt && value <= _maxSafeInt
          ? value.truncate()
          : null;
    }
    if (value is String) {
      final text = value.trim();
      final n = _intText.hasMatch(text) ? int.tryParse(text) : null;
      if (n != null && n >= -_maxSafeInt && n <= _maxSafeInt) return n;
    }
    return null;
  }

  // JS `\s` plus U+0085, which JS trim keeps and Dart trim removes
  static final _edgeSpace = RegExp(r'^[\s\u0085]+|[\s\u0085]+$');

  /// Whitespace removed at both ends, the same in JS and Dart.
  /// Vectors: `text_trim.json`.
  static String trimText(String text) => text.replaceAll(_edgeSpace, '');

  /// A JSON value as text, the way JS `String()` writes it; null is "".
  static String text(Object? value) => value == null ? '' : '$value';

  static final _leadingNumber = RegExp(r'^\d+');

  /// Numeric lines by value ("21" < "104"), suffixed variants next to their
  /// number ("124" < "124 SD" < "125"), then lettered lines ("CE1", "D10");
  /// ties in code-unit order, never by locale.
  /// Vectors: `line_order.json`.
  static int compareLines(String a, String b) {
    final na = int.tryParse(_leadingNumber.stringMatch(a) ?? '');
    final nb = int.tryParse(_leadingNumber.stringMatch(b) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if ((na == null) != (nb == null)) return na == null ? 1 : -1;
    return a.compareTo(b);
  }

  /// "CALLE y ESQUINA" from the two street names, either may be missing;
  /// null when both are.
  /// Vectors: `stop_name.json`.
  static String? stopName(Object? street, Object? corner) {
    final parts = [trimText(text(street)), trimText(text(corner))]
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' y ');
  }

  /// [time] the way the contract writes times: ISO 8601 in UTC with
  /// milliseconds ("2026-10-19T22:52:10.000Z"), as JS `toISOString` does.
  /// Dart's `toIso8601String` adds microseconds when there are any, and
  /// `DateTime.now()` has them on the VM.
  static String isoUtc(DateTime time) =>
      DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch,
              isUtc: true)
          .toIso8601String();

  /// [utc] on the Montevideo clock, "H:MM". Uruguay keeps UTC−3 all year.
  static String montevideoClock(DateTime utc) {
    final local = utc.toUtc().subtract(const Duration(hours: 3));
    return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  // "08:05" → "8:05", the hour without its leading zero
  static final _leadingHourZero = RegExp(r'^0(?=\d)');
  static final _nonDigits = RegExp(r'\D');

  /// A clock time as the API writes it, trimmed, without the hour's
  /// leading zero.
  static String clock(Object? value) =>
      trimText(text(value)).replaceFirst(_leadingHourZero, '');

  /// The digits of a clock time as H*100+MM ("20:01" → 2001), or null.
  static int? hhmmOf(String clockTime) =>
      int.tryParse(clockTime.replaceAll(_nonDigits, ''));

  /// One row of transporteRest `siguientesParada` as a /v1 arrival, or
  /// null when it has no line or no minutes, or its time is past what a
  /// date holds. [fetchedAt] is when the answer came. Comfort is always
  /// null here: only the proxy knows it. `location` is the GPS bus
  /// position ([_busLocation]).
  /// Vectors: `arrival.json`.
  static Map<String, Object?>? arrival(Object? row, DateTime fetchedAt) {
    if (row is! Map) return null;
    final line = text(row['linea']);
    final minutes = toIntLoose(row['minutos']);
    if (line.isEmpty || minutes == null) return null;

    final real = row['real'] == true;
    final state = real && minutes <= 0
        ? 'arriving'
        : real
            ? 'live'
            : 'scheduled';
    final eta = minutes < 0 ? 0 : minutes;

    final time = row['time'];
    // In doubles, as JS computes it: eta * 60000 can pass the int range
    final num expectedMs = time is num
        ? time
        : ((fetchedAt.millisecondsSinceEpoch + eta * 60000.0) / 60000)
                .floorToDouble() * 60000;
    // DateTime would throw: one bad row, not a failure for the whole stop
    if (!(expectedMs.abs() <= maxDateMs)) return null;
    final expectedAt =
        DateTime.fromMillisecondsSinceEpoch(expectedMs.toInt(), isUtc: true);

    var clockTime = clock(row['horaDesc']);
    if (clockTime.isEmpty) clockTime = montevideoClock(expectedAt);

    final company = row['idEmpresa'], bus = row['idBus'];
    final tripId = real && company != null && bus != null
        ? 'bus-$company-$bus'
        : 'sched-${row['variante'] ?? 0}-${row['hora'] ?? hhmmOf(clockTime)}';

    return {
      'tripId': tripId,
      'variantId': toIntLoose(row['variante']),
      'line': line,
      'destination': text(row['destino']),
      'state': state,
      'etaMinutes': eta,
      'expectedAt': expectedAt.toIso8601String(),
      'clockTime': clockTime,
      'accessible': row['accesibilidad'] == true,
      'airConditioning': null,
      'zeroEmission': null,
      // Only a GPS row has a bus position
      'location': real ? _busLocation(row['coordinates']) : null,
    };
  }

  /// transporteRest `coordinates` ([lng, lat]) as `{lat, lng}`, the
  /// decoded numbers unchanged (no rounding, no toDouble). Null unless the
  /// first two items are finite JSON numbers, not both 0, with |lat| <= 90
  /// and |lng| <= 180. No Montevideo box: the map drops what is off its
  /// basemap.
  /// Vectors: `arrival.json`.
  static Map<String, Object?>? _busLocation(Object? coordinates) {
    if (coordinates is! List || coordinates.length < 2) return null;
    final lng = coordinates[0], lat = coordinates[1];
    if (lat is! num || lng is! num || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    if (lat == 0 && lng == 0) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return {'lat': lat, 'lng': lng};
  }

  static final _webLink =
      RegExp(r'^(https?)://([^/?#]+)(.*)$', caseSensitive: false);

  /// A news link: http(s) only, scheme and host in lower case, the rest as
  /// written; anything else ("", "null", ftp:, mailto:) is null.
  /// Vectors: `news_link.json`.
  static String? newsLink(Object? value) {
    if (value is! String) return null;
    final m = _webLink.firstMatch(trimText(value));
    if (m == null) return null;
    return '${m[1]!.toLowerCase()}://${m[2]!.toLowerCase()}${m[3]}';
  }

  /// Below this share of buses with GPS an operator is "partial".
  static const gpsPartialBelow = 70;

  /// One item of pci `buses/control` as a /v1 operator, or null when it
  /// has no company or no numeric value. The percent is clamped to 0–100.
  /// Vectors: `gps_status.json`.
  static Map<String, Object?>? gpsOperator(Object? item) {
    if (item is! Map) return null;
    final company = trimText(text(item['empresa']));
    final value = item['valor'];
    if (company.isEmpty || value is! num || !value.isFinite) return null;
    final percent = value.round().clamp(0, 100);
    return {
      'company': company,
      'percent': percent,
      'partial': percent < gpsPartialBelow,
    };
  }

  /// Stop numbers the proxy routes accept; anything else is not requested.
  /// Vectors: `stop_id.json`.
  static bool isValidStopId(int id) => id >= 1 && id <= 9999999;

  /// The timetable request, as a proxy path and as the transporteRest URL
  /// of the direct mode. [day] is `weekday`, `saturday` or `sunday`.
  /// Vectors: `schedule_path.json`.
  static ({String proxyPath, String directUrl}) schedulePath(
      int stopId, String day, int hour, int minute) {
    final time = '$hour:${minute.toString().padLeft(2, '0')}';
    return (
      proxyPath: '/v1/stops/$stopId/schedule/$day/$time',
      directUrl:
          '$_directBase/siguientesParada/$stopId/${_directDays[day]}/$time',
    );
  }

  static const _directDays = {
    'weekday': 'HABIL',
    'saturday': 'SABADO',
    'sunday': 'DOMINGO',
  };
}
