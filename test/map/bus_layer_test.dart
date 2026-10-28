// The Mapa's bus layer on a FlutterMap with no tiles: a tap finds the bus
// under it, also mid-move; pills from style z14, dots below; estimates are
// unlit; moves jump with reduced motion or off screen; the pill atlas is
// drawn again after a trip to the background.


import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:stm_app/services/map/basemap.dart';
import 'package:stm_app/ui/map/bus_layer.dart';
import 'package:stm_app/ui/map/map_buses.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';

const _a = LatLng(-34.9060, -56.1950);
const _b = LatLng(-34.9080, -56.1900);

MapBus _bus(LatLng at, {String key = 'bus-50-1', bool live = true}) => MapBus(
  key: key,
  line: '145',
  destination: 'BV ARTIGAS Y BV ESPAÑA',
  position: at,
  live: live,
  etas: const [(stopId: 3140, etaMinutes: 7, clockTime: '8:59')],
);

void main() {
  late BusLayerHandle handle;
  late MapController controller;

  setUp(() {
    handle = BusLayerHandle();
    controller = MapController();
  });

  Widget map(
    List<MapBus> buses, {
    double styleZoom = 15,
    bool animate = true,
    bool reduceMotion = false,
  }) => MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: const LatLng(-34.907, -56.193),
            initialZoom: Basemap.fmZoom(styleZoom),
          ),
          children: [BusLayer(buses: buses, handle: handle, animate: animate)],
        ),
      ),
    ),
  );

  testWidgets('a tap finds the bus under it, also while it moves', (
    tester,
  ) async {
    await tester.pumpWidget(map([_bus(_a)]));
    final camera = controller.camera;
    final atA = camera.latLngToScreenOffset(_a);
    final atB = camera.latLngToScreenOffset(_b);

    expect(handle.hitTest(atA, camera)?.key, 'bus-50-1');
    expect(handle.hitTest(atA + const Offset(0, 40), camera), isNull);

    // New position: the marker moves there over 1 s
    await tester.pumpWidget(map([_bus(_b)]));
    await tester.pump(const Duration(milliseconds: 500));
    final mid = Offset.lerp(atA, atB, 0.5)!;
    expect(handle.hitTest(mid, camera)?.key, 'bus-50-1');
    expect(handle.hitTest(atA, camera), isNull);
    await tester.pump(const Duration(milliseconds: 600));
    expect(handle.hitTest(atB, camera)?.key, 'bus-50-1');

    // Below style z14 buses are dots with a smaller target
    controller.move(const LatLng(-34.907, -56.193), Basemap.fmZoom(13));
    await tester.pump();
    final far = controller.camera;
    final dot = far.latLngToScreenOffset(_b);
    expect(handle.hitTest(dot, far)?.key, 'bus-50-1');
    expect(handle.hitTest(dot + const Offset(20, 0), far), isNull);
    expect(handle.drawn.single.key, 'bus-50-1');
  });

  testWidgets('pills from style z14: a wide target', (tester) async {
    await tester.pumpWidget(map([_bus(_a)], styleZoom: 14));
    final camera = controller.camera;
    final atA = camera.latLngToScreenOffset(_a);
    // A pill is wider than a dot's 14 px reach
    expect(handle.hitTest(atA + const Offset(18, 0), camera)?.key, 'bus-50-1');
    expect(handle.hasAtlas, isTrue);

    // Just below: dots
    controller.move(const LatLng(-34.907, -56.193), Basemap.fmZoom(13.9));
    await tester.pump();
    final dots = controller.camera;
    final dot = dots.latLngToScreenOffset(_a);
    expect(handle.hitTest(dot + const Offset(18, 0), dots), isNull);
    expect(handle.hitTest(dot, dots)?.key, 'bus-50-1');
  });

  /// Pixels close to ámbar in a [window] around [center] of the layer.
  Future<int> amberAround(
    WidgetTester tester,
    Offset center,
    Size window,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(BusLayer),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(() => image.toByteData()))!;
    final width = image.width;
    image.dispose();
    const amber = TimbreColors.ambar;
    bool near(int byte, double channel) => (byte / 255 - channel).abs() < 0.12;
    var count = 0;
    final rect = Rect.fromCenter(
      center: center,
      width: window.width,
      height: window.height,
    );
    for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
      for (var x = rect.left.round(); x < rect.right.round(); x++) {
        final i = (y * width + x) * 4;
        if (near(bytes.getUint8(i), amber.r) &&
            near(bytes.getUint8(i + 1), amber.g) &&
            near(bytes.getUint8(i + 2), amber.b)) {
          count++;
        }
      }
    }
    return count;
  }

  for (final styleZoom in [15.0, 12.0]) {
    testWidgets('at style z$styleZoom a live bus is lit, an estimate is not', (
      tester,
    ) async {
      const west = LatLng(-34.907, -56.197);
      const east = LatLng(-34.907, -56.189);
      await tester.pumpWidget(
        map([
          _bus(west, key: 'bus-50-1'),
          _bus(east, key: 'bus-50-2', live: false),
        ], styleZoom: styleZoom),
      );
      final camera = controller.camera;
      // A pill, or a dot and its halo
      final window = styleZoom >= 14 ? const Size(60, 20) : const Size(10, 10);
      expect(
        await amberAround(tester, camera.latLngToScreenOffset(west), window),
        greaterThan(styleZoom >= 14 ? 300 : 9),
      );
      expect(
        await amberAround(tester, camera.latLngToScreenOffset(east), window),
        0,
      );
    });
  }

  testWidgets('with reduced motion a bus jumps to its new position', (
    tester,
  ) async {
    await tester.pumpWidget(map([_bus(_a)], reduceMotion: true));
    final camera = controller.camera;
    await tester.pumpWidget(map([_bus(_b)], reduceMotion: true));
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      handle.hitTest(camera.latLngToScreenOffset(_b), camera)?.key,
      'bus-50-1',
    );
  });

  testWidgets('off screen a bus jumps, and a move under way ends', (
    tester,
  ) async {
    await tester.pumpWidget(map([_bus(_a)]));
    final camera = controller.camera;
    await tester.pumpWidget(map([_bus(_b)]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(map([_bus(_b)], animate: false));
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      handle.hitTest(camera.latLngToScreenOffset(_b), camera)?.key,
      'bus-50-1',
    );

    await tester.pumpWidget(map([_bus(_a)], animate: false));
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      handle.hitTest(camera.latLngToScreenOffset(_a), camera)?.key,
      'bus-50-1',
    );
  });

  testWidgets('back from the background the pill atlas is drawn again', (
    tester,
  ) async {
    await tester.pumpWidget(map([_bus(_a)]));
    expect(handle.hasAtlas, isTrue);
    final drawn = handle.atlasVersion;

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    // Nothing drawn while away
    expect(handle.atlasVersion, drawn);

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    // Dropped and drawn again
    expect(handle.atlasVersion, drawn + 2);
    expect(handle.hasAtlas, isTrue);
  });
}
