import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';

/// Serves the tiles of a PMTiles v3 archive on local storage.
///
/// flutter_map_vector_tiles 2.10.1 reads PMTiles only over HTTP range
/// requests; this provider reads the same archive from a file, with the
/// package's own header, directory and Hilbert-id code. Tile blobs go out
/// still gzip-compressed: the package inflates them in its worker isolates
/// (it sniffs the gzip magic), so nothing heavy runs on the UI isolate.
/// Directories are inflated here; the root is read once, leaf directories
/// are kept in a small cache.
class LocalPmTilesProvider extends vt.VectorTileProvider {
  LocalPmTilesProvider._(
    this.path,
    this._file,
    this.header,
    this.bounds,
    this._root,
  );

  /// The spec puts the header and the root directory in the first 16 KiB.
  static const _prefixLength = 16384;

  /// PMTiles tile type of Mapbox Vector Tiles.
  static const _mvt = 1;

  /// Same bound as the package's HTTP provider.
  static const _maxLeaves = 32;

  /// Opens the archive at [path]. Throws [vt.PmTilesException] for a
  /// malformed archive, one that does not hold vector tiles or one not
  /// compressed with gzip (or none).
  static Future<LocalPmTilesProvider> open(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      final prefix = await file.read(
        length < _prefixLength ? length : _prefixLength,
      );
      final header = vt.PmTilesHeader.parse(prefix);
      for (final c in [header.internalCompression, header.tileCompression]) {
        if (c != vt.PmTilesCompression.none &&
            c != vt.PmTilesCompression.gzip) {
          throw vt.PmTilesException('unsupported compression $c');
        }
      }
      if (header.tileType != _mvt) {
        throw vt.PmTilesException('tile type ${header.tileType} is not MVT');
      }
      final bounds = _bounds(prefix);
      final rootEnd = header.rootDirectoryOffset + header.rootDirectoryLength;
      Uint8List rootBytes;
      if (rootEnd <= prefix.length) {
        rootBytes = Uint8List.sublistView(
          prefix,
          header.rootDirectoryOffset,
          rootEnd,
        );
      } else {
        await file.setPosition(header.rootDirectoryOffset);
        rootBytes = await file.read(header.rootDirectoryLength);
        _checkLength(rootBytes, header.rootDirectoryLength);
      }
      final root = vt.PmTilesDirectory.decode(
        _inflateDirectory(header, rootBytes),
      );
      return LocalPmTilesProvider._(path, file, header, bounds, root);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  final String path;
  final vt.PmTilesHeader header;

  /// The area the archive covers, from its header (the package's header
  /// class skips these bytes).
  final LatLngBounds bounds;

  final RandomAccessFile _file;
  final vt.PmTilesDirectory _root;

  /// Most recently used last.
  final _leaves = <int, vt.PmTilesDirectory>{};
  final _inFlight = vt.SingleFlight<int, vt.TileResponse>();
  final _leafInFlight = vt.SingleFlight<int, vt.PmTilesDirectory>();

  /// A [RandomAccessFile] takes one operation at a time: reads, and the
  /// final close, queue here.
  Future<void> _queue = Future.value();
  var _disposed = false;

  @visibleForTesting
  int get cachedLeafCount => _leaves.length;

  @override
  int get minimumZoom => header.minZoom;

  @override
  int get maximumZoom => header.maxZoom;

  /// The file name carries the extract version, so the key changes with it.
  @override
  String get cacheKey => 'local-pmtiles:$path';

  /// Already on local storage: no second copy in the disk cache.
  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) {
    // Cancelled, not NotFound: an absent tile is cached process-wide
    if (_disposed) return Future.value(const vt.TileResponseCancelled());
    if (tile.z < minimumZoom ||
        tile.z > maximumZoom ||
        tile.z > vt.pmTilesMaxAddressableZoom) {
      return Future.value(const vt.TileResponseNotFound());
    }
    final id = vt.zxyToTileId(tile.z, tile.x, tile.y);
    return _inFlight.run(
      id,
      (token) => _load(id, token),
      cancellation: cancellation,
    );
  }

  Future<vt.TileResponse> _load(int id, vt.CancellationToken token) async {
    try {
      var directory = _root;
      // One leaf level is the norm; tolerate two, like the package.
      for (var depth = 0; depth < 3; depth++) {
        if (_disposed || token.isCancelled) {
          return const vt.TileResponseCancelled();
        }
        final entry = directory.find(id);
        if (entry == null) return const vt.TileResponseNotFound();
        if (!entry.isLeaf) {
          final bytes = await _read(
            header.tileDataOffset + entry.offset,
            entry.length,
          );
          if (_disposed) return const vt.TileResponseCancelled();
          if (bytes.isEmpty) return const vt.TileResponseNotFound();
          return vt.TileResponseData(bytes);
        }
        directory = await _leaf(entry);
      }
      return const vt.TileResponseNotFound();
    } catch (e) {
      if (_disposed || token.isCancelled) {
        return const vt.TileResponseCancelled();
      }
      return vt.TileResponseError(e);
    }
  }

  /// A leaf directory serves many tiles: read once, never cancelled by
  /// one caller.
  Future<vt.PmTilesDirectory> _leaf(vt.PmTilesEntry entry) async {
    final cached = _leaves.remove(entry.offset);
    if (cached != null) return _leaves[entry.offset] = cached;
    return _leafInFlight.run(entry.offset, (_) async {
      final bytes = await _read(
        header.leafDirectoriesOffset + entry.offset,
        entry.length,
      );
      final directory = vt.PmTilesDirectory.decode(
        _inflateDirectory(header, bytes),
      );
      _leaves[entry.offset] = directory;
      if (_leaves.length > _maxLeaves) _leaves.remove(_leaves.keys.first);
      return directory;
    });
  }

  Future<Uint8List> _read(int offset, int length) {
    final result = Completer<Uint8List>();
    _queue = _queue.then((_) async {
      try {
        // Queued before dispose but not run yet: the file is about to close
        if (_disposed) throw const vt.PmTilesException('provider disposed');
        await _file.setPosition(offset);
        final bytes = await _file.read(length);
        _checkLength(bytes, length);
        result.complete(bytes);
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  /// A truncated archive reads short; that is an error, not a tile.
  static void _checkLength(Uint8List bytes, int length) {
    if (bytes.length != length) {
      throw vt.PmTilesException(
        'truncated archive: read ${bytes.length} of $length bytes',
      );
    }
  }

  /// Header bytes 102-117: min lon, min lat, max lon, max lat, each an
  /// int32 in units of 1e-7 degrees.
  static LatLngBounds _bounds(Uint8List header) {
    final data = ByteData.sublistView(header);
    double e7(int offset) => data.getInt32(offset, Endian.little) / 1e7;
    final west = e7(102), south = e7(106), east = e7(110), north = e7(114);
    if (south < -90 ||
        north > 90 ||
        south > north ||
        west < -180 ||
        east > 180 ||
        west > east) {
      throw const vt.PmTilesException('bad bounds in the header');
    }
    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  static Uint8List _inflateDirectory(vt.PmTilesHeader header, Uint8List b) {
    if (header.internalCompression != vt.PmTilesCompression.gzip) return b;
    final out = gzip.decode(b);
    return out is Uint8List ? out : Uint8List.fromList(out);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inFlight.clear();
    _leafInFlight.clear();
    // After every read already queued, so none runs on a closed file
    _queue = _queue.then((_) async {
      try {
        await _file.close();
      } catch (_) {}
    });
  }
}
