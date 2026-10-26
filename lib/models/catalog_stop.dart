/// A stop of the proxy's catalog (`/v1/catalog/stops`), found by street
/// names. Not persisted as a saved stop: saving goes through
/// MvdApiService.resolveStop → CacheService.saveStop like a typed number.
class CatalogStop {
  /// Stop code — the same number transporteRest and Cómo Ir use.
  final int id;

  /// "CALLE y ESQUINA", the format transporteRest/lineas uses too.
  final String name;

  /// [name] in lower case without accents or punctuation, for the search.
  final String searchKey;

  const CatalogStop({
    required this.id,
    required this.name,
    required this.searchKey,
  });
}
