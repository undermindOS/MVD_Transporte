import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../models/arrivals_board.dart';
import '../../models/bus_stop.dart';
import '../../services/api/api_result.dart';
import '../../services/cache_service.dart';
import '../../services/map/basemap.dart';
import '../../services/mvd_api_service.dart';
import '../../services/official_sites.dart';
import '../../services/stop_locations_service.dart';
import '../stops_page.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/pixel_icon.dart';
import 'bus_layer.dart';
import 'map_buses.dart';
import 'map_sheets.dart';

/// Loads what the Mapa draws under its markers.
typedef MapaBasemapLoader = Future<MapaBasemap> Function();

/// What the Mapa needs of its basemap. In the app it wraps the bundled
/// [Basemap] ([bundled]); a widget test passes one with no tile layer, so
/// no archive is copied and no tile is read or decoded (worker isolates,
/// file reads) inside the fake-async zone.
class MapaBasemap {
  MapaBasemap({
    required this.bounds,
    required this.attribution,
    this.layer,
    VoidCallback? onDispose,
  }) : _onDispose = onDispose;

  /// [Basemap.load]: the extract bundled in the app.
  static Future<MapaBasemap> bundled() async {
    final basemap = await Basemap.load();
    return MapaBasemap(
      bounds: basemap.bounds,
      attribution: basemap.attribution,
      layer: basemap.layer,
      onDispose: basemap.dispose,
    );
  }

  /// Where there are tiles: the camera's center and the buses stay
  /// inside. Not to be changed (LatLngBounds is mutable).
  final LatLngBounds bounds;

  /// '© OpenStreetMap', always in sight on the map (ODbL).
  final String attribution;

  /// The tile layer; null draws no tiles.
  final Widget Function()? layer;

  final VoidCallback? _onDispose;

  /// Call once the map that uses it is gone.
  void dispose() => _onDispose?.call();
}

/// The Mapa tab: the saved stops on the bundled basemap and the GPS buses
/// on their way to them.
///
/// Nothing is loaded before it is first [active]: no basemap, no request.
/// Without saved stops it shows an empty sign and loads nothing. The
/// arrivals come from the same /v1 boards as Mis paradas
/// ([MvdApiService.latestBoards]), polled every 30 s while it is on
/// screen; the phone's location is never used.
class MapaPage extends StatefulWidget {
  const MapaPage({
    super.key,
    this.active = true,
    this.basemapLoader = _defaultLoader,
  });

  /// The Mapa is on screen: its tab is selected, no page covers it and the
  /// app is not locked. Boards are polled only then; becoming active
  /// refreshes them unless they are fresh.
  final bool active;

  /// Tests pass a basemap without tiles.
  @visibleForTesting
  final MapaBasemapLoader basemapLoader;

  /// The loader of a page built without one, as the app's is: tests of the
  /// whole app set a basemap without tiles (the bundled style is read in a
  /// worker isolate, which never answers inside fake async).
  @visibleForTesting
  static MapaBasemapLoader defaultBasemapLoader = MapaBasemap.bundled;

  static Future<MapaBasemap> _defaultLoader() => defaultBasemapLoader();

  /// The phone's clock, against the boards' `fetchedAt`. Tests move it.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Where the camera starts before the saved stops are placed: centro.
  static const centro = LatLng(-34.9058, -56.1913);

  static final _copyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> with WidgetsBindingObserver {
  // Without a Retry-After
  static const _busyDefault = Duration(seconds: 60);

  List<BusStop> _stops = const [];

  MapaBasemap? _basemap;
  // The one load in flight; a new one starts only after a failure
  Future<void>? _loading;
  bool _basemapFailed = false;

  // null while not polling: app in the background or page not on screen
  Timer? _timer;
  bool _refreshing = false;
  // The app is hidden or paused
  bool _inBackground = false;
  // After a busy answer (429), ticks are skipped until then
  DateTime? _skipTicksUntil;

  // Stops whose latest refresh failed: their buses are estimates
  final _failed = <int>{};
  // The latest refresh brought no board at all
  bool _refreshFailed = false;
  // The boards last seen in MvdApiService.latestBoards
  Map<int, ArrivalsBoard> _seen = const {};

  // Saved stops StopLocationsService.fillMissing has answered for, and
  // those it is looking up now: only the first can be "not placed"
  final _lookedUp = <int>{};
  final _lookingUp = <int>{};

  // Rebuilds an open sheet with the page
  final _sheet = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seen = MvdApiService.latestBoards.value;
    MvdApiService.latestBoards.addListener(_onBoards);
    _stops = CacheService.getAllStops();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(MapaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _resume();
    } else {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MvdApiService.latestBoards.removeListener(_onBoards);
    _timer?.cancel();
    // The map and its tile layer are unmounted by now
    _basemap?.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Back from the background (not from a system dialog, which only
        // makes the app inactive)
        if (_inBackground) {
          _inBackground = false;
          // After the next frame: when the app locks on its way back, that
          // frame turns this page inactive first, and nothing is requested
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (mounted) setState(_resume);
          });
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _inBackground = true;
        _stopPolling();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // Decoded tiles and label text outlive the layer, process-wide
  @override
  void didHaveMemoryPressure() => Basemap.clearMemoryCache();

  /// setState, and an open sheet follows.
  void _changed(VoidCallback fn) {
    setState(fn);
    _sheet.value++;
  }

  /// On screen again: the saved stops read again (Mis paradas may have
  /// changed them), then [_start]. The caller rebuilds.
  void _resume() {
    if (!widget.active || _inBackground || _timer != null) return;
    _stops = CacheService.getAllStops();
    _start();
  }

  /// Places the stops, draws what [MvdApiService.latestBoards] has, asks
  /// for the boards unless they are fresh, then every 30 s.
  void _start() {
    if (_stops.isEmpty) return;
    _loadBasemap();
    _locate();
    _refresh(unlessFresh: true);
    _timer?.cancel();
    _timer = Timer.periodic(StopsPage.autoRefreshInterval, (_) {
      // Busy (429): wait out the Retry-After, without a word
      final skipUntil = _skipTicksUntil;
      if (skipUntil != null && DateTime.now().isBefore(skipUntil)) return;
      _refresh();
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _loadBasemap() {
    if (_basemap != null || _loading != null || _basemapFailed) return;
    _loading = _openBasemap();
  }

  Future<void> _openBasemap() async {
    try {
      final basemap = await widget.basemapLoader();
      if (!mounted) {
        basemap.dispose();
        return;
      }
      setState(() => _basemap = basemap);
    } catch (e) {
      // Not the error text: it can hold a file path
      debugPrint('⚠️ Basemap error: ${e.runtimeType}');
      if (mounted) setState(() => _basemapFailed = true);
    } finally {
      _loading = null;
    }
  }

  void _retryBasemap() {
    setState(() => _basemapFailed = false);
    _loadBasemap();
  }

  /// Saved stops with no location get one; the map follows.
  void _locate() {
    // One still looked up by an earlier call is skipped by this one
    final asked = {
      for (final s in _stops)
        if (!s.hasLocation && !_lookingUp.contains(s.id)) s.id,
    };
    _lookingUp.addAll(asked);
    StopLocationsService.fillMissing(_stops).then((filled) {
      _lookingUp.removeAll(asked);
      if (!mounted) return;
      _changed(() {
        _lookedUp.addAll(asked);
        if (filled > 0) _stops = CacheService.getAllStops();
      });
    });
  }

  /// A new board, from this page or from Mis paradas: its stop is current
  /// again.
  void _onBoards() {
    final boards = MvdApiService.latestBoards.value;
    var fresh = false;
    for (final stop in _stops) {
      final board = boards[stop.id];
      if (board != null && !identical(board, _seen[stop.id])) {
        _failed.remove(stop.id);
        fresh = true;
      }
    }
    _seen = boards;
    if (fresh) _refreshFailed = false;
    if (mounted && widget.active) _changed(() {});
  }

  /// Every saved stop has a board fetched within the refresh interval,
  /// e.g. right after Mis paradas refreshed.
  bool _fresh(Set<int> ids) {
    final boards = MvdApiService.latestBoards.value;
    final now = MapaPage.clock();
    return ids.every((id) {
      final board = boards[id];
      if (board == null) return false;
      final age = now.difference(board.fetchedAt);
      return !age.isNegative && age < StopsPage.autoRefreshInterval;
    });
  }

  /// The boards of the saved stops, each once and all in parallel.
  Future<void> _refresh({bool unlessFresh = false}) async {
    final ids = {for (final s in _stops) s.id};
    // Slow network: don't pile up requests
    if (_refreshing || ids.isEmpty) return;
    if (unlessFresh && _fresh(ids)) return;
    _refreshing = true;
    try {
      final results = await MvdApiService.getBoards(ids);
      Duration? busyFor;
      var good = false;
      var failed = false;
      results.forEach((id, result) {
        switch (result) {
          case ApiOk():
            good = true;
            _failed.remove(id);
          case ApiError(failure: ApiFailure.busy, :final retryAfter):
            final wait = retryAfter ?? _busyDefault;
            if (busyFor == null || wait > busyFor!) busyFor = wait;
          // A stop that no longer exists: Mis paradas says so
          case ApiError(failure: ApiFailure.notFound):
            break;
          case ApiError():
            failed = true;
            _failed.add(id);
        }
      });
      if (busyFor != null) _skipTicksUntil = DateTime.now().add(busyFor!);
      if (!mounted) return;
      _changed(() {
        if (good) {
          _refreshFailed = false;
        } else if (failed) {
          _refreshFailed = true;
        }
      });
    } finally {
      _refreshing = false;
    }
  }

  List<MapBus> _buses() {
    final basemap = _basemap;
    if (basemap == null) return const [];
    return MapBuses.from(
      stopIds: _stops.map((s) => s.id),
      boards: MvdApiService.latestBoards.value,
      failed: _failed,
      bounds: basemap.bounds,
      now: MapaPage.clock(),
    );
  }

  void _showBus(MapBus tapped) {
    var last = tapped;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _sheet,
        builder: (context, _, _) {
          // The same bus after a refresh. Once no board has it, the last
          // seen as an estimate: old minutes must not look live
          MapBus? current;
          for (final bus in _buses()) {
            if (bus.key == tapped.key) current = bus;
          }
          if (current != null) last = current;
          return BusSheet(
            bus: current ?? last.estimate,
            stops: {for (final s in _stops) s.id: s},
          );
        },
      ),
    );
  }

  void _showStop(BusStop stop) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _sheet,
        builder: (context, _, _) => StopSheet(
          stop: stop,
          board: MvdApiService.latestBoards.value[stop.id],
          failed: _failed.contains(stop.id) || _refreshFailed,
          now: MapaPage.clock(),
        ),
      ),
    );
  }

  Future<void> _openCopyright() async {
    final opened = await SystemBrowser.open(MapaPage._copyright);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el navegador. Revisá que tengas uno activado.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stops.isEmpty) return const _NoStops();
    final basemap = _basemap;
    if (basemap == null) {
      return _basemapFailed
          ? _BasemapFailed(onRetry: _retryBasemap)
          : const _Loading();
    }

    final now = MapaPage.clock();
    final buses = _buses();
    final located = _stops.where((s) => s.hasLocation).toList();
    final unlocated = _stops
        .where((s) => !s.hasLocation && _lookedUp.contains(s.id))
        .toList();
    final boards = MvdApiService.latestBoards.value;
    final liveness = {
      for (final s in located)
        s.id: MapBuses.liveness(
          boards[s.id],
          failed: _failed.contains(s.id),
          now: now,
        ),
    };
    final known = _stops.any((s) {
      final board = boards[s.id];
      return board != null &&
          now.difference(board.fetchedAt) < MapBuses.staleFor;
    });
    final notes = <Widget>[
      if (_refreshFailed)
        _FailedBanner(onRetry: _refresh)
      else if (located.isNotEmpty && buses.isEmpty && known)
        const _MapNote(
          icon: PixelGlyphs.bus,
          text: 'Ahora ningún ómnibus con GPS viene a tus paradas.',
        ),
      if (unlocated.isNotEmpty)
        _MapNote(
          icon: PixelGlyphs.stop,
          text: unlocated.length == 1
              ? 'No se pudo ubicar en el mapa la parada '
                    '${unlocated.single.id}.'
              : 'No se pudieron ubicar en el mapa '
                    '${unlocated.length} paradas.',
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: _MapaView(
            basemap: basemap,
            located: located,
            liveness: liveness,
            buses: buses,
            animate: widget.active,
            onStop: _showStop,
            onBus: _showBus,
          ),
        ),
        if (notes.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(TimbreSpace.s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: TimbreSpace.xs,
                  children: notes,
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            right: false,
            child: _Attribution(
              text: basemap.attribution,
              onTap: _openCopyright,
            ),
          ),
        ),
      ],
    );
  }
}

/// The map itself, built once the basemap is there: tiles, the saved stops
/// and the buses. It owns its controller and options, so they are made
/// once and dropped with it.
class _MapaView extends StatefulWidget {
  const _MapaView({
    required this.basemap,
    required this.located,
    required this.liveness,
    required this.buses,
    required this.animate,
    required this.onStop,
    required this.onBus,
  });

  final MapaBasemap basemap;

  /// The saved stops with a location.
  final List<BusStop> located;

  /// [MapBuses.liveness] of each located stop's board, by stop id.
  final Map<int, bool?> liveness;
  final List<MapBus> buses;
  final bool animate;
  final ValueChanged<BusStop> onStop;
  final ValueChanged<MapBus> onBus;

  @override
  State<_MapaView> createState() => _MapaViewState();
}

class _MapaViewState extends State<_MapaView> {
  final _map = MapController();
  final _handle = BusLayerHandle();
  // Kept across rebuilds: the map asserts on a changed camera constraint
  late final MapOptions _options;
  // The camera was fitted to the saved stops once
  late bool _fitted;
  bool _ready = false;

  static List<LatLng> _points(List<BusStop> stops) => [
    for (final s in stops) LatLng(s.latitude, s.longitude),
  ];

  static CameraFit _fit(List<BusStop> stops) => CameraFit.coordinates(
    coordinates: _points(stops),
    padding: const EdgeInsets.all(48),
    maxZoom: Basemap.fmZoom(16),
  );

  @override
  void initState() {
    super.initState();
    _fitted = widget.located.isNotEmpty;
    _options = MapOptions(
      initialCenter: MapaPage.centro,
      initialZoom: Basemap.fmZoom(14),
      initialCameraFit: _fitted ? _fit(widget.located) : null,
      minZoom: Basemap.fmZoom(10),
      maxZoom: Basemap.fmZoom(18),
      cameraConstraint: CameraConstraint.containCenter(
        bounds: widget.basemap.bounds,
      ),
      // No rotation: stop markers and pills stay upright
      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
      backgroundColor: TimbreColors.noche,
      onTap: _onTap,
      onMapReady: () {
        _ready = true;
        _fitOnce();
      },
    );
  }

  @override
  void didUpdateWidget(_MapaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_fitted && widget.located.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitOnce();
      });
    }
  }

  /// The first stops placed after the map opened: the camera goes to them.
  void _fitOnce() {
    if (_fitted || !_ready || widget.located.isEmpty) return;
    _fitted = true;
    _map.fitCamera(_fit(widget.located));
  }

  void _onTap(TapPosition position, LatLng _) {
    final bus = _handle.hitTest(
      position.relative ?? position.global,
      _map.camera,
    );
    if (bus != null) widget.onBus(bus);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = widget.basemap.layer;
    return FlutterMap(
      mapController: _map,
      options: _options,
      children: [
        ?layer?.call(),
        MarkerLayer(
          markers: [
            for (final stop in widget.located)
              Marker(
                point: LatLng(stop.latitude, stop.longitude),
                width: TimbreSpace.touch,
                height: TimbreSpace.touch,
                child: _StopMarker(
                  stop: stop,
                  live: widget.liveness[stop.id],
                  buses: widget.buses
                      .where((b) => b.etas.any((e) => e.stopId == stop.id))
                      .length,
                  onTap: () => widget.onStop(stop),
                ),
              ),
          ],
        ),
        BusLayer(buses: widget.buses, handle: _handle, animate: widget.animate),
      ],
    );
  }
}

/// A saved stop: the pixel stop sign on an ink tile, unlit (ámbar is for
/// the buses), in a 44 px target. Screen readers hear the stop and how
/// many GPS buses are on their way, since the buses are paint only: as
/// estimates when they are drawn unlit, nothing when no board is known.
class _StopMarker extends StatelessWidget {
  const _StopMarker({
    required this.stop,
    required this.live,
    required this.buses,
    required this.onTap,
  });

  final BusStop stop;

  /// [MapBuses.liveness] of its board.
  final bool? live;

  /// The buses drawn on their way to it.
  final int buses;
  final VoidCallback onTap;

  /// The tile is drawn smaller than its touch target.
  static const _tile = 26.0;

  /// Between [TimbreIconSize.mark] and [TimbreIconSize.row]: fits the tile.
  static const _glyph = 16.0;

  String get _phrase {
    final coming = switch ((live, buses)) {
      // Unknown, or only old minutes: "no buses" is not known either
      (null, _) || (false, 0) => null,
      (false, _) => '$buses ómnibus en camino, estimado',
      (true, 0) => 'sin ómnibus con GPS en camino',
      (true, _) => '$buses ómnibus con GPS en camino',
    };
    return coming == null ? stopPhrase(stop) : '${stopPhrase(stop)}, $coming';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: _phrase,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: SizedBox.square(
            dimension: _tile,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TimbreColors.tinta,
                borderRadius: BorderRadius.circular(TimbreRadii.chip),
                border: Border.all(
                  color: TimbreColors.etiquetaCartel,
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: PixelIcon(
                  PixelGlyphs.stop,
                  size: _glyph,
                  color: TimbreColors.papel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// '© OpenStreetMap' in a corner, always in sight; it opens the copyright
/// page in the system browser.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      link: true,
      label: text,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // A 44 px target around the small label
          constraints: const BoxConstraints(
            minHeight: TimbreSpace.touch,
            minWidth: TimbreSpace.touch,
          ),
          alignment: Alignment.bottomLeft,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: TimbreColors.noche,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(TimbreRadii.chip),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(text, style: TimbreText.caption),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note over the map, on an ink panel so it reads over any tile.
class _MapNote extends StatelessWidget {
  const _MapNote({required this.icon, required this.text});

  final PixelGlyph icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TimbreColors.tinta,
        border: Border.all(color: TimbreColors.lineaNoche),
        borderRadius: BorderRadius.circular(TimbreRadii.control),
      ),
      child: Row(
        children: [
          PixelIcon(icon, size: TimbreIconSize.row, color: TimbreColors.tenue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TimbreText.subtitle.copyWith(color: TimbreColors.tenue),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failed refresh over the map, which stays in sight with the last buses
/// unlit: the avisoNoche panel. No pull to refresh on a map, so a button.
class _FailedBanner extends StatelessWidget {
  const _FailedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      'No se pudo actualizar. Revisá la conexión.',
      style: TimbreText.subtitle.copyWith(
        color: TimbreColors.ambar,
        fontWeight: FontWeight.w600,
      ),
    );
    final retry = TextButton(
      onPressed: onRetry,
      child: const Text('Reintentar'),
    );
    const warning = PixelIcon(
      PixelGlyphs.warning,
      size: TimbreIconSize.row,
      color: TimbreColors.ambar,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: TimbreColors.avisoNoche,
        border: Border.all(color: TimbreColors.ambarTenue),
        borderRadius: BorderRadius.circular(TimbreRadii.control),
      ),
      // With large fonts the button goes under the text, so neither is cut
      child: TimbreText.isLarge(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Row(
                    children: [
                      warning,
                      const SizedBox(width: 10),
                      Expanded(child: text),
                    ],
                  ),
                ),
                Align(alignment: Alignment.centerRight, child: retry),
              ],
            )
          : Row(
              children: [
                warning,
                const SizedBox(width: 10),
                Expanded(child: text),
                retry,
              ],
            ),
    );
  }
}

/// No saved stops: a sign with nothing to announce, scrollable so the
/// largest fonts still fit.
class _NoStops extends StatelessWidget {
  const _NoStops();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: TimbreEmptyState(
              'Sin paradas guardadas',
              sign: 'SIN PARADAS',
              detail:
                  'Agregá una parada en Mis paradas para ver acá los '
                  'ómnibus con GPS que se acercan.',
            ),
          ),
        ),
      ),
    );
  }
}

/// The basemap opening: a progress ring, no text.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// The basemap could not be opened: a red LED, never the error text.
class _BasemapFailed extends StatelessWidget {
  const _BasemapFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(TimbreSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PixelIcon(
                    PixelGlyphs.warning,
                    size: TimbreIconSize.rowLarge,
                    color: TimbreColors.rojoLed,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No se pudo abrir el mapa. Probá de nuevo.',
                    textAlign: TextAlign.center,
                    style: TimbreText.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
