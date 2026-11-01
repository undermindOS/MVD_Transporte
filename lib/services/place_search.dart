import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'rutas/itinerary.dart' show GeoPoint;

/// What a search result is: a door number, a corner, a street (still
/// without a number), a landmark the city lists, or a place from
/// OpenStreetMap (a shop, a school, a café).
enum PlaceHitKind { address, corner, street, landmark, poi }

/// One suggestion of [PlaceSearch]. Places from OpenStreetMap come with
/// their point; the city's are looked up only when picked ([locate]).
class PlaceHit {
  const PlaceHit({
    required this.title,
    required this.subtitle,
    required this.kind,
    this.point,
    this.resolve,
  });

  final String title;
  final String subtitle;
  final PlaceHitKind kind;
  final GeoPoint? point;
  final Future<GeoPoint?> Function()? resolve;

  /// Where it is; null when the city no longer finds it.
  Future<GeoPoint?> locate() async => point ?? await resolve?.call();
}

/// Search by address or name, like a map app's search box, from two
/// sources at once:
///
/// - the IM's own address service (`ubicacionesRest`, the one Cómo Ir
///   uses, keyless): door numbers ("18 de Julio 1453"), corners ("18 de
///   Julio y Ejido") and the landmarks it lists;
/// - OpenStreetMap through Photon, made for search as you type: shops,
///   schools, cafés. Nominatim, which forbids that, answers only a search
///   sent with the keyboard ([search]), at most once a second.
///
/// Only the typed text leaves the phone, never its position: the results
/// are limited to Montevideo and around by a fixed box.
abstract final class PlaceSearch {
  static const imBase = 'https://api.montevideo.gub.uy/ubicacionesRest/';
  static const _photon = 'https://photon.komoot.io/api/';
  static const _nominatim = 'https://nominatim.openstreetmap.org/search';
  // Montevideo and the metropolitan area: west, south, east, north
  static const _box = (
    west: -56.45,
    south: -34.95,
    east: -55.95,
    north: -34.70,
  );
  static const _headers = {
    'User-Agent': 'TimbreMVD/1.0 (github.com/undermindOS/MVD_Transporte)',
  };
  static const _timeout = Duration(seconds: 10);

  /// Nominatim's limit: one request a second.
  static DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Suggestions for [text] while typing: the city's first, then
  /// OpenStreetMap's. Empty below 3 letters. A source that fails is left
  /// out; [PlaceSearchException] only when both fail.
  static Future<List<PlaceHit>> suggest(String text) async {
    final query = text.trim();
    if (query.length < 3) return const [];
    final results = await Future.wait([
      _city(query).then<List<PlaceHit>?>((r) => r).catchError((_) => null),
      _photonSearch(
        query,
      ).then<List<PlaceHit>?>((r) => r).catchError((_) => null),
    ]);
    final (city, osm) = (results[0], results[1]);
    if (city == null && osm == null) throw const PlaceSearchException();
    return _merge(city ?? const [], osm ?? const []);
  }

  /// [suggest], plus Nominatim: what the keyboard's search key asks.
  static Future<List<PlaceHit>> search(String text) async {
    final query = text.trim();
    final hits = await suggest(query).catchError((_) => <PlaceHit>[]);
    List<PlaceHit> extra = const [];
    final now = clock();
    if (query.length >= 3 &&
        now.difference(_lastNominatim) >= const Duration(seconds: 1)) {
      _lastNominatim = now;
      extra = await _nominatimSearch(query).catchError((_) => <PlaceHit>[]);
    }
    if (hits.isEmpty && extra.isEmpty && query.length >= 3) {
      // Both failed or found nothing: say which
      try {
        await _city(query);
      } catch (_) {
        throw const PlaceSearchException();
      }
    }
    return _merge(hits, extra);
  }

  // ------------------------------------------------------------- city ---

  /// "18 de julio 1453": a street and a door number; "18 de julio y
  /// ejido": a corner; anything else: streets and landmarks.
  static Future<List<PlaceHit>> _city(String query) async {
    final corner = RegExp(
      r'^(.+?)\s+(?:y|esq\.?|esquina)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(query);
    if (corner != null) {
      return _corners(corner.group(1)!.trim(), corner.group(2)!.trim());
    }
    final numbered = RegExp(r'^(.+?)\s+(\d{1,5})$').firstMatch(query);
    if (numbered != null) {
      final number = int.parse(numbered.group(2)!);
      final streets = (await _streets(numbered.group(1)!)).take(3).toList();
      // Looked up now: a street without that number is left out
      final points = await Future.wait([
        for (final s in streets)
          _point(
            'direcciones/posicion/${s.code}/$number',
          ).then<GeoPoint?>((p) => p).catchError((_) => null),
      ]);
      return [
        for (final (i, s) in streets.indexed)
          if (points[i] case final point?)
            PlaceHit(
              title: '${_title(s.name)} $number',
              subtitle: 'Dirección · Montevideo',
              kind: PlaceHitKind.address,
              point: point,
            ),
      ];
    }
    final places = await _places(query);
    return [
      for (final p in places.take(8))
        if (p.type == 'VIA')
          PlaceHit(
            title: _title(p.name),
            subtitle: 'Calle · agregá el número o la esquina',
            kind: PlaceHitKind.street,
            resolve: () => _point('vias/punto/${p.code}'),
          )
        else if (_landmarkPaths[p.subtype] case final path?)
          PlaceHit(
            title: _title(p.name),
            subtitle: '${_title(p.subtype ?? 'Lugar')} · Montevideo',
            kind: PlaceHitKind.landmark,
            resolve: () => _point('$path${p.code}'),
          ),
    ];
  }

  static Future<List<PlaceHit>> _corners(String first, String second) async {
    final streets = (await _streets(first)).take(3).toList();
    final hits = <PlaceHit>[];
    for (final s in streets) {
      final list = await _getJson(
        Uri.parse(
          '${imBase}infoUbicacion/esquinas/${s.code}',
        ).replace(queryParameters: {'nombre': second}),
      );
      if (list is! List) continue;
      for (final c in list.take(4)) {
        if (c is! Map || c['codigo'] is! int || c['nombre'] is! String) {
          continue;
        }
        hits.add(
          PlaceHit(
            title: '${_title(s.name)} y ${_title(c['nombre'] as String)}',
            subtitle: 'Esquina · Montevideo',
            kind: PlaceHitKind.corner,
            resolve: () => _point('esquinas/posicion/${s.code}/${c['codigo']}'),
          ),
        );
      }
    }
    return hits;
  }

  /// The city's streets for [name]: as typed, or else by its longest word,
  /// keeping the streets that have every typed word ("bulevar artigas"
  /// finds "BV GRAL ARTIGAS").
  static Future<List<({String type, String? subtype, String name, int code})>>
  _streets(String name) async {
    final typed = (await _places(name)).where((p) => p.type == 'VIA').toList();
    if (typed.isNotEmpty) return typed;
    final words = normalize(name).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return const [];
    final longest = words.reduce((a, b) => b.length > a.length ? b : a);
    return [
      for (final p in await _places(longest))
        if (p.type == 'VIA' &&
            words.every(
              (w) => normalize(p.name).split(' ').any((n) => n.startsWith(w)),
            ))
          p,
    ];
  }

  /// Lower case, no accents, and the abbreviations the city writes
  /// ("Avenida General" → "av gral").
  @visibleForTesting
  static String normalize(String s) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    const short = {
      'avenida': 'av',
      'av.': 'av',
      'bulevar': 'bv',
      'boulevard': 'bv',
      'bv.': 'bv',
      'general': 'gral',
      'gral.': 'gral',
      'doctor': 'dr',
      'dr.': 'dr',
      'ingeniero': 'ing',
      'ing.': 'ing',
      'presidente': 'pres',
      'pasaje': 'psje',
      'camino': 'cno',
      'coronel': 'cnel',
    };
    final plain = s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    return plain
        .split(RegExp(r'\s+'))
        .map((w) => short[w] ?? w)
        .join(' ')
        .trim();
  }

  // Where each kind of landmark the city lists is looked up
  static const _landmarkPaths = {
    'PATRIMONIO': 'patrimonio/',
    'MONUMENTO': 'monumentos/',
    'SALUD': 'salud/',
    'CULTURA': 'cultura/',
    'EDUCACION': 'educacion/',
    'DEPORTE': 'deporte/',
    'PARQUE': 'nombresDeParque/',
    'PLAYA': 'playas/',
    'ESPACIO LIBRE': 'nombresDeEspacioLibre/',
  };

  static Future<List<({String type, String? subtype, String name, int code})>>
  _places(String name) async {
    final list = await _getJson(
      Uri.parse(
        '${imBase}infoUbicacion/lugaresDeInteresYVias/',
      ).replace(queryParameters: {'nombre': name}),
    );
    if (list is! List) return const [];
    return [
      for (final p in list)
        if (p is Map &&
            p['descTipo'] is String &&
            p['nombre'] is String &&
            p['codigo'] is int)
          (
            type: p['descTipo'] as String,
            subtype: p['descSubtipo'] as String?,
            name: p['nombre'] as String,
            code: p['codigo'] as int,
          ),
    ];
  }

  /// The point of an `ubicacionesRest` answer: `geoJSON`, `punto` or the
  /// middle of its `geometria` (parks and beaches have only an outline).
  static Future<GeoPoint?> _point(String path) async =>
      pointOf(await _getJson(Uri.parse('$imBase$path')));

  @visibleForTesting
  static GeoPoint? pointOf(Object? json) {
    if (json is! Map) return null;
    final geo = json['geoJSON'] ?? (json['punto'] as Map?)?['geoJSON'];
    if (geo is Map && geo['type'] == 'Point') {
      final c = geo['coordinates'];
      if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
        return utm21sToWgs84(
          (c[0] as num).toDouble(),
          (c[1] as num).toDouble(),
        );
      }
    }
    final shape = (json['geometria'] as Map?)?['geoJSON'];
    if (shape is Map) {
      final xs = <double>[], ys = <double>[];
      void walk(Object? node) {
        if (node is List &&
            node.length >= 2 &&
            node[0] is num &&
            node[1] is num) {
          xs.add((node[0] as num).toDouble());
          ys.add((node[1] as num).toDouble());
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      walk(shape['coordinates']);
      if (xs.isNotEmpty) {
        final x = xs.reduce(math.min) / 2 + xs.reduce(math.max) / 2;
        final y = ys.reduce(math.min) / 2 + ys.reduce(math.max) / 2;
        return utm21sToWgs84(x, y);
      }
    }
    return null;
  }

  // ------------------------------------------------------ OpenStreetMap ---

  static Future<List<PlaceHit>> _photonSearch(String query) async {
    final json = await _getJson(
      Uri.parse(_photon).replace(
        queryParameters: {
          'q': query,
          'limit': '8',
          'bbox': '${_box.west},${_box.south},${_box.east},${_box.north}',
        },
      ),
    );
    final features = json is Map ? json['features'] : null;
    if (features is! List) return const [];
    return [for (final f in features) ?_photonHit(f)];
  }

  static PlaceHit? _photonHit(Object? f) {
    if (f is! Map) return null;
    final p = f['properties'], g = f['geometry'];
    if (p is! Map || g is! Map) return null;
    final c = g['coordinates'];
    if (c is! List || c.length < 2 || c[0] is! num || c[1] is! num) {
      return null;
    }
    final street = [
      p['street'],
      p['housenumber'],
    ].whereType<String>().join(' ');
    final name = p['name'] as String? ?? (street.isEmpty ? null : street);
    if (name == null) return null;
    // Streets are the city's: its door numbers are better
    if (p['osm_key'] == 'highway') return null;
    final area = p['district'] ?? p['locality'] ?? p['city'];
    return PlaceHit(
      title: name,
      subtitle: [
        if (street.isNotEmpty && street != name) street,
        ?area as String?,
      ].join(' · '),
      kind: PlaceHitKind.poi,
      point: (lat: (c[1] as num).toDouble(), lon: (c[0] as num).toDouble()),
    );
  }

  static Future<List<PlaceHit>> _nominatimSearch(String query) async {
    final json = await _getJson(
      Uri.parse(_nominatim).replace(
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'limit': '5',
          'bounded': '1',
          'viewbox': '${_box.west},${_box.north},${_box.east},${_box.south}',
        },
      ),
    );
    if (json is! List) return const [];
    return [
      for (final r in json)
        if (r is Map &&
            r['display_name'] is String &&
            double.tryParse('${r['lat']}') != null &&
            double.tryParse('${r['lon']}') != null)
          PlaceHit(
            title: (r['name'] as String?)?.isNotEmpty == true
                ? r['name'] as String
                : (r['display_name'] as String).split(',').first,
            subtitle: (r['display_name'] as String)
                .split(',')
                .skip(1)
                .take(2)
                .map((s) => s.trim())
                .join(' · '),
            kind: PlaceHitKind.poi,
            point: (
              lat: double.parse('${r['lat']}'),
              lon: double.parse('${r['lon']}'),
            ),
          ),
    ];
  }

  // ------------------------------------------------------------ shared ---

  /// The city's first; then OpenStreetMap's, minus the names already
  /// there.
  static List<PlaceHit> _merge(List<PlaceHit> first, List<PlaceHit> second) {
    final seen = {for (final h in first) h.title.toLowerCase()};
    return [
      ...first,
      for (final h in second)
        if (seen.add(h.title.toLowerCase())) h,
    ];
  }

  static Future<Object?> _getJson(Uri uri) async {
    final response = await http.get(uri, headers: _headers).timeout(_timeout);
    if (response.statusCode == 204 || response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw PlaceSearchException(response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// "AV 18 DE JULIO" → "Av 18 De Julio" reads better than all caps,
  /// but the city's names keep their own words: only the case changes.
  static String _title(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ')
      .replaceAll(' De ', ' de ')
      .replaceAll(' Del ', ' del ')
      .replaceAll(' Y ', ' y ')
      .replaceAll(' E ', ' e ')
      .replaceAll(' En ', ' en ')
      .replaceAll(' La ', ' la ')
      .replaceAll(' Los ', ' los ')
      .replaceAll(' Las ', ' las ');
}

class PlaceSearchException implements Exception {
  const PlaceSearchException([this.status]);
  final int? status;
}

/// EPSG:32721 (UTM zone 21 south, WGS84), what the IM's services answer in,
/// to latitude and longitude. Snyder's inverse transverse Mercator: well
/// under a metre across Montevideo.
GeoPoint utm21sToWgs84(double x, double y) {
  const a = 6378137.0;
  const f = 1 / 298.257223563;
  const k0 = 0.9996;
  const e2 = f * (2 - f);
  final ep2 = e2 / (1 - e2);
  final lon0 = (21 - 1) * 6 - 180 + 3; // -57°
  final m = (y - 10000000) / k0;
  final mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
  final e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2));
  final phi1 =
      mu +
      (3 * e1 / 2 - 27 * math.pow(e1, 3) / 32) * math.sin(2 * mu) +
      (21 * e1 * e1 / 16 - 55 * math.pow(e1, 4) / 32) * math.sin(4 * mu) +
      (151 * math.pow(e1, 3) / 96) * math.sin(6 * mu) +
      (1097 * math.pow(e1, 4) / 512) * math.sin(8 * mu);
  final sin1 = math.sin(phi1), cos1 = math.cos(phi1), tan1 = math.tan(phi1);
  final n1 = a / math.sqrt(1 - e2 * sin1 * sin1);
  final t1 = tan1 * tan1;
  final c1 = ep2 * cos1 * cos1;
  final r1 = a * (1 - e2) / math.pow(1 - e2 * sin1 * sin1, 1.5);
  final d = (x - 500000) / (n1 * k0);
  final lat =
      phi1 -
      (n1 * tan1 / r1) *
          (d * d / 2 -
              (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) *
                  math.pow(d, 4) /
                  24 +
              (61 +
                      90 * t1 +
                      298 * c1 +
                      45 * t1 * t1 -
                      252 * ep2 -
                      3 * c1 * c1) *
                  math.pow(d, 6) /
                  720);
  final lon =
      (d -
          (1 + 2 * t1 + c1) * math.pow(d, 3) / 6 +
          (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) *
              math.pow(d, 5) /
              120) /
      cos1;
  return (lat: lat * 180 / math.pi, lon: lon0 + lon * 180 / math.pi);
}
