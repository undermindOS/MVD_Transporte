/// A stop of the proxy's catalog (`/v1/catalog/stops`), found by street
/// names or around the user. Not persisted as a saved stop.
class CatalogStop {
  /// Stop code — the same number transporteRest and Cómo Ir use.
  final int id;

  /// "CALLE y ESQUINA", the format transporteRest/lineas uses too;
  /// "Parada N" when the source has no street names.
  final String name;

  /// [name] in lower case without accents or punctuation, for the search;
  /// empty for a stop without street names, so no search finds it.
  final String searchKey;

  /// Lines of the stop as geoserver names them ("124 SD", "M-A"), in
  /// natural order; empty when the catalog came without lines.
  final List<String> lines;

  final double latitude;
  final double longitude;

  const CatalogStop({
    required this.id,
    required this.name,
    required this.searchKey,
    required this.lines,
    required this.latitude,
    required this.longitude,
  });

  /// From a catalog item: [name] null or blank gives "Parada N" and no
  /// search key.
  factory CatalogStop.fromSource({
    required int id,
    required String? name,
    required List<String> lines,
    required double latitude,
    required double longitude,
  }) {
    final trimmed = name?.trim() ?? '';
    return CatalogStop(
      id: id,
      name: trimmed.isEmpty ? 'Parada $id' : trimmed,
      searchKey: trimmed.isEmpty ? '' : fold(trimmed),
      lines: lines,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static const _plainLetters = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ñ': 'n', 'ç': 'c',
    // The catalog writes ORDOÑEZ as "ORDOÐEZ" (stops 5340–5346)
    'ð': 'n',
  };
  static final _accented = RegExp('[${_plainLetters.keys.join()}]');
  static final _combiningMarks = RegExp('[̀-ͯ]');
  // "O´HIGGINS" = "ohiggins", whichever apostrophe the user types
  static final _apostrophes = RegExp('[´\'’‘`]');
  static final _separators = RegExp('[^a-z0-9]+');

  /// Lower case, no accents, apostrophes dropped, any other punctuation
  /// ("Nº", "S/N", parentheses) turned into single spaces.
  static String fold(String text) => text
      .toLowerCase()
      .replaceAll(_combiningMarks, '')
      .replaceAllMapped(_accented, (m) => _plainLetters[m[0]]!)
      .replaceAll(_apostrophes, '')
      .replaceAll(_separators, ' ')
      .trim();
}
