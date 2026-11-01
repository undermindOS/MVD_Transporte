import '../contract_rules.dart';

/// The open WFS layer `imm:v_uptu_paradas` of the Intendencia de Montevideo
/// GeoServer (no credentials) turned into /v1 catalog items, for the nearby
/// stops of the direct mode.
abstract final class WfsAdapter {
  /// GetFeature GeoJSON as /v1 catalog items, in the order first seen:
  /// `{"features":[{"geometry":{"type":"Point","coordinates":[lon,lat]},
  ///   "properties":{"cod_ubic_parada":574,"desc_linea":"116",
  ///   "calle":"SAN JOSE","esquina":"ANDES"}}, ...]}`
  /// Each feature is one "stop × line variant": they are grouped by
  /// `cod_ubic_parada`, the stop number transporteRest and Cómo Ir use.
  /// Null when the answer is not a feature collection.
  static List<Map<String, Object?>>? featuresToCatalogItems(Object? raw) {
    if (raw is! Map || raw['features'] is! List) return null;

    final byId = <int, ({Map<String, Object?> item, Set<String> lines})>{};
    for (final feature in raw['features'] as List) {
      if (feature is! Map) continue;
      final props = feature['properties'];
      final geometry = feature['geometry'];
      if (props is! Map || geometry is! Map) continue;

      final id = props['cod_ubic_parada'];
      final coords = geometry['coordinates'];
      if (id is! num || coords is! List || coords.length < 2) continue;
      final lng = coords[0], lat = coords[1];
      if (lng is! num || lat is! num) continue;

      final stop = byId.putIfAbsent(
        id.toInt(),
        () => (
          item: {
            'id': id.toInt(),
            'name': ContractRules.stopName(props['calle'], props['esquina']),
            'location': {'lat': lat, 'lng': lng},
          },
          lines: <String>{},
        ),
      );
      final line =
          ContractRules.trimText(ContractRules.text(props['desc_linea']));
      if (line.isNotEmpty) stop.lines.add(line);
    }

    return [
      for (final s in byId.values)
        {
          ...s.item,
          'lines': s.lines.toList()..sort(ContractRules.compareLines),
        },
    ];
  }
}
