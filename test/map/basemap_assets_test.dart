// The basemap files committed in assets/map/ and declared in pubspec.yaml:
// the extract is the one assets/map/README.md describes, and the «Timbre
// Noche» style compiles for flutter_map_vector_tiles with no ámbar in it.
// These read the real files and never skip: a checkout without them fails.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/services/map/basemap.dart';
import 'package:stm_app/services/map/local_pmtiles_provider.dart';

const _archiveSha256 =
    '7f709b47def44df05ddc97e31e0a68158162caecaa85b710ba876ab193835111';

/// The extract bbox: -56.80,-34.97,-55.70,-34.50.
final _bounds = LatLngBounds(
  const LatLng(-34.97, -56.80),
  const LatLng(-34.50, -55.70),
);

/// Every colour of the style: the flavor of assets/map/README.md.
const _palette = {
  '#030814', '#070F22', '#09132A', '#091726', '#0A1A3A', '#0C1F47', //
  '#10172A', '#13284F', '#22396A', '#2C4880', '#7F8FB3', '#9FB0D0',
};

/// ambar, ambarTenue, ambarClaro, avisoNoche, rojoLed and papel of
/// TimbreColors: never on the basemap.
const _forbidden = ['FFB21E', 'C68B1E', 'FFE2A3', '2A2210', 'FF6B57', 'F1ECE2'];

/// What ThemeReader reports for this style, warnings and skipped layers:
/// nothing, every layer compiles. A new message means something of the
/// style stopped drawing.
const _warnings = <String>[];

/// Reads the repo files as the app bundle would.
class _FileBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

vt.TileKey _tileAt(double lat, double lng, int z) {
  final n = 1 << z;
  final x = ((lng + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
  return vt.TileKey(z, x, y);
}

void main() {
  test('pubspec declares the two map files, not the folder', () {
    final lines = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.contains('assets/map'))
        .where((l) => !l.startsWith('#'));
    expect(lines, ['- ${Basemap.archiveAsset}', '- ${Basemap.styleAsset}']);
  });

  test('the extract is the one of the README, bounds in its header', () async {
    final file = File(Basemap.archiveAsset);
    expect(sha256.convert(await file.readAsBytes()).toString(), _archiveSha256);

    final provider = await LocalPmTilesProvider.open(file.path);
    addTearDown(provider.dispose);
    expect(provider.bounds, _bounds);
    expect(provider.minimumZoom, 0);
    expect(provider.maximumZoom, 15);
    expect(provider.header.tileCompression, vt.PmTilesCompression.gzip);

    // Montevideo centro, still gzip-compressed
    for (final z in [10, 14, 15]) {
      final response = await provider.load(_tileAt(-34.9058, -56.1913, z));
      final bytes = (response as vt.TileResponseData).bytes;
      expect(bytes.sublist(0, 2), [0x1f, 0x8b], reason: 'z$z');
    }
    // Buenos Aires is outside the extract
    expect(
      await provider.load(_tileAt(-34.60, -58.38, 14)),
      isA<vt.TileResponseNotFound>(),
    );
  });

  group('the Timbre Noche style', () {
    final raw = File(Basemap.styleAsset).readAsStringSync();
    final style = jsonDecode(raw) as Map<String, Object?>;

    test('is minified, named Timbre Noche, with no sprite or glyphs', () {
      expect(raw.trimRight(), jsonEncode(style));
      expect(style['name'], 'Timbre Noche');
      expect(style.keys, ['version', 'name', 'metadata', 'sources', 'layers']);
      expect((style['sources'] as Map).keys, ['protomaps']);
    });

    test('has only the flavor colours, no ámbar, rojoLed or papel', () {
      final upper = raw.toUpperCase();
      for (final hex in _forbidden) {
        expect(upper, isNot(contains(hex)), reason: hex);
      }
      final colours = RegExp(
        r'#[0-9a-fA-F]{3,8}\b',
      ).allMatches(raw).map((m) => m.group(0)!.toUpperCase()).toSet();
      expect(colours, _palette);
      expect(raw, isNot(contains('rgb')));
      expect(raw, isNot(contains('hsl')));
    });

    test('compiles to 67 layers with the known warnings', () {
      final warnings = <String>[];
      final logger = vt.Logger.custom(
        onLog: warnings.add,
        onWarn: warnings.add,
      );
      final theme = vt.ThemeReader(logger: logger).read(style);
      expect(theme.layers, hasLength(67));
      expect(warnings, _warnings);

      // The collector does hear the reader: a skipped type and an unknown one
      vt.ThemeReader(logger: logger).read({
        'layers': [
          {'id': 'relief', 'type': 'hillshade'},
          {'id': 'what', 'type': 'nope'},
        ],
      });
      expect(warnings, hasLength(2));
    });
  });

  test('Basemap.load serves the real extract from its cache copy', () async {
    final cache = await Directory.systemTemp.createTemp('mvd_basemap_real');
    addTearDown(() => cache.delete(recursive: true));
    final basemap = await Basemap.load(
      bundle: _FileBundle(),
      cacheDirectory: () async => cache,
    );
    addTearDown(basemap.dispose);

    expect(basemap.theme.layers, hasLength(67));
    expect(basemap.attribution, '© OpenStreetMap');
    expect(basemap.bounds, _bounds);
    final copy = File('${cache.path}/map/mvd-20261028.pmtiles');
    expect(sha256.convert(await copy.readAsBytes()).toString(), _archiveSha256);
    expect(
      await basemap.providers['protomaps']!.load(
        _tileAt(-34.9058, -56.1913, 14),
      ),
      isA<vt.TileResponseData>(),
    );
  });
}
