/// A bus stop found around the user. Not persisted: picking it saves its
/// name and lines with CacheService.saveStop at once, with no lookup.
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
