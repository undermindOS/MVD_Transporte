/// What a place on the Mapa is to the person: one Casa, one Trabajo, and
/// any number of favourites.
enum PlaceKind { casa, trabajo, favorito }

/// A point the person keeps on the Mapa to plan trips from or to. Only on
/// the phone: places and trips never leave it.
class Place {
  const Place({
    required this.id,
    required this.kind,
    required this.name,
    required this.lat,
    required this.lon,
    this.address,
  });

  /// 'casa' and 'trabajo' for those two, so there is one of each; a
  /// favourite's id is its creation time.
  final String id;
  final PlaceKind kind;

  /// The name of a favourite; 'Casa' or 'Trabajo' for those two.
  final String name;
  final double lat;
  final double lon;

  /// Where it is in words, when it was found by the search ("Av 18 de
  /// Julio 1453"); null for a point held on the map.
  final String? address;

  /// A new Casa or Trabajo at [lat], [lon], or a favourite called [name].
  factory Place.at(
    PlaceKind kind, {
    required double lat,
    required double lon,
    String? name,
    String? address,
    DateTime? now,
  }) => Place(
    id: switch (kind) {
      PlaceKind.casa => 'casa',
      PlaceKind.trabajo => 'trabajo',
      PlaceKind.favorito =>
        'fav-${(now ?? DateTime.now()).millisecondsSinceEpoch}',
    },
    kind: kind,
    name: switch (kind) {
      PlaceKind.casa => 'Casa',
      PlaceKind.trabajo => 'Trabajo',
      PlaceKind.favorito => name!.trim(),
    },
    lat: lat,
    lon: lon,
    address: address,
  );

  Place renamed(String name) => Place(
    id: id,
    kind: kind,
    name: name.trim(),
    lat: lat,
    lon: lon,
    address: address,
  );

  /// The same place, somewhere else.
  Place movedTo({required double lat, required double lon, String? address}) =>
      Place(
        id: id,
        kind: kind,
        name: name,
        lat: lat,
        lon: lon,
        address: address,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'lat': lat,
    'lon': lon,
    'address': ?address,
  };

  /// Null for a value an older or newer app wrote in a shape this one does
  /// not read: that place is skipped, the others stay.
  static Place? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = PlaceKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final id = json['id'];
    final name = json['name'];
    final lat = json['lat'];
    final lon = json['lon'];
    if (kind == null ||
        id is! String ||
        name is! String ||
        lat is! num ||
        lon is! num) {
      return null;
    }
    return Place(
      id: id,
      kind: kind,
      name: name,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      address: json['address'] is String ? json['address'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.lat == lat &&
      other.lon == lon &&
      other.address == address;

  @override
  int get hashCode => Object.hash(id, kind, name, lat, lon, address);
}
