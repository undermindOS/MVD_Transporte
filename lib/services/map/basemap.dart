import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:path_provider/path_provider.dart';

import 'local_pmtiles_provider.dart';

/// The basemap bundled in the app: the «Timbre Noche» style compiled for
/// flutter_map_vector_tiles, and its tiles read from a copy of the PMTiles
/// archive in the app cache directory. Moving the map asks no server.
///
/// Theme and providers are built once, in [load]: a VectorTileLayer drops
/// its tiles whenever either changes identity. Provenance, licences and how
/// to regenerate the assets: assets/map/README.md.
class Basemap {
  Basemap._({
    required this.theme,
    required this.providers,
    required this.bounds,
    required this.attribution,
  });

  /// The extract; the build date in the name is its version.
  static const archiveAsset = 'assets/map/mvd-20261028.pmtiles';
  static const styleAsset = 'assets/map/style_noche.json';

  /// The style's only source.
  static const _source = 'protomaps';

  /// Where the archive copy lives, inside the app cache directory.
  static const _cacheFolder = 'map';

  /// The style is written for MapLibre's 512 px tiles; flutter_map counts
  /// zoom with 256 px tiles, one level higher at the same scale. The layer
  /// evaluates the style at flutter_map zoom - 1.
  static const tileOffset = vt.TileOffset.maplibre;

  /// flutter_map zoom (cameras, MapOptions) for a style zoom.
  static double fmZoom(double styleZoom) => styleZoom + 1;

  /// Style zoom (the zoom the style JSON and the docs talk about) for a
  /// flutter_map zoom.
  static double styleZoom(double fmZoom) => fmZoom - 1;

  final vt.Theme theme;
  final vt.TileProviders providers;

  /// The area the extract covers, from the archive header. Past it there
  /// are no tiles.
  final LatLngBounds bounds;

  /// The source's attribution ('© OpenStreetMap'); ODbL wants it visible
  /// on the map.
  final String attribution;

  /// Copies the archive out of the bundle when needed, opens it and
  /// compiles the style.
  ///
  /// The style goes through [vt.ThemeReader], not StyleReader: StyleReader
  /// reads `asset://` only from rootBundle, and it would open a source it
  /// cannot resolve over HTTP. Here the source is served by id from the
  /// local copy, so no URL is ever read and the file path (with a space on
  /// iOS) never goes through one.
  static Future<Basemap> load({
    AssetBundle? bundle,
    Future<Directory> Function()? cacheDirectory,
  }) async {
    final assets = bundle ?? rootBundle;
    // Read once: no reason to keep the string in the bundle cache
    final style =
        jsonDecode(await assets.loadString(styleAsset, cache: false))
            as Map<String, Object?>;
    final theme = vt.ThemeReader().read(style);
    final attribution = _attribution(style);
    final path = await ensureArchive(
      bundle: assets,
      cacheDirectory: cacheDirectory ?? getApplicationCacheDirectory,
    );
    final provider = await LocalPmTilesProvider.open(path);
    return Basemap._(
      theme: theme,
      providers: vt.TileProviders({_source: provider}),
      bounds: provider.bounds,
      attribution: attribution,
    );
  }

  static String _attribution(Map<String, Object?> style) {
    final sources = style['sources'];
    final declared = sources is Map ? sources[_source] : null;
    final attribution = declared is Map ? declared['attribution'] : null;
    if (attribution is! String || attribution.trim().isEmpty) {
      throw const FormatException('the basemap style has no attribution');
    }
    return vt.StyleAttribution.parse(attribution).text;
  }

  /// The path of the archive copy in `<cacheDirectory>/map/`, copied from
  /// [bundle] when it is not there. The copy is written aside and renamed,
  /// and its name carries the version: a file that exists is complete.
  /// Other `*.pmtiles` (older extracts) and `*.tmp` (interrupted copies)
  /// in that folder are deleted.
  @visibleForTesting
  static Future<String> ensureArchive({
    required AssetBundle bundle,
    required Future<Directory> Function() cacheDirectory,
  }) async {
    final sep = Platform.pathSeparator;
    final dir = Directory('${(await cacheDirectory()).path}$sep$_cacheFolder');
    final name = archiveAsset.substring(archiveAsset.lastIndexOf('/') + 1);
    final file = File('${dir.path}$sep$name');
    await dir.create(recursive: true);
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final other = entity.path.substring(entity.path.lastIndexOf(sep) + 1);
      if (other != name &&
          (other.endsWith('.pmtiles') || other.endsWith('.tmp'))) {
        await entity.delete();
      }
    }
    if (await file.exists()) return file.path;
    final data = await bundle.load(archiveAsset);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await tmp.rename(file.path);
    return file.path;
  }

  /// The basemap layer for a FlutterMap. Cheap to call in build(): theme
  /// and providers are this object's, so the layer keeps its tiles.
  vt.VectorTileLayer layer() => vt.VectorTileLayer(
    theme: theme,
    tileProviders: providers,
    tileOffset: tileOffset,
    // The tiles are already on local storage
    diskCacheMaximumSizeInBytes: 0,
  );

  /// Releases the decoded tiles and label text kept in memory between map
  /// opens (process-wide, they outlive the layer). For memory pressure.
  static void clearMemoryCache() => vt.VectorTileLayer.clearMemoryCache();

  /// Closes the archive. Call after the map that uses this basemap is gone.
  void dispose() => providers.dispose();
}
