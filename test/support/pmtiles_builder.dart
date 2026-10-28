// Copied unchanged from flutter_map_vector_tiles 2.10.1,
// test/fixtures/pmtiles_builder.dart, for hermetic tests of
// lib/services/map/local_pmtiles_provider.dart. Its licence follows.
//
// BSD 3-Clause License
//
// Copyright (c) 2026, Jonas Grunau
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import 'dart:typed_data';

/// Minimal PMTiles v3 archive writer for tests — the inverse of the
/// package's reader, written independently against the v3 spec.
///
/// Web-safe on purpose (arithmetic instead of 64-bit bitwise ops), so
/// the same fixtures run in the browser suite.
class PmTilesArchiveBuilder {
  final Map<int, List<int>> _tiles = {};
  int minZoom = 0;
  int maxZoom = 3;

  /// Compresses directories, metadata and tiles when set (the archive
  /// then declares gzip); otherwise everything is stored uncompressed.
  List<int> Function(List<int> bytes)? compress;

  /// When > 0, tile entries are split into leaf directories of this
  /// many entries and the root only holds leaf pointers.
  int leafSplit = 0;

  void addTile(int tileId, List<int> bytes) => _tiles[tileId] = bytes;

  Uint8List build() {
    final compression = compress == null ? 1 : 2; // none | gzip
    List<int> pack(List<int> bytes) => compress?.call(bytes) ?? bytes;

    // Tile data section: blobs in tile-ID order, contiguous.
    final tileData = BytesBuilder();
    final tileEntries = <_Entry>[];
    final ids = _tiles.keys.toList()..sort();
    for (final id in ids) {
      final blob = pack(_tiles[id]!);
      tileEntries.add(_Entry(id, tileData.length, blob.length, runLength: 1));
      tileData.add(blob);
    }

    final leafData = BytesBuilder();
    List<_Entry> rootEntries;
    if (leafSplit > 0) {
      rootEntries = [];
      for (var i = 0; i < tileEntries.length; i += leafSplit) {
        final chunk = tileEntries.sublist(
            i,
            i + leafSplit > tileEntries.length
                ? tileEntries.length
                : i + leafSplit);
        final encoded = pack(_encodeDirectory(chunk));
        rootEntries.add(_Entry(
            chunk.first.tileId, leafData.length, encoded.length,
            runLength: 0));
        leafData.add(encoded);
      }
    } else {
      rootEntries = tileEntries;
    }

    final rootDirectory = pack(_encodeDirectory(rootEntries));
    final metadata = pack('{}'.codeUnits);

    const rootOffset = 127;
    final metadataOffset = rootOffset + rootDirectory.length;
    final leafOffset = metadataOffset + metadata.length;
    final dataOffset = leafOffset + leafData.length;

    final header = ByteData(127);
    const magic = 'PMTiles';
    for (var i = 0; i < magic.length; i++) {
      header.setUint8(i, magic.codeUnitAt(i));
    }
    header.setUint8(7, 3); // version
    void u64(int offset, int value) {
      header.setUint32(offset, value % 4294967296, Endian.little);
      header.setUint32(offset + 4, value ~/ 4294967296, Endian.little);
    }

    u64(8, rootOffset);
    u64(16, rootDirectory.length);
    u64(24, metadataOffset);
    u64(32, metadata.length);
    u64(40, leafOffset);
    u64(48, leafData.length);
    u64(56, dataOffset);
    u64(64, tileData.length);
    u64(72, _tiles.length); // addressed tiles
    u64(80, tileEntries.length);
    u64(88, tileEntries.length);
    header.setUint8(96, 1); // clustered
    header.setUint8(97, compression); // internal compression
    header.setUint8(98, compression); // tile compression
    header.setUint8(99, 1); // MVT
    header.setUint8(100, minZoom);
    header.setUint8(101, maxZoom);
    // Positions and center (bytes 102–126) stay zero.

    final archive = BytesBuilder()
      ..add(header.buffer.asUint8List())
      ..add(rootDirectory)
      ..add(metadata)
      ..add(leafData.takeBytes())
      ..add(tileData.takeBytes());
    return archive.takeBytes();
  }

  static List<int> _encodeDirectory(List<_Entry> entries) {
    final buffer = BytesBuilder();
    _writeVarint(buffer, entries.length);
    var lastId = 0;
    for (final entry in entries) {
      _writeVarint(buffer, entry.tileId - lastId);
      lastId = entry.tileId;
    }
    for (final entry in entries) {
      _writeVarint(buffer, entry.runLength);
    }
    for (final entry in entries) {
      _writeVarint(buffer, entry.length);
    }
    var nextByte = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (i > 0 && entry.offset == nextByte) {
        _writeVarint(buffer, 0);
      } else {
        _writeVarint(buffer, entry.offset + 1);
      }
      nextByte = entry.offset + entry.length;
    }
    return buffer.takeBytes();
  }

  static void _writeVarint(BytesBuilder buffer, int value) {
    var v = value;
    while (v >= 0x80) {
      buffer.addByte(0x80 + (v % 0x80));
      v = v ~/ 0x80;
    }
    buffer.addByte(v);
  }
}

class _Entry {
  final int tileId;
  final int offset;
  final int length;
  final int runLength;
  const _Entry(this.tileId, this.offset, this.length,
      {required this.runLength});
}
