// Basemap.load with a fake asset bundle and temp cache directories: the
// archive copy (first copy, reuse, version change, leftovers, overlapping
// calls, a retry, a path with a space), the style compile and the layer it
// hands out. No network, no bundled asset (those are checked in
// basemap_assets_test.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/services/map/basemap.dart';
import 'package:stm_app/services/map/local_pmtiles_provider.dart';

import '../support/pmtiles_builder.dart';

/// Serves fixed bytes per key and counts the loads.
class _Bundle extends AssetBundle {
  _Bundle(this.files);

  final Map<String, List<int>> files;
  final loads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    loads[key] = (loads[key] ?? 0) + 1;
    final bytes = files[key];
    if (bytes == null) throw StateError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// A one-tile archive with the extract's bbox in its header.
Uint8List _archive([List<int> tile = const [1, 2, 3]]) {
  final bytes =
      (PmTilesArchiveBuilder()
            ..maxZoom = 2
            ..addTile(vt.zxyToTileId(2, 1, 2), tile))
          .build();
  final data = ByteData.sublistView(bytes);
  data.setInt32(102, -568000000, Endian.little);
  data.setInt32(106, -349700000, Endian.little);
  data.setInt32(110, -557000000, Endian.little);
  data.setInt32(114, -345000000, Endian.little);
  return bytes;
}

String _style({Object? attribution = '© OpenStreetMap'}) => jsonEncode({
  'version': 8,
  'name': 'Timbre Noche',
  'sources': {
    'protomaps': {
      'type': 'vector',
      'url': 'pmtiles://__PMTILES__',
      'attribution': ?attribution,
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#070F22'},
    },
    {
      'id': 'water',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'water',
      'paint': {'fill-color': '#0C1F47'},
    },
  ],
});

/// Holds every load until [release], so a copy stays in progress.
class _HeldBundle extends _Bundle {
  _HeldBundle(super.files);

  final loading = Completer<void>();
  final _released = Completer<void>();

  void release() => _released.complete();

  @override
  Future<ByteData> load(String key) async {
    if (!loading.isCompleted) loading.complete();
    await _released.future;
    return super.load(key);
  }
}

_Bundle _bundle({List<int>? archive, String? style}) => _Bundle({
  Basemap.archiveAsset: archive ?? _archive(),
  Basemap.styleAsset: utf8.encode(style ?? _style()),
});

String get _name =>
    Basemap.archiveAsset.substring(Basemap.archiveAsset.lastIndexOf('/') + 1);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mvd_basemap_test');
  });

  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    await root.delete(recursive: true);
  });

  Future<Directory> cache() async => root;

  List<String> mapFolder() =>
      Directory('${root.path}/map')
          .listSync()
          .map((e) => e.path.substring(e.path.lastIndexOf('/') + 1))
          .toList()
        ..sort();

  test(
    'the first open copies the archive into the cache, through a rename',
    () async {
      final bundle = _bundle();
      final path = await Basemap.ensureArchive(
        bundle: bundle,
        cacheDirectory: cache,
      );
      expect(path, '${root.path}/map/$_name');
      expect(File(path).readAsBytesSync(), _archive());
      expect(mapFolder(), [_name]);
      expect(bundle.loads[Basemap.archiveAsset], 1);
    },
  );

  test('a copy that exists is reused without reading the bundle', () async {
    final bundle = _bundle();
    final first = await Basemap.ensureArchive(
      bundle: bundle,
      cacheDirectory: cache,
    );
    final again = await Basemap.ensureArchive(
      bundle: bundle,
      cacheDirectory: cache,
    );
    expect(again, first);
    expect(bundle.loads[Basemap.archiveAsset], 1);
  });

  test(
    'a new extract version deletes the old copies and leftovers only',
    () async {
      final folder = Directory('${root.path}/map')..createSync();
      for (final name in [
        'mvd-20250101.pmtiles',
        'other.pmtiles',
        'mvd-20250101.pmtiles.tmp',
        'notes.txt',
      ]) {
        File('${folder.path}/$name').writeAsStringSync('old');
      }
      Directory('${folder.path}/sub.pmtiles').createSync();

      await Basemap.ensureArchive(bundle: _bundle(), cacheDirectory: cache);
      expect(mapFolder(), [_name, 'notes.txt', 'sub.pmtiles']..sort());
    },
  );

  test('a leftover .tmp of an interrupted copy is replaced', () async {
    final folder = Directory('${root.path}/map')..createSync();
    File('${folder.path}/$_name.tmp').writeAsStringSync('half a copy');

    final path = await Basemap.ensureArchive(
      bundle: _bundle(),
      cacheDirectory: cache,
    );
    expect(File(path).readAsBytesSync(), _archive());
    expect(mapFolder(), [_name]);
  });

  test('overlapping calls share one copy', () async {
    final bundle = _HeldBundle(_bundle().files);
    final first = Basemap.ensureArchive(bundle: bundle, cacheDirectory: cache);
    await bundle.loading.future;
    final second = Basemap.ensureArchive(bundle: bundle, cacheDirectory: cache);
    bundle.release();

    final path = '${root.path}/map/$_name';
    expect(await Future.wait([first, second]), [path, path]);
    expect(bundle.loads[Basemap.archiveAsset], 1);
    expect(File(path).readAsBytesSync(), _archive());
    expect(mapFolder(), [_name]);
  });

  test('a failed copy is retried by the next call', () async {
    await expectLater(
      Basemap.ensureArchive(bundle: _Bundle({}), cacheDirectory: cache),
      throwsStateError,
    );
    final path = await Basemap.ensureArchive(
      bundle: _bundle(),
      cacheDirectory: cache,
    );
    expect(File(path).readAsBytesSync(), _archive());
  });

  test(
    'load works under a path with a space, like iOS Application Support',
    () async {
      final spaced = Directory('${root.path}/Library/Application Support')
        ..createSync(recursive: true);
      final basemap = await Basemap.load(
        bundle: _bundle(archive: _archive([7, 8, 9])),
        cacheDirectory: () async => spaced,
      );
      addTearDown(basemap.dispose);

      expect(File('${spaced.path}/map/$_name').existsSync(), isTrue);
      final response = await basemap.providers['protomaps']!.load(
        const vt.TileKey(2, 1, 2),
      );
      expect((response as vt.TileResponseData).bytes, [7, 8, 9]);
    },
  );

  test(
    'load compiles the style once and reads bounds and attribution',
    () async {
      final basemap = await Basemap.load(
        bundle: _bundle(),
        cacheDirectory: cache,
      );
      addTearDown(basemap.dispose);

      expect(basemap.theme.layers.map((l) => l.id), ['background', 'water']);
      expect(basemap.providers.providers.keys, ['protomaps']);
      expect(basemap.providers['protomaps'], isA<LocalPmTilesProvider>());
      expect(basemap.attribution, '© OpenStreetMap');
      expect(
        basemap.bounds,
        LatLngBounds(
          const LatLng(-34.97, -56.80),
          const LatLng(-34.50, -55.70),
        ),
      );

      // Every layer it hands out shares the same theme and providers, so a
      // rebuild keeps the tiles
      final a = basemap.layer();
      final b = basemap.layer();
      expect(identical(a.theme, b.theme), isTrue);
      expect(identical(a.tileProviders, b.tileProviders), isTrue);
      expect(identical(a.theme, basemap.theme), isTrue);
      expect(a.tileOffset, vt.TileOffset.maplibre);
      expect(a.diskCacheMaximumSizeInBytes, 0);
    },
  );

  test('a style without attribution does not load', () async {
    await expectLater(
      Basemap.load(
        bundle: _bundle(style: _style(attribution: null)),
        cacheDirectory: cache,
      ),
      throwsFormatException,
    );
  });

  test('dispose closes the archive', () async {
    final basemap = await Basemap.load(
      bundle: _bundle(),
      cacheDirectory: cache,
    );
    basemap.dispose();
    expect(
      await basemap.providers['protomaps']!.load(const vt.TileKey(2, 1, 2)),
      isA<vt.TileResponseCancelled>(),
    );
  });

  test('style zoom is flutter_map zoom - 1', () {
    expect(Basemap.tileOffset.zoomOffset, -1);
    expect(Basemap.fmZoom(14), 15);
    expect(Basemap.styleZoom(15), 14);
    expect(Basemap.styleZoom(Basemap.fmZoom(10.5)), 10.5);
  });
}
