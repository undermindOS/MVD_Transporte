import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/alert_schedule.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/bus_wait.dart';
import '../models/catalog_stop.dart';
import '../models/nearby_stop.dart';
import '../models/route_alert.dart';
import '../models/transport_news.dart';
import '../services/background_worker.dart';
import '../services/bus_status_service.dart';
import '../services/bus_wait_service.dart';
import '../services/cache_service.dart';
import '../services/mvd_api_service.dart';
import '../services/nearby_stops_service.dart';
import '../services/notification_service.dart';
import '../services/transport_news_service.dart';
import 'news_list.dart';
import 'schedule_page.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/arrival_row.dart';
import 'widgets/cartel.dart';
import 'widgets/empty_state.dart';
import 'widgets/pixel_icon.dart';
import 'widgets/segmented.dart';

class StopsPage extends StatefulWidget {
  /// Opens the stop in Cómo Ir (official deep link).
  final ValueChanged<int> onOpenStopInComoIr;

  const StopsPage({super.key, required this.onOpenStopInComoIr});

  /// Arrival times go stale within a minute: refresh this often while the
  /// app is in the foreground.
  static const autoRefreshInterval = Duration(seconds: 30);

  @override
  State<StopsPage> createState() => _StopsPageState();
}

class _StopsPageState extends State<StopsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  // null while the app is in the background
  Timer? _autoRefreshTimer;
  bool _autoRefreshing = false;

  // --- Stops ---
  List<BusStop> _stops = [];
  // null value = last request failed (network/server error)
  final Map<int, List<BusArrival>?> _stopArrivals = {};
  final Map<int, bool> _stopLoading = {};

  // --- Routes ---
  List<RouteAlert> _routes = [];
  // key: routeId → arrivals filtered by preferred lines (null = failed)
  final Map<int, List<BusArrival>?> _routeArrivals = {};
  final Map<int, bool> _routeLoading = {};

  // GPS data quality per operator (null = unknown)
  List<OperatorGpsStatus>? _gpsStatus;

  // --- News ---
  static const _newsTab = 2;
  int _shownTab = 0;
  List<TransportNews> _news = [];
  bool _newsLoading = false;
  bool _newsFailed = false;
  // Ids above this were unread when the news tab was opened (highlighted)
  int? _newsReadBefore;

  // Cards showing all their buses ("s574" stop, "r3" route)
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Rebuild so the FAB tooltip follows the selected tab
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      // Swipes also notify (offset changes) without changing the tab
      if (_tabController.index != _shownTab) {
        _shownTab = _tabController.index;
        if (_shownTab == _newsTab) {
          _newsReadBefore = TransportNewsService.lastReadId;
          _markNewsRead();
        }
      }
      setState(() {});
    });
    _loadAll();
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    BusWaitService.current.addListener(_onWaitChanged);
  }

  @override
  void dispose() {
    BusWaitService.current.removeListener(_onWaitChanged);
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Back from the background (not from a system dialog, which only
        // makes the app inactive): what is on screen may be minutes old
        if (_autoRefreshTimer == null) {
          BusWaitService.sync();
          _autoRefresh();
          _startAutoRefresh();
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _autoRefreshTimer?.cancel();
        _autoRefreshTimer = null;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onWaitChanged() {
    if (mounted) setState(() {});
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(StopsPage.autoRefreshInterval, (_) => _autoRefresh());
  }

  /// Refreshes stops and routes without spinners, so the chips do not
  /// flicker. A stop that is also a route origin is requested once.
  Future<void> _autoRefresh() async {
    if (_autoRefreshing) return; // slow network: don't pile up requests
    _autoRefreshing = true;
    _loadGpsStatus();
    final ids = {
      ..._stops.map((s) => s.id),
      ..._routes.map((r) => r.originStopId),
    };
    final results = <int, List<BusArrival>?>{};
    await Future.wait(ids.map((id) async =>
        results[id] = await MvdApiService.getNextArrivals(id)));
    _autoRefreshing = false;
    results.forEach(BusWaitService.onArrivals);
    if (!mounted) return;
    // Stops added meanwhile are loaded by _loadStops/_loadRoutes
    setState(() {
      for (final s in _stops) {
        if (results.containsKey(s.id)) _stopArrivals[s.id] = results[s.id];
      }
      for (final r in _routes) {
        if (!results.containsKey(r.originStopId)) continue;
        _routeArrivals[r.id] =
            results[r.originStopId]?.where(r.accepts).toList();
      }
    });
  }

  void _loadAll() {
    _loadStops();
    _loadRoutes();
    _loadNews();
    _loadGpsStatus();
  }

  /// Rate-limited inside the service (once a minute at most).
  Future<void> _loadGpsStatus() async {
    final status = await BusStatusService.getStatus();
    if (mounted) setState(() => _gpsStatus = status);
  }

  /// Keeps notification permission and the background task in step with
  /// alert changes (previously the task was registered only at app start).
  Future<void> _syncAlerts({bool enabling = false}) async {
    if (enabling) await NotificationService.requestPermissions();
    await BackgroundWorker.sync();
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const PixelIcon(PixelGlyphs.warning,
            size: 18, color: TimbreColors.rojoLed),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
  }

  // ---------------------------------------------------------------- Stops ---

  void _loadStops() {
    setState(() => _stops = CacheService.getAllStops());
    for (final s in _stops) {
      _refreshStopArrivals(s.id);
    }
  }

  Future<void> _refreshStopArrivals(int stopId) async {
    setState(() => _stopLoading[stopId] = true);
    final arrivals = await MvdApiService.getNextArrivals(stopId);
    BusWaitService.onArrivals(stopId, arrivals);
    if (mounted) {
      setState(() {
        _stopArrivals[stopId] = arrivals;
        _stopLoading[stopId] = false;
      });
    }
  }

  Future<void> _addStop() async {
    final stopId = await _showAddStopDialog();
    if (stopId == null || !mounted) return;

    // Re-adding would overwrite the saved alert settings
    if (CacheService.getStop(stopId) != null) {
      _showError('La parada $stopId ya está guardada');
      return;
    }

    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(const SnackBar(content: Text('Buscando parada…')));

    final BusStop? resolved;
    try {
      resolved = await MvdApiService.resolveStop(stopId);
    } on StopNotFoundException {
      _showError('No existe la parada $stopId');
      return;
    }
    // Offline: keep the stop with a placeholder name
    final stop = resolved ?? BusStop(id: stopId, name: 'Parada $stopId');
    await CacheService.saveStop(stop);

    if (mounted) {
      snack.clearSnackBars();
      _loadStops();
    }
  }

  Future<int?> _showAddStopDialog() => showDialog<int>(
        context: context,
        builder: (_) => const _AddStopDialog(),
      );

  Future<void> _toggleStopNotification(BusStop stop) async {
    stop.notificationsEnabled = !stop.notificationsEnabled;
    await stop.save();
    setState(() {});
    await _syncAlerts(enabling: stop.notificationsEnabled);
  }

  Future<void> _editStopAlert(BusStop stop) async {
    final settings = await _showAlertSettings(
        stop.name, stop.etaAlertMinutes, stop.schedule);
    if (settings == null || !mounted) return;
    final (minutes, schedule) = settings;
    setState(() => stop
      ..etaAlertMinutes = minutes
      ..schedule = schedule);
    await stop.save();
  }

  void _deleteStop(BusStop stop) {
    // Dismissible requires the item to leave the list synchronously
    setState(() {
      _stops.removeWhere((s) => s.id == stop.id);
      _stopArrivals.remove(stop.id);
    });
    CacheService.deleteStop(stop.id).then((_) => _syncAlerts());
  }

  // ---------------------------------------------------------------- Routes --

  void _loadRoutes() {
    setState(() => _routes = CacheService.getAllRoutes());
    for (final r in _routes) {
      _refreshRouteArrivals(r);
    }
  }

  Future<void> _refreshRouteArrivals(RouteAlert route) async {
    setState(() => _routeLoading[route.id] = true);
    final all = await MvdApiService.getNextArrivals(route.originStopId);
    BusWaitService.onArrivals(route.originStopId, all);
    final filtered = all?.where(route.accepts).toList();

    if (mounted) {
      setState(() {
        _routeArrivals[route.id] = filtered;
        _routeLoading[route.id] = false;
      });
    }
  }

  Future<void> _addRouteManually() async {
    final result = await _showAddRouteDialog();
    if (result == null || !mounted) return;

    final snack = ScaffoldMessenger.of(context);
    // Already resolved if the dialog listed the stop's lines
    var resolved = result.origin;
    if (resolved == null) {
      snack.showSnackBar(const SnackBar(content: Text('Buscando parada…')));
      try {
        resolved = await MvdApiService.resolveStop(result.originStopId);
      } on StopNotFoundException {
        _showError('No existe la parada ${result.originStopId}');
        return;
      }
    }
    final id = CacheService.nextRouteId();
    final route = RouteAlert(
      id: id,
      originStopId: result.originStopId,
      originName: resolved?.name ?? 'Parada ${result.originStopId}',
      destinationName: result.destinationName,
      preferredLines: result.preferredLines,
      preferredDestinations: result.preferredDestinations,
    );
    await CacheService.saveRoute(route);

    if (mounted) {
      snack.clearSnackBars();
      _loadRoutes();
      await _syncAlerts(enabling: true);
    }
  }

  Future<_RouteFormData?> _showAddRouteDialog() => showDialog<_RouteFormData>(
        context: context,
        builder: (_) => const _AddRouteDialog(),
      );

  Future<void> _toggleRouteEnabled(RouteAlert route) async {
    route.enabled = !route.enabled;
    await route.save();
    setState(() {});
    await _syncAlerts(enabling: route.enabled);
  }

  Future<void> _editRouteAlert(RouteAlert route) async {
    final settings = await _showAlertSettings(
        '${route.originName} → ${route.destinationName}',
        route.alertMinutes,
        route.schedule);
    if (settings == null || !mounted) return;
    final (minutes, schedule) = settings;
    setState(() => route
      ..alertMinutes = minutes
      ..schedule = schedule);
    await route.save();
  }

  // ------------------------------------------------------- Alert settings --

  /// Threshold and schedule of a stop or route alert.
  Future<(int, AlertSchedule)?> _showAlertSettings(
          String title, int minutes, AlertSchedule schedule) =>
      showModalBottomSheet<(int, AlertSchedule)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AlertSettingsSheet(
            title: title, minutes: minutes, schedule: schedule),
      );

  void _deleteRoute(RouteAlert route) {
    // Dismissible requires the item to leave the list synchronously
    setState(() {
      _routes.removeWhere((r) => r.id == route.id);
      _routeArrivals.remove(route.id);
    });
    CacheService.deleteRoute(route.id).then((_) => _syncAlerts());
  }

  // ---------------------------------------------------------------- News ----

  Future<void> _loadNews({bool force = false}) async {
    setState(() {
      if (_news.isEmpty) _news = TransportNewsService.cached();
      _newsLoading = true;
    });
    final fresh = await TransportNewsService.refresh(force: force);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _news = fresh;
      _newsFailed = fresh == null;
      _newsLoading = false;
    });
    if (_tabController.index == _newsTab) _markNewsRead();
  }

  Future<void> _markNewsRead() async {
    await TransportNewsService.markRead(_news);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------ Estoy esperando --

  /// Tap on an arrival chip: follow that trip and notify when it is close.
  Future<void> _showWaitSheet(int stopId, String stopName, BusArrival trip,
      {required bool waiting}) async {
    var alertMinutes = 5;
    // Minutes before arrival to notify; -1 = stop waiting
    final choice = await showModalBottomSheet<int>(
      context: context,
      // Grows with large system fonts and scrolls when taller than the screen
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The bus being followed, as the sign at the stop would
                // show it; a timetable trip has no sign, only words
                if (trip.isRealTime)
                  CartelTira(
                    line: trip.line,
                    destination: trip.destination,
                    etaMinutes: trip.etaMinutes,
                  )
                else
                  Text(
                    trip.destination.isEmpty
                        ? 'Línea ${trip.line}'
                        : '${trip.line} → ${trip.destination}',
                    style: TimbreText.destination.copyWith(fontSize: 20),
                  ),
                const SizedBox(height: 8),
                Text(
                  trip.isRealTime
                      ? '$stopName · con GPS'
                      : 'Según horario ${trip.etaLabel}, sin GPS todavía · '
                          '$stopName',
                  style: TimbreText.subtitle,
                ),
                const SizedBox(height: 18),
                if (waiting)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, -1),
                    icon: const PixelIcon(PixelGlyphs.bell, size: 20),
                    label: const Text('Dejar de esperar'),
                  )
                else ...[
                  Text('Avisarme cuando falten',
                      style: TimbreText.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TimbreSegmented<int>(
                    values: const [3, 5, 10],
                    selected: alertMinutes,
                    labelOf: (m) => '$m min',
                    semanticLabel: 'Minutos antes de que llegue',
                    onChanged: (m) => setSheet(() => alertMinutes = m),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, alertMinutes),
                    icon: const PixelIcon(PixelGlyphs.bellRing, size: 20),
                    label: const Text('Avisarme cuando llegue'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    defaultTargetPlatform == TargetPlatform.android
                        ? 'Verás un aviso fijo mientras la app sigue al '
                            'ómnibus, también con la pantalla apagada. '
                            'Avisa cuando el ómnibus tiene GPS.'
                        : 'Te avisamos a la hora estimada. Si abrís la app '
                            'mientras esperás, el aviso se ajusta al GPS.',
                    style: TimbreText.caption.copyWith(height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice < 0) {
      await BusWaitService.stop();
      return;
    }

    final wait = BusWait.forTrip(
      stopId: stopId,
      stopName: stopName,
      trip: trip,
      alertMinutes: choice,
      now: DateTime.now(),
    );
    final started = await BusWaitService.start(wait, trip);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (started) {
      case WaitStart.started:
        messenger.showSnackBar(SnackBar(
            content:
                Text('Te avisamos cuando el ${trip.line} esté a $choice min')));
      case WaitStart.alreadyClose:
        messenger.showSnackBar(SnackBar(
            content: Text(
                'El ${trip.line} ya está a ${trip.etaMinutes} min')));
      case WaitStart.failed:
        _showError('No se pudo activar el aviso');
    }
  }

  // ---------------------------------------------------------------- Build ---

  @override
  Widget build(BuildContext context) {
    final unread = TransportNewsService.unreadCount(_news);
    final largeText = TimbreText.isLarge(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          // With large text the labels keep their full width and the bar
          // scrolls sideways
          isScrollable: largeText,
          tabAlignment: largeText ? TabAlignment.start : null,
          tabs: [
            const Tab(
                icon: PixelIcon(PixelGlyphs.stop, size: 22), text: 'Paradas'),
            const Tab(
                icon: PixelIcon(PixelGlyphs.route, size: 22), text: 'Rutas'),
            Tab(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const PixelIcon(PixelGlyphs.news, size: 22),
              ),
              text: 'Novedades',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStopsTab(),
          _buildRoutesTab(),
          NewsList(
            news: _news,
            readBefore: _newsReadBefore,
            isLoading: _newsLoading,
            failed: _newsFailed,
            onRefresh: () => _loadNews(force: true),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == _newsTab
          ? null
          : FloatingActionButton(
              onPressed: () => _tabController.index == 0
                  ? _addStop()
                  : _addRouteManually(),
              tooltip: _tabController.index == 0
                  ? 'Agregar parada'
                  : 'Agregar ruta',
              child: const PixelIcon(PixelGlyphs.plus, size: 26),
            ),
    );
  }

  // --------------------------------------------------------- Stops tab -----

  Widget _buildStopsTab() {
    if (_stops.isEmpty) {
      return const _EmptyTab(
        message: 'Sin paradas guardadas',
        sign: 'SIN PARADAS',
        detail: 'Tocá + para agregar una parada y recibir un aviso cuando '
            'llegue el ómnibus.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _loadGpsStatus();
        for (final s in _stops) {
          await _refreshStopArrivals(s.id);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 96),
        itemCount: _stops.length + 1,
        itemBuilder: (_, i) =>
            i == 0 ? _buildGpsWarning() : _buildStopCard(_stops[i - 1]),
      ),
    );
  }

  /// A saved stop as a small board: name and number, the timetable and the
  /// alert, then its next buses.
  Widget _buildStopCard(BusStop stop) {
    final arrivals = _stopArrivals[stop.id];
    final failed = _stopArrivals.containsKey(stop.id) && arrivals == null;
    final isLoading = _stopLoading[stop.id] ?? false;

    return Dismissible(
      key: Key('stop_${stop.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      onDismissed: (_) => _deleteStop(stop),
      child: _Board(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.name, style: TimbreText.stopName),
                    const SizedBox(height: 3),
                    Text('#${stop.id}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: TimbreColors.etiquetaCartel)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Horarios',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SchedulePage(stop: stop))),
                icon: const PixelIcon(PixelGlyphs.clock,
                    color: TimbreColors.etiquetaCartel),
              ),
              _AlertButton(
                on: stop.notificationsEnabled,
                onPressed: () => _toggleStopNotification(stop),
              ),
            ]),
          ),
          if (stop.notificationsEnabled)
            _buildAlertSettingsRow(stop.etaAlertMinutes, stop.schedule,
                () => _editStopAlert(stop)),
          const Divider(),
          _buildArrivals('s${stop.id}', arrivals, isLoading, failed, stop.id,
              stop.name),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () => widget.onOpenStopInComoIr(stop.id),
                icon: const PixelIcon(PixelGlyphs.map, size: 18),
                label: const Text('Ver en Cómo Ir'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- Routes tab ----

  Widget _buildRoutesTab() {
    if (_routes.isEmpty) {
      return const _EmptyTab(
        message: 'Sin rutas guardadas',
        sign: 'SIN RUTAS',
        detail: 'Tocá + para guardar una alerta de salida.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _loadGpsStatus();
        for (final r in _routes) {
          await _refreshRouteArrivals(r);
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 96),
        children: [
          _buildGpsWarning(),
          ..._routes.map(_buildRouteCard),
        ],
      ),
    );
  }

  Widget _buildRouteCard(RouteAlert route) {
    final arrivals = _routeArrivals[route.id];
    final failed = _routeArrivals.containsKey(route.id) && arrivals == null;
    final isLoading = _routeLoading[route.id] ?? false;

    return Dismissible(
      key: Key('route_${route.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      onDismissed: (_) => _deleteRoute(route),
      child: _Board(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const PixelIcon(PixelGlyphs.stop,
                          size: 14, color: TimbreColors.etiquetaCartel),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(route.originName,
                            style: const TextStyle(
                                fontSize: 13,
                                color: TimbreColors.etiquetaCartel)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('→ ${route.destinationName}',
                        style: TimbreText.stopName),
                    if (route.preferredLines.isNotEmpty ||
                        route.preferredDestinations.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                          [
                            if (route.preferredLines.isNotEmpty)
                              'Líneas: ${route.preferredLines.join(", ")}',
                            if (route.preferredDestinations.isNotEmpty)
                              'Hacia: ${route.preferredDestinations.join(", ")}',
                          ].join(' · '),
                          style: TimbreText.caption
                              .copyWith(color: TimbreColors.tenue)),
                    ],
                  ],
                ),
              ),
              _AlertButton(
                on: route.enabled,
                onPressed: () => _toggleRouteEnabled(route),
              ),
            ]),
          ),
          if (route.enabled)
            _buildAlertSettingsRow(route.alertMinutes, route.schedule,
                () => _editRouteAlert(route)),
          const Divider(),
          _buildArrivals('r${route.id}', arrivals, isLoading, failed,
              route.originStopId, route.originName),
        ],
      ),
    );
  }

  // --------------------------------------------------------- Shared --------

  /// Shown when an operator reports GPS for less than 70 % of its buses.
  Widget _buildGpsWarning() {
    final text = BusStatusService.partialWarning(_gpsStatus);
    if (text == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TimbreColors.avisoNoche,
        border: Border.all(color: TimbreColors.ambarTenue),
        borderRadius: BorderRadius.circular(TimbreRadii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PixelIcon(PixelGlyphs.signal,
              size: 18, color: TimbreColors.ambar),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: TimbreColors.papel)),
          ),
        ],
      ),
    );
  }

  /// Under an enabled alert: "Aviso 5 min antes · Lun a Vie 7:30–8:30".
  /// Opens the threshold and schedule settings.
  Widget _buildAlertSettingsRow(
      int minutes, AlertSchedule schedule, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TimbreSpace.touch),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Row(children: [
            const PixelIcon(PixelGlyphs.bellRing,
                size: 14, color: TimbreColors.ambar),
            const SizedBox(width: TimbreSpace.s),
            Expanded(
              child: Text('Aviso $minutes min antes · ${schedule.label}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TimbreColors.ambar)),
            ),
            const PixelIcon(PixelGlyphs.chevronRight,
                size: 14, color: TimbreColors.etiquetaCartel),
          ]),
        ),
      ),
    );
  }

  /// The next buses of a stop: three rows, all of them (up to six) on
  /// request.
  Widget _buildArrivals(String key, List<BusArrival>? arrivals,
      bool isLoading, bool failed, int stopId, String stopName) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Offline must not look like "no buses are coming"
    if (failed) {
      return const _BoardNote(
        icon: PixelGlyphs.warning,
        color: TimbreColors.ambar,
        text: 'No se pudo actualizar. Deslizá para reintentar',
      );
    }
    if (arrivals == null || arrivals.isEmpty) {
      return const _BoardNote(
        icon: PixelGlyphs.bus,
        color: TimbreColors.tenue,
        text: 'Sin ómnibus próximos',
      );
    }
    final wait = BusWaitService.current.value;
    final waited = wait != null && wait.stopId == stopId
        ? wait.findTrip(arrivals, DateTime.now())
        : null;
    final all = arrivals.take(6).toList();
    final open = _expanded.contains(key) || all.length <= 3;
    final shown = open ? all : all.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(indent: 14, endIndent: 14),
          ArrivalRow(
            arrival: shown[i],
            waited: identical(shown[i], waited),
            onTap: () => _showWaitSheet(stopId, stopName, shown[i],
                waiting: identical(shown[i], waited)),
          ),
        ],
        if (all.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () => setState(() =>
                    open ? _expanded.remove(key) : _expanded.add(key)),
                icon: PixelIcon(
                    open ? PixelGlyphs.minus : PixelGlyphs.chevronDown,
                    size: 16),
                label: Text(open ? 'Ver menos' : 'Ver las ${all.length}'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _deleteBackground() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: TimbreColors.rojoLed,
          borderRadius: BorderRadius.circular(TimbreRadii.card),
        ),
        child: const PixelIcon(PixelGlyphs.trash,
            color: TimbreColors.noche, semanticLabel: 'Eliminar'),
      );
}

/// A card of the stops and routes tabs: an ink panel on the board.
class _Board extends StatelessWidget {
  const _Board({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// One line inside a board when there are no rows to show.
class _BoardNote extends StatelessWidget {
  const _BoardNote(
      {required this.icon, required this.color, required this.text});

  final PixelGlyph icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(children: [
        PixelIcon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TimbreText.subtitle.copyWith(color: color)),
        ),
      ]),
    );
  }
}

/// The alert of a stop or route: a bell, lit and ringing when on.
class _AlertButton extends StatelessWidget {
  const _AlertButton({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: on ? 'Desactivar avisos' : 'Activar avisos',
      isSelected: on,
      onPressed: onPressed,
      icon: PixelIcon(
        on ? PixelGlyphs.bellRing : PixelGlyphs.bell,
        color: on ? TimbreColors.ambar : TimbreColors.tenue,
        glow: on,
      ),
    );
  }
}

/// An empty tab: a sign with nothing to announce, scrollable so pull to
/// refresh and the largest fonts still fit.
class _EmptyTab extends StatelessWidget {
  const _EmptyTab(
      {required this.message, required this.sign, required this.detail});

  final String message;
  final String sign;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: TimbreEmptyState(message, sign: sign, detail: detail),
          ),
        ),
      ),
    );
  }
}

/// Pixel icon inside a text field.
class _FieldIcon extends StatelessWidget {
  const _FieldIcon(this.glyph);

  final PixelGlyph glyph;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 44,
        child: Center(
          child: PixelIcon(glyph,
              size: 20, color: TimbreColors.etiquetaCartel),
        ),
      );
}

/// Add-stop dialog: type the stop number, search by street names (through
/// the proxy only) or pick one of the stops around the user ("Paradas
/// cercanas"). Pops with the chosen stop ID.
class _AddStopDialog extends StatefulWidget {
  const _AddStopDialog();

  @override
  State<_AddStopDialog> createState() => _AddStopDialogState();
}

class _AddStopDialogState extends State<_AddStopDialog> {
  final _controller = TextEditingController();
  final _streetController = TextEditingController();
  bool _searching = false;
  List<NearbyStop>? _nearby;
  NearbyStopsError? _error;

  // Search by streets: the catalog is loaded on the first letter typed
  List<CatalogStop>? _catalog;
  bool _catalogLoading = false;
  bool _catalogFailed = false;
  List<CatalogStop>? _matches;

  static const _maxMatches = 50;
  static final _radiusLabel = '${NearbyStopsService.radiusMeters.round()} m';

  @override
  void dispose() {
    _controller.dispose();
    _streetController.dispose();
    super.dispose();
  }

  void _onStreetQuery(String query) {
    final catalog = _catalog;
    final empty = query.trim().isEmpty;
    // One list at a time: street matches replace the nearby stops
    setState(() {
      _nearby = null;
      _error = null;
      // One extra match tells that there are more than shown
      _matches = empty || catalog == null
          ? null
          : MvdApiService.searchStops(catalog, query, limit: _maxMatches + 1);
    });
    if (!empty && catalog == null && !_catalogLoading) _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogFailed = false;
    });
    final catalog = await MvdApiService.getStopCatalog();
    if (!mounted) return;
    setState(() {
      _catalogLoading = false;
      _catalog = catalog;
      _catalogFailed = catalog == null;
    });
    // Search what was typed meanwhile
    if (catalog != null) _onStreetQuery(_streetController.text);
  }

  Future<void> _findNearby() async {
    // Hide the keyboard so the list has room
    FocusScope.of(context).unfocus();
    _streetController.clear();
    setState(() {
      _searching = true;
      _error = null;
      _nearby = null;
      _matches = null;
      _catalogFailed = false;
    });
    try {
      final stops = await NearbyStopsService.findNearMe();
      if (mounted) setState(() => _nearby = stops);
    } on NearbyStopsException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } catch (e) {
      debugPrint('❌ Nearby stops error: $e');
      if (mounted) setState(() => _error = NearbyStopsError.locationUnavailable);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _errorMessage(NearbyStopsError error) => switch (error) {
        NearbyStopsError.serviceDisabled =>
          'Activá la ubicación del teléfono para buscar paradas cercanas.',
        NearbyStopsError.permissionDenied =>
          'Sin permiso de ubicación no se pueden buscar paradas cercanas.',
        NearbyStopsError.permissionDeniedForever =>
          'El permiso de ubicación está desactivado para la app.',
        NearbyStopsError.locationUnavailable =>
          'No se pudo obtener tu ubicación. Probá de nuevo.',
        NearbyStopsError.network =>
          'No se pudieron cargar las paradas cercanas. Revisá la conexión.',
      };

  @override
  Widget build(BuildContext context) {
    final nearby = _nearby;
    final error = _error;
    final matches = _matches;

    return AlertDialog(
      title: const Text('Agregar parada'),
      content: SizedBox(
        // A ListView inside AlertDialog needs a definite width
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Número de parada',
                hintText: 'Ej: 1234',
                prefixIcon: _FieldIcon(PixelGlyphs.bus),
              ),
              autofocus: true,
            ),
            // The catalog with street names comes from the proxy only
            if (MvdApiService.usesProxy) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _streetController,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Buscar por calles',
                  hintText: 'Ej: San José y Andes',
                  prefixIcon: _FieldIcon(PixelGlyphs.search),
                ),
                onChanged: _onStreetQuery,
              ),
              if (_catalogLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_catalogFailed)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                      'No se pudo cargar la lista de paradas. '
                      'Revisá la conexión.',
                      style:
                          TextStyle(color: TimbreColors.rojoLed, fontSize: 13)),
                ),
              if (matches != null && matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Ninguna parada coincide',
                      style: TextStyle(
                          color: TimbreColors.etiquetaCartel, fontSize: 13)),
                ),
              if (matches != null && matches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: matches.length.clamp(0, _maxMatches),
                    itemBuilder: (_, i) => _buildMatchTile(matches[i]),
                  ),
                ),
                if (matches.length > _maxMatches)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'Hay más de $_maxMatches: agregá la otra calle',
                        style: TextStyle(
                            color: TimbreColors.etiquetaCartel, fontSize: 13)),
                  ),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _searching ? null : _findNearby,
              icon: const PixelIcon(PixelGlyphs.gps, size: 20),
              label: const Text('Paradas cercanas'),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage(error),
                  style:
                      const TextStyle(color: TimbreColors.rojoLed, fontSize: 13)),
              if (error == NearbyStopsError.permissionDeniedForever)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: NearbyStopsService.openAppSettings,
                    child: const Text('Abrir ajustes'),
                  ),
                ),
            ],
            if (nearby != null && nearby.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('No hay paradas a menos de $_radiusLabel',
                    style:
                        const TextStyle(
                            color: TimbreColors.etiquetaCartel, fontSize: 13)),
              ),
            if (nearby != null && nearby.isNotEmpty) ...[
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: nearby.length,
                  itemBuilder: (_, i) =>
                      _buildNearbyTile(nearby[i]),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_controller.text)),
          child: const Text('Agregar'),
        ),
      ],
    );
  }

  Widget _buildNearbyTile(NearbyStop stop) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const PixelIcon(PixelGlyphs.stop,
            size: 22, color: TimbreColors.ambar),
        title: Text(stop.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: TimbreColors.papel)),
        // Merged into the tile's style, so it keeps the app font
        subtitle: Text(
          '#${stop.id} · ${stop.distanceMeters.round()} m'
          '${stop.lines.isEmpty ? '' : ' · ${stop.lines.join(', ')}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TimbreText.caption,
        ),
        onTap: () => Navigator.pop(context, stop.id),
      );

  /// A stop found by its streets: the same tile as a nearby one, with
  /// the number under the name.
  Widget _buildMatchTile(CatalogStop stop) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const PixelIcon(PixelGlyphs.stop,
            size: 22, color: TimbreColors.ambar),
        title: Text(stop.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: TimbreColors.papel)),
        subtitle: Text('#${stop.id}', style: TimbreText.caption),
        onTap: () => Navigator.pop(context, stop.id),
      );
}

/// Add-route dialog: origin stop and destination label. Once the stop is
/// looked up, its lines (`transporteRest/lineas`) and the directions of its
/// upcoming buses (`destino`) are picked as chips; none picked = all.
class _AddRouteDialog extends StatefulWidget {
  const _AddRouteDialog();

  @override
  State<_AddRouteDialog> createState() => _AddRouteDialogState();
}

class _AddRouteDialogState extends State<_AddRouteDialog> {
  final _stopCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  // Looked-up stop with its lines (null = not looked up yet)
  BusStop? _stop;
  // Upcoming buses of the stop: where each line is heading
  List<BusArrival> _arrivals = const [];
  final _lines = <String>{};
  final _directions = <String>{};

  @override
  void dispose() {
    _stopCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  /// Another stop number: the chips belonged to the previous one.
  void _reset() {
    if (_stop == null && _error == null) return;
    setState(() {
      _stop = null;
      _error = null;
      _arrivals = const [];
      _lines.clear();
      _directions.clear();
    });
  }

  Future<void> _lookUp() async {
    final stopId = int.tryParse(_stopCtrl.text);
    if (stopId == null || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final arrivals = MvdApiService.getNextArrivals(stopId);
    BusStop? stop;
    String? error;
    try {
      stop = await MvdApiService.resolveStop(stopId);
      if (stop == null) {
        error = 'No se pudieron cargar las líneas. Revisá la conexión.';
      }
    } on StopNotFoundException {
      error = 'No existe la parada $stopId';
    }
    final upcoming = await arrivals;
    if (!mounted) return;
    setState(() {
      _loading = false;
      // The number was edited meanwhile
      if (int.tryParse(_stopCtrl.text) != stopId) return;
      _stop = stop;
      _error = error;
      _arrivals = upcoming ?? const [];
    });
  }

  /// Directions of the upcoming buses of the picked lines (or of all).
  List<String> get _visibleDirections => {
        for (final a in _arrivals)
          if (a.destination.isNotEmpty &&
              (_lines.isEmpty || _lines.contains(a.line)))
            a.destination,
      }.toList()
        ..sort();

  void _save() {
    final stopId = int.tryParse(_stopCtrl.text);
    if (stopId == null || _destCtrl.text.trim().isEmpty) return;
    final stop = _stop;
    final directions = _visibleDirections;
    Navigator.pop(
      context,
      _RouteFormData(
        originStopId: stopId,
        destinationName: _destCtrl.text.trim(),
        origin: stop,
        // In the API order, as the chips
        preferredLines: [
          for (final l in stop?.lines ?? const <String>[])
            if (_lines.contains(l)) l,
        ],
        preferredDestinations: [
          for (final d in directions)
            if (_directions.contains(d)) d,
        ],
      ),
    );
  }

  Widget _chips(List<String> labels, Set<String> picked) => Wrap(
        spacing: TimbreSpace.s,
        runSpacing: TimbreSpace.xs,
        children: [
          for (final label in labels)
            FilterChip(
              label: Text(label),
              selected: picked.contains(label),
              onSelected: (on) => setState(
                  () => on ? picked.add(label) : picked.remove(label)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const hint = TextStyle(color: TimbreColors.etiquetaCartel, fontSize: 13);
    const label = TimbreText.sectionLabel;
    final stop = _stop;
    final error = _error;
    final directions = _visibleDirections;

    return AlertDialog(
      title: const Text('Agregar ruta'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _stopCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.search,
                onChanged: (_) => _reset(),
                onSubmitted: (_) => _lookUp(),
                decoration: InputDecoration(
                  labelText: 'Parada de origen *',
                  hintText: 'Ej: 1234',
                  prefixIcon: const _FieldIcon(PixelGlyphs.stop),
                  suffixIcon: IconButton(
                    onPressed: _loading ? null : _lookUp,
                    tooltip: 'Ver líneas',
                    icon: const PixelIcon(PixelGlyphs.search, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _destCtrl,
                decoration: const InputDecoration(
                  labelText: 'Destino *',
                  hintText: 'Ej: Centro',
                  prefixIcon: _FieldIcon(PixelGlyphs.route),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                Text(error,
                    style: const TextStyle(
                        color: TimbreColors.rojoLed, fontSize: 13))
              else if (stop == null)
                const Text('Buscá la parada para elegir sus líneas',
                    style: hint)
              else ...[
                Text(stop.name, style: TimbreText.stopName),
                const SizedBox(height: TimbreSpace.m),
                const Text('LÍNEAS', style: label),
                const SizedBox(height: TimbreSpace.xs),
                _chips(stop.lines, _lines),
                if (directions.isNotEmpty) ...[
                  const SizedBox(height: TimbreSpace.m),
                  const Text('HACIA', style: label),
                  const SizedBox(height: TimbreSpace.xs),
                  _chips(directions, _directions),
                ],
                const SizedBox(height: 4),
                const Text('Si no elegís ninguna, se incluyen todas.',
                    style: hint),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Internal form data for the add-route dialog.
class _RouteFormData {
  final int originStopId;
  final String destinationName;
  // Resolved by the dialog (null = not looked up)
  final BusStop? origin;
  final List<String> preferredLines;
  final List<String> preferredDestinations;

  const _RouteFormData({
    required this.originStopId,
    required this.destinationName,
    this.origin,
    required this.preferredLines,
    required this.preferredDestinations,
  });
}

/// Threshold and schedule of a stop or route alert, e.g. 5 min before,
/// Monday to Friday 7:30–8:30. Pops with the chosen values.
class _AlertSettingsSheet extends StatefulWidget {
  final String title;
  final int minutes;
  final AlertSchedule schedule;

  const _AlertSettingsSheet(
      {required this.title, required this.minutes, required this.schedule});

  @override
  State<_AlertSettingsSheet> createState() => _AlertSettingsSheetState();
}

class _AlertSettingsSheetState extends State<_AlertSettingsSheet> {
  static const _dayChips = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
  // Offered when "Todo el día" is turned off
  static const _defaultFrom = 7 * 60, _defaultTo = 9 * 60;

  late int _minutes = widget.minutes;
  late final Set<int> _days = {...widget.schedule.days};
  late bool _allDay = widget.schedule.isAllDay;
  late int _from =
      widget.schedule.isAllDay ? _defaultFrom : widget.schedule.fromMinute;
  late int _to =
      widget.schedule.isAllDay ? _defaultTo : widget.schedule.toMinute;

  String? get _problem {
    if (_days.isEmpty) return 'Elegí al menos un día';
    if (!_allDay && _from == _to) return 'Elegí horas distintas';
    return null;
  }

  Future<void> _pickTime({required bool from}) async {
    final current = from ? _from : _to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: from ? 'Desde' : 'Hasta',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final minute = picked.hour * 60 + picked.minute;
      if (from) {
        _from = minute;
      } else {
        _to = minute;
      }
    });
  }

  void _save() => Navigator.pop(
        context,
        (
          _minutes,
          AlertSchedule(
            days: _days.toList()..sort(),
            fromMinute: _allDay ? 0 : _from,
            toMinute: _allDay ? AlertSchedule.dayMinutes : _to,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: TimbreText.stopName),
            if (defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: TimbreSpace.xs),
              Text(
                  'Se revisa cada 15 min aprox. y avisa solo por ómnibus '
                  'con GPS.',
                  style: TimbreText.caption.copyWith(height: 1.4)),
            ],
            const SizedBox(height: 18),
            Text('Avisarme cuando falten',
                style: TimbreText.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: TimbreSpace.s),
            TimbreSegmented<int>(
              values: const [3, 5, 10],
              selected: _minutes,
              labelOf: (m) => '$m min',
              semanticLabel: 'Minutos antes de que llegue',
              onChanged: (m) => setState(() => _minutes = m),
            ),
            const SizedBox(height: 18),
            const Text('DÍAS', style: TimbreText.sectionLabel),
            const SizedBox(height: TimbreSpace.xs),
            Wrap(
              spacing: TimbreSpace.s,
              runSpacing: TimbreSpace.xs,
              children: [
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  FilterChip(
                    label: Text(_dayChips[day - 1]),
                    showCheckmark: false,
                    selected: _days.contains(day),
                    onSelected: (on) => setState(
                        () => on ? _days.add(day) : _days.remove(day)),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Todo el día'),
              value: _allDay,
              onChanged: (on) => setState(() => _allDay = on),
            ),
            if (!_allDay)
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(from: true),
                    child: Text('Desde ${AlertSchedule.time(_from)}'),
                  ),
                ),
                const SizedBox(width: TimbreSpace.m),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(from: false),
                    child: Text('Hasta ${AlertSchedule.time(_to)}'),
                  ),
                ),
              ]),
            if (problem != null) ...[
              const SizedBox(height: TimbreSpace.s),
              Text(problem,
                  style: const TextStyle(
                      color: TimbreColors.rojoLed, fontSize: 13)),
            ],
            const SizedBox(height: TimbreSpace.l),
            FilledButton(
              onPressed: problem == null ? _save : null,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
