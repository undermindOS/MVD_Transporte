// The local PMTiles provider of the Mapa basemap, on small archives written
// by test/support/pmtiles_builder.dart into temp files: no network, no
// bundled asset (that one is checked in basemap_assets_test.dart).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/services/map/local_pmtiles_provider.dart';

import '../support/pmtiles_builder.dart';

/// Distinct bytes per tile, so a wrong offset shows.
List<int> _tileBytes(int z, int x, int y) => [z, x % 256, y % 256, 0x4d, 0x56];

/// An archive with every tile of zooms 0 to [maxZoom].
Uint8List _archive({bool gzipped = false, int maxZoom = 3, int leafSplit = 0}) {
  final builder = PmTilesArchiveBuilder()
    ..maxZoom = maxZoom
    ..leafSplit = leafSplit;
  if (gzipped) builder.compress = gzip.encode;
  for (var z = 0; z <= maxZoom; z++) {
    for (var x = 0; x < 1 << z; x++) {
      for (var y = 0; y < 1 << z; y++) {
        builder.addTile(vt.zxyToTileId(z, x, y), _tileBytes(z, x, y));
      }
    }
  }
  return builder.build();
}

/// Writes the extract bbox into header bytes 102-117 (the builder leaves
/// them zero).
Uint8List _withBounds(
  Uint8List archive, {
  required double west,
  required double south,
  required double east,
  required double north,
}) {
  final data = ByteData.sublistView(archive);
  data.setInt32(102, (west * 1e7).round(), Endian.little);
  data.setInt32(106, (south * 1e7).round(), Endian.little);
  data.setInt32(110, (east * 1e7).round(), Endian.little);
  data.setInt32(114, (north * 1e7).round(), Endian.little);
  return archive;
}

void main() {
  late Directory dir;
  final open = <LocalPmTilesProvider>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mvd_pmtiles_test');
  });

  tearDown(() async {
    for (final provider in open) {
      provider.dispose();
    }
    open.clear();
    // Let the queued closes run before the files go
    await Future<void>.delayed(Duration.zero);
    await dir.delete(recursive: true);
  });

  Future<String> write(List<int> bytes, [String name = 'a.pmtiles']) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<LocalPmTilesProvider> openArchive(List<int> bytes) async {
    final provider = await LocalPmTilesProvider.open(await write(bytes));
    open.add(provider);
    return provider;
  }

  Future<Uint8List> dataOf(LocalPmTilesProvider p, int z, int x, int y) async {
    final response = await p.load(vt.TileKey(z, x, y));
    expect(response, isA<vt.TileResponseData>(), reason: 'z$z/$x/$y');
    return (response as vt.TileResponseData).bytes;
  }

  test(
    'gzip tiles come out still compressed, for the worker isolates',
    () async {
      final provider = await openArchive(_archive(gzipped: true));
      expect(provider.minimumZoom, 0);
      expect(provider.maximumZoom, 3);
      expect(provider.cacheBytesToDisk, isFalse);
      expect(provider.cacheKey, contains('a.pmtiles'));

      for (final (z, x, y) in [(0, 0, 0), (2, 1, 3), (3, 7, 0)]) {
        final bytes = await dataOf(provider, z, x, y);
        expect(bytes.sublist(0, 2), [0x1f, 0x8b], reason: 'gzip magic');
        expect(gzip.decode(bytes), _tileBytes(z, x, y));
      }
      // Past the archive's zooms
      expect(
        await provider.load(const vt.TileKey(4, 0, 0)),
        isA<vt.TileResponseNotFound>(),
      );
    },
  );

  test('uncompressed tiles come out as they are', () async {
    final provider = await openArchive(_archive());
    for (final (z, x, y) in [(0, 0, 0), (1, 1, 0), (3, 5, 6)]) {
      expect(await dataOf(provider, z, x, y), _tileBytes(z, x, y));
    }
  });

  test('a tile the archive does not have is NotFound', () async {
    final builder = PmTilesArchiveBuilder()
      ..maxZoom = 2
      ..addTile(vt.zxyToTileId(2, 1, 1), [1, 2, 3]);
    final provider = await openArchive(builder.build());
    expect(await dataOf(provider, 2, 1, 1), [1, 2, 3]);
    expect(
      await provider.load(const vt.TileKey(2, 2, 2)),
      isA<vt.TileResponseNotFound>(),
    );
    expect(
      await provider.load(const vt.TileKey(0, 0, 0)),
      isA<vt.TileResponseNotFound>(),
    );
  });

  for (final gzipped in [false, true]) {
    test('leaf directories are followed (gzip: $gzipped)', () async {
      final provider = await openArchive(
        _archive(gzipped: gzipped, leafSplit: 7),
      );
      for (var z = 0; z <= 3; z++) {
        for (var x = 0; x < 1 << z; x++) {
          for (var y = 0; y < 1 << z; y++) {
            final bytes = await dataOf(provider, z, x, y);
            expect(gzipped ? gzip.decode(bytes) : bytes, _tileBytes(z, x, y));
          }
        }
      }
    });
  }

  test('the leaf cache stays bounded and still serves every tile', () async {
    // 85 tiles, one leaf each
    final provider = await openArchive(_archive(leafSplit: 1));
    for (var round = 0; round < 2; round++) {
      for (var z = 0; z <= 3; z++) {
        for (var x = 0; x < 1 << z; x++) {
          for (var y = 0; y < 1 << z; y++) {
            expect(await dataOf(provider, z, x, y), _tileBytes(z, x, y));
          }
        }
      }
    }
    expect(provider.cachedLeafCount, 32);
  });

  test('a root directory past the first 16 KiB is read on its own', () async {
    final provider = await openArchive(_archive(maxZoom: 6));
    expect(provider.header.rootDirectoryLength, greaterThan(16384));
    expect(await dataOf(provider, 0, 0, 0), _tileBytes(0, 0, 0));
    expect(await dataOf(provider, 6, 63, 63), _tileBytes(6, 63, 63));
  });

  test('50 concurrent loads all get their own tile', () async {
    final provider = await openArchive(_archive(gzipped: true, leafSplit: 9));
    final keys = [
      for (var x = 0; x < 8; x++)
        for (var y = 0; y < 6; y++) vt.TileKey(3, x, y),
      // The same tile twice more: coalesced
      const vt.TileKey(3, 0, 0),
      const vt.TileKey(3, 0, 0),
    ];
    expect(keys, hasLength(50));
    final responses = await Future.wait([
      for (final k in keys) provider.load(k),
    ]);
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      expect(responses[i], isA<vt.TileResponseData>(), reason: '$k');
      expect(
        gzip.decode((responses[i] as vt.TileResponseData).bytes),
        _tileBytes(k.z, k.x, k.y),
      );
    }
  });

  test(
    'loads pending at dispose and after it are Cancelled, not NotFound',
    () async {
      final provider = await openArchive(_archive());
      final pending = [
        for (var x = 0; x < 4; x++) provider.load(vt.TileKey(2, x, 1)),
      ];
      provider.dispose();
      provider.dispose(); // twice is fine
      for (final response in await Future.wait(pending)) {
        expect(response, isA<vt.TileResponseCancelled>());
      }
      // Absent tiles are cached process-wide: a disposed provider must not
      // report one
      expect(
        await provider.load(const vt.TileKey(0, 0, 0)),
        isA<vt.TileResponseCancelled>(),
      );
      expect(
        await provider.load(const vt.TileKey(9, 0, 0)),
        isA<vt.TileResponseCancelled>(),
      );
    },
  );

  test(
    'a truncated archive gives an error for the cut tile, not data',
    () async {
      final full = _archive(maxZoom: 2);
      // The last tile in id order is z2's last on the Hilbert curve; cut it
      final provider = await openArchive(full.sublist(0, full.length - 2));
      var errors = 0;
      for (var x = 0; x < 4; x++) {
        for (var y = 0; y < 4; y++) {
          final response = await provider.load(vt.TileKey(2, x, y));
          if (response is vt.TileResponseError) {
            errors++;
            expect(response.error, isA<vt.PmTilesException>());
          } else {
            expect(
              (response as vt.TileResponseData).bytes,
              _tileBytes(2, x, y),
            );
          }
        }
      }
      expect(errors, 1);
    },
  );

  test('an archive cut inside its root directory does not open', () async {
    final full = _archive(maxZoom: 6);
    await expectLater(
      LocalPmTilesProvider.open(await write(full.sublist(0, 20000))),
      throwsA(isA<vt.PmTilesException>()),
    );
    await expectLater(
      LocalPmTilesProvider.open(await write(full.sublist(0, 100), 'b.pmtiles')),
      throwsA(isA<vt.PmTilesException>()),
    );
  });

  test('bad magic, version, compression or tile type do not open', () async {
    Future<void> rejects(String name, void Function(Uint8List) corrupt) async {
      final bytes = _archive();
      corrupt(bytes);
      await expectLater(
        LocalPmTilesProvider.open(await write(bytes, name)),
        throwsA(isA<vt.PmTilesException>()),
        reason: name,
      );
    }

    await rejects('magic', (b) => b[0] = 0x51);
    await rejects('version', (b) => b[7] = 2);
    await rejects('brotli', (b) => b[98] = vt.PmTilesCompression.brotli);
    await rejects('unknown', (b) => b[97] = vt.PmTilesCompression.unknown);
    await rejects('png', (b) => b[99] = 2);
  });

  test('the bounds come from the header', () async {
    final provider = await openArchive(
      _withBounds(
        _archive(),
        west: -56.80,
        south: -34.97,
        east: -55.70,
        north: -34.50,
      ),
    );
    expect(
      provider.bounds,
      LatLngBounds(const LatLng(-34.97, -56.80), const LatLng(-34.50, -55.70)),
    );

    final bad = _withBounds(
      _archive(),
      west: -55.70,
      south: -34.97,
      east: -56.80,
      north: -34.50,
    );
    await expectLater(
      LocalPmTilesProvider.open(await write(bad, 'bad.pmtiles')),
      throwsA(isA<vt.PmTilesException>()),
    );
  });
}
