/// A bus stop found around the user. Not persisted: saving goes through
/// MvdApiService.resolveStop → CacheService.saveStop like a typed number.
class NearbyStop {
  /// Stop code (`cod_ubic_parada`) — the same number transporteRest uses.
  final int id;

  /// "CALLE y ESQUINA", the format transporteRest/lineas uses too.
  final String name;
  final List<String> lines;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  const NearbyStop({
    required this.id,
    required this.name,
    required this.lines,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });
}
