import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../services/map/basemap.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/pixel_icon.dart';
import 'map_buses.dart';

/// Lets the page ask the layer which bus is under a tap.
class BusLayerHandle {
  _BusLayerState? _state;

  /// The bus drawn under [screen] (relative to the map widget), nearest to
  /// its center, or null.
  MapBus? hitTest(Offset screen, MapCamera camera) =>
      _state?._hitTest(screen, camera);

  /// The buses the layer draws now, in drawing order.
  @visibleForTesting
  List<MapBus> get drawn => [for (final t in _state?._order ?? []) t.bus];

  /// Goes up each time the pill atlas is drawn or dropped.
  @visibleForTesting
  int get atlasVersion => _state?._sprites.version ?? 0;

  /// Whether a pill atlas is drawn now.
  @visibleForTesting
  bool get hasAtlas => _state?._sprites.image != null;
}

/// Every bus of the map in one custom layer: one `drawRawAtlas` call for
/// the pills (one sprite per line number, drawn once into an atlas) or
/// `drawRawPoints` for the dots below style zoom [pillMinStyleZoom].
///
/// No widget per bus: a new set of positions starts one
/// [AnimationController] and each frame of the move only repaints this
/// layer (its own [RepaintBoundary]), lerping every bus from where it was
/// drawn to its new position. Buses that appear show up in place; buses
/// that leave disappear at once. A live bus is lit like
/// `LineBadge(live: true)`; an estimate is unlit, never ámbar.
///
/// Buses are paint only: screen readers hear them on the stop markers.
class BusLayer extends StatefulWidget {
  const BusLayer({
    super.key,
    required this.buses,
    required this.handle,
    this.animate = true,
  });

  final List<MapBus> buses;
  final BusLayerHandle handle;

  /// Moves glide over [moveDuration]. false, or reduced motion, makes them
  /// jump: the map is not on screen, its ticker is off. The first buses
  /// after it turns true jump too: they moved while it was away.
  final bool animate;

  /// Below this style zoom buses are dots: at z13 a pill covers a few
  /// blocks and they bury the city.
  static const pillMinStyleZoom = 14.0;

  /// A bus gliding to its new position.
  static const moveDuration = Duration(milliseconds: 1000);

  @override
  State<BusLayer> createState() => _BusLayerState();
}

class _Track {
  _Track(this.bus, this.fromX, this.fromY) : toX = fromX, toY = fromY;

  MapBus bus;
  double fromX, fromY, toX, toY;
  LatLng from = const LatLng(0, 0);
}

class _BusLayerState extends State<BusLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _crs = Epsg3857();
  static const _curve = Curves.easeInOut;

  late final _move = AnimationController(
    vsync: this,
    duration: BusLayer.moveDuration,
    value: 1,
  );
  final _tracks = <String, _Track>{};
  List<_Track> _order = const [];
  // The pills the buses need
  Set<_Sprite> _wanted = const {};
  final _sprites = _PillSprites();
  // Reduced motion
  bool _still = false;
  // Drawing the atlas is safe now (see [_canRasterize])
  bool _foregrounded = _canRasterize(WidgetsBinding.instance.lifecycleState);

  bool get _glides => widget.animate && !_still;

  @override
  void initState() {
    super.initState();
    widget.handle._state = this;
    WidgetsBinding.instance.addObserver(this);
    _apply(widget.buses);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_glides) _jump();
  }

  @override
  void didUpdateWidget(BusLayer old) {
    super.didUpdateWidget(old);
    if (old.handle != widget.handle) {
      old.handle._state = null;
      widget.handle._state = this;
    }
    if (!_glides) _jump();
    // Back on screen: what moved while it was away jumps there
    if (!identical(old.buses, widget.buses)) {
      _apply(widget.buses, glide: old.animate);
    }
  }

  /// A move under way ends where it was going.
  void _jump() {
    if (_move.isAnimating) _move.value = 1;
  }

  /// toImageSync draws into a revoked GPU context while iOS has the app
  /// away, and the atlas comes out magenta (see VectorTileLayer's
  /// workaround). Only `resumed` is safe there; null under flutter test.
  static bool _canRasterize(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed => true,
    AppLifecycleState.inactive =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.iOS,
    _ => false,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final can = _canRasterize(state);
    if (can == _foregrounded) return;
    _foregrounded = can;
    // Back in front: an atlas drawn around the trip away may be magenta
    if (can && mounted) setState(_sprites.invalidate);
  }

  /// World position at zoom 0 (a 256 px world).
  static Offset _world(LatLng p) => _crs.latLngToOffset(p, 0);

  void _apply(List<MapBus> buses, {bool glide = true}) {
    final t = _curve.transform(_move.value);
    // Only a new target starts a move: the page rebuilds once per board,
    // and a move under way to the same places goes on as it is
    final moved = buses.any((bus) {
      final track = _tracks[bus.key];
      if (track == null) return false;
      final to = _world(bus.position);
      return to.dx != track.toX || to.dy != track.toY;
    });
    final next = <String, _Track>{};
    for (final bus in buses) {
      final to = _world(bus.position);
      final track = _tracks[bus.key];
      if (track == null) {
        next[bus.key] = _Track(bus, to.dx, to.dy)..from = bus.position;
        continue;
      }
      if (moved) {
        // Start from where it is drawn now, mid-move included
        final x = t >= 1
            ? track.toX
            : track.fromX + (track.toX - track.fromX) * t;
        final y = t >= 1
            ? track.toY
            : track.fromY + (track.toY - track.fromY) * t;
        track
          ..from = _lerp(track.from, track.bus.position, t)
          ..fromX = x
          ..fromY = y
          ..toX = to.dx
          ..toY = to.dy;
      }
      next[bus.key] = track..bus = bus;
    }
    _tracks
      ..clear()
      ..addAll(next);
    // Lit buses over the unlit ones; south on top, so pills further down
    // the screen overlap the ones above
    _order = _tracks.values.toList()
      ..sort(
        (a, b) => a.bus.live != b.bus.live
            ? (a.bus.live ? 1 : -1)
            : a.toY.compareTo(b.toY),
      );
    _wanted = {for (final t in _order) (t.bus.line, t.bus.live)};
    // A new _order repaints the layer once; a move repaints every frame
    if (!moved) return;
    if (_glides && glide) {
      _move.forward(from: 0);
    } else {
      _move.value = 1;
    }
  }

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );

  MapBus? _hitTest(Offset screen, MapCamera camera) {
    final t = _curve.transform(_move.value);
    final pills = camera.zoom >= Basemap.fmZoom(BusLayer.pillMinStyleZoom);
    MapBus? best;
    var bestDistance = double.infinity;
    for (final track in _order) {
      final p = camera.latLngToScreenOffset(
        _lerp(track.from, track.bus.position, t),
      );
      final d = p - screen;
      if (pills) {
        final size = _sprites.logicalSize((track.bus.line, track.bus.live));
        if (d.dx.abs() > size.width / 2 + 4 ||
            d.dy.abs() > size.height / 2 + 4) {
          continue;
        }
      } else if (d.distance > 14) {
        continue;
      }
      if (d.distance < bestDistance) {
        bestDistance = d.distance;
        best = track.bus;
      }
    }
    return best;
  }

  @override
  void dispose() {
    if (widget.handle._state == this) widget.handle._state = null;
    WidgetsBinding.instance.removeObserver(this);
    _move.dispose();
    _sprites.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_foregrounded) _sprites.ensure(_wanted, dpr);
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BusPainter(
            camera: camera,
            tracks: _order,
            sprites: _sprites,
            move: _move,
            version: _sprites.version,
          ),
        ),
      ),
    );
  }
}

class _BusPainter extends CustomPainter {
  _BusPainter({
    required this.camera,
    required this.tracks,
    required this.sprites,
    required this.move,
    required this.version,
  }) : super(repaint: move);

  final MapCamera camera;
  final List<_Track> tracks;
  final _PillSprites sprites;
  final Animation<double> move;
  final int version;

  static Float32List _transforms = Float32List(0);
  static Float32List _rects = Float32List(0);
  static Float32List _points = Float32List(0);

  static final _dotHalo = Paint()
    ..color = TimbreColors.noche
    ..strokeWidth = 8
    ..strokeCap = StrokeCap.round;
  static final _dot = Paint()
    ..color = TimbreColors.ambar
    ..strokeWidth = 5.5
    ..strokeCap = StrokeCap.round;
  // An estimate: an unlit ring, ink inside
  static final _staleRim = Paint()
    ..color = TimbreColors.etiquetaCartel
    ..strokeWidth = 5.5
    ..strokeCap = StrokeCap.round;
  static final _staleBody = Paint()
    ..color = TimbreColors.tinta
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;
  static final _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    if (tracks.isEmpty) return;
    final t = Curves.easeInOut.transform(move.value);
    final factor = math.pow(2, camera.zoom).toDouble();
    final origin = camera.pixelOrigin;
    final pills = camera.zoom >= Basemap.fmZoom(BusLayer.pillMinStyleZoom);
    const margin = 48.0;
    final right = size.width + margin;
    final bottom = size.height + margin;

    if (!pills) {
      if (_points.length < tracks.length * 2) {
        _points = Float32List(tracks.length * 2);
      }
      // Unlit dots first (tracks are ordered so), then the lit ones
      var n = 0;
      var stale = 0;
      for (final tr in tracks) {
        final x = (tr.fromX + (tr.toX - tr.fromX) * t) * factor - origin.dx;
        final y = (tr.fromY + (tr.toY - tr.fromY) * t) * factor - origin.dy;
        if (x < -margin || y < -margin || x > right || y > bottom) continue;
        _points[n++] = x;
        _points[n++] = y;
        if (!tr.bus.live) stale = n;
      }
      final all = Float32List.sublistView(_points, 0, n);
      canvas.drawRawPoints(ui.PointMode.points, all, _dotHalo);
      final unlit = Float32List.sublistView(_points, 0, stale);
      canvas.drawRawPoints(ui.PointMode.points, unlit, _staleRim);
      canvas.drawRawPoints(ui.PointMode.points, unlit, _staleBody);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_points, stale, n),
        _dot,
      );
      return;
    }

    final atlas = sprites.image;
    if (atlas == null) return;
    if (_transforms.length < tracks.length * 4) {
      _transforms = Float32List(tracks.length * 4);
      _rects = Float32List(tracks.length * 4);
    }
    // Upright pills on a rotated map; sprites are in physical pixels
    final scale = 1 / sprites.pixelRatio;
    final scos = math.cos(-camera.rotationRad) * scale;
    final ssin = math.sin(-camera.rotationRad) * scale;
    var n = 0;
    for (final tr in tracks) {
      final x = (tr.fromX + (tr.toX - tr.fromX) * t) * factor - origin.dx;
      final y = (tr.fromY + (tr.toY - tr.fromY) * t) * factor - origin.dy;
      if (x < -margin || y < -margin || x > right || y > bottom) continue;
      final r = sprites.rect((tr.bus.line, tr.bus.live));
      if (r == null) continue;
      final ax = r.width / 2;
      final ay = r.height / 2;
      _transforms[n] = scos;
      _transforms[n + 1] = ssin;
      _transforms[n + 2] = x - scos * ax + ssin * ay;
      _transforms[n + 3] = y - ssin * ax - scos * ay;
      _rects[n] = r.left;
      _rects[n + 1] = r.top;
      _rects[n + 2] = r.right;
      _rects[n + 3] = r.bottom;
      n += 4;
    }
    if (n == 0) return;
    canvas.drawRawAtlas(
      atlas,
      Float32List.sublistView(_transforms, 0, n),
      Float32List.sublistView(_rects, 0, n),
      null,
      null,
      null,
      _atlasPaint,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_BusPainter old) =>
      old.camera != camera ||
      !identical(old.tracks, tracks) ||
      old.version != version;
}

/// A pill: the line number, lit (GPS, current) or not (an estimate).
typedef _Sprite = (String line, bool live);

/// The bus pills, drawn once per line number and look into one atlas
/// image. Lit like [LineBadge] with GPS: ámbar plate, ink text in the
/// board typography ([TimbreText.lineBadge]) and the pixel bus glyph
/// [PixelGlyphs.bus] in front. Unlit like the timetable badge: an ink
/// plate with an [TimbreColors.etiquetaCartel] rim and text. A
/// [TimbreColors.noche] rim keeps overlapping pills apart.
class _PillSprites {
  static const _height = 22.0;
  static const _rim = 1.5;
  static const _outline = 1.5;
  static const _glyph = 12.0;
  static const _padLeft = 5.0;
  static const _gap = 3.0;
  static const _padRight = 6.0;
  static const _cell = 2.0; // empty pixels around each sprite
  static final _textStyle = TimbreText.lineBadge.copyWith(
    fontSize: 15,
    height: 1,
  );

  ui.Image? image;
  double pixelRatio = 1;
  int version = 0;
  final _rects = <_Sprite, Rect>{};
  final _sizes = <_Sprite, Size>{};

  Rect? rect(_Sprite sprite) => _rects[sprite];

  Size logicalSize(_Sprite sprite) =>
      _sizes[sprite] ?? const Size(40, _height + 2 * _rim);

  static Color _ink(bool live) =>
      live ? TimbreColors.tinta : TimbreColors.etiquetaCartel;

  /// Redraws the atlas when a sprite it lacks shows up or the pixel ratio
  /// changes.
  void ensure(Set<_Sprite> sprites, double dpr) {
    if (sprites.isEmpty && image == null) return;
    if (dpr == pixelRatio &&
        image != null &&
        sprites.every(_rects.containsKey)) {
      return;
    }
    final all = {..._rects.keys, ...sprites}.toList()
      ..sort(
        (a, b) => a.$1 != b.$1
            ? a.$1.compareTo(b.$1)
            : (a.$2 ? 1 : 0) - (b.$2 ? 1 : 0),
      );
    final painters = {
      for (final sprite in all)
        sprite: TextPainter(
          text: TextSpan(
            text: sprite.$1,
            style: _textStyle.copyWith(color: _ink(sprite.$2)),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(),
    };
    // Lay the sprites out in rows of an atlas at most 1024 px wide
    const maxWidth = 1024.0;
    final rects = <_Sprite, Rect>{};
    final sizes = <_Sprite, Size>{};
    var x = 0.0, y = 0.0, rowHeight = 0.0, atlasWidth = 0.0;
    for (final sprite in all) {
      final w = _padLeft + _glyph + _gap + painters[sprite]!.width + _padRight;
      final logical = Size(math.max(w, 34) + 2 * _rim, _height + 2 * _rim);
      final pw = ((logical.width + 2 * _cell) * dpr).ceilToDouble();
      final ph = ((logical.height + 2 * _cell) * dpr).ceilToDouble();
      if (x + pw > maxWidth * dpr && x > 0) {
        x = 0;
        y += rowHeight;
        rowHeight = 0;
      }
      rects[sprite] = Rect.fromLTWH(x, y, pw, ph);
      sizes[sprite] = logical;
      x += pw;
      rowHeight = math.max(rowHeight, ph);
      atlasWidth = math.max(atlasWidth, x);
    }
    final atlasHeight = y + rowHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final sprite in all) {
      final r = rects[sprite]!;
      canvas.save();
      canvas.translate(r.left, r.top);
      canvas.scale(dpr);
      canvas.translate(_cell, _cell);
      _paintPill(canvas, sizes[sprite]!, painters[sprite]!, sprite.$2);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(
      math.max(1, atlasWidth.ceil()),
      math.max(1, atlasHeight.ceil()),
    );
    picture.dispose();
    for (final p in painters.values) {
      p.dispose();
    }

    image?.dispose();
    image = next;
    pixelRatio = dpr;
    _rects
      ..clear()
      ..addAll(rects);
    _sizes
      ..clear()
      ..addAll(sizes);
    version++;
  }

  static void _paintPill(
    Canvas canvas,
    Size size,
    TextPainter text,
    bool live,
  ) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7 + _rim),
    );
    canvas.drawRRect(outer, Paint()..color = TimbreColors.noche);
    final plate = outer.deflate(_rim);
    if (live) {
      canvas.drawRRect(plate, Paint()..color = TimbreColors.ambar);
    } else {
      canvas.drawRRect(plate, Paint()..color = TimbreColors.etiquetaCartel);
      canvas.drawRRect(
        plate.deflate(_outline),
        Paint()..color = TimbreColors.tinta,
      );
    }

    // The pixel bus, like PixelIcon draws it: square pixels, small gaps
    final glyphTop = (size.height - _glyph) / 2;
    final glyphLeft = _rim + _padLeft;
    const p = _glyph / PixelGlyph.size;
    const gap = p * 0.14;
    final path = Path();
    final rows = PixelGlyphs.bus.rows;
    for (var gy = 0; gy < PixelGlyph.size; gy++) {
      for (var gx = 0; gx < PixelGlyph.size; gx++) {
        if (rows[gy].codeUnitAt(gx) != 0x23) continue; // '#'
        path.addRect(
          Rect.fromLTWH(
            glyphLeft + gx * p + gap / 2,
            glyphTop + gy * p + gap / 2,
            p - gap,
            p - gap,
          ),
        );
      }
    }
    canvas.drawPath(path, Paint()..color = _ink(live));

    final textLeft = glyphLeft + _glyph + _gap;
    final textRight = size.width - _rim - _padRight;
    text.paint(
      canvas,
      Offset(
        textLeft + (textRight - textLeft - text.width) / 2,
        (size.height - text.height) / 2,
      ),
    );
  }

  /// Drops the atlas: the next [ensure] draws it again.
  void invalidate() {
    image?.dispose();
    image = null;
    _rects.clear();
    _sizes.clear();
    version++;
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}
