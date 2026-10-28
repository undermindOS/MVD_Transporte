import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../models/alert_schedule.dart';
import '../models/arrivals_board.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/bus_wait.dart';
import '../models/catalog_stop.dart';
import '../models/nearby_stop.dart';
import '../models/route_alert.dart';
import '../models/stop_details.dart';
import '../models/transport_news.dart';
import '../services/api/api_result.dart';
import '../services/background_worker.dart';
import '../services/bus_status_service.dart';
import '../services/bus_wait_service.dart';
import '../services/cache_service.dart';
import '../services/home_widget_feed.dart';
import '../services/mvd_api_service.dart';
import '../services/nearby_stops_service.dart';
import '../services/notification_service.dart';
import '../services/transport_news_service.dart';
import 'news_list.dart';
import 'schedule_page.dart';
import 'spoken_text.dart';
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

  /// Mis paradas is on screen: its tab is selected, no page covers it and
  /// the app is not locked. Arrivals are polled only then; becoming active
  /// refreshes them once.
  final bool active;

  const StopsPage(
      {super.key, required this.onOpenStopInComoIr, this.active = true});

  /// Arrival times go stale within a minute: refresh this often while the
  /// page is on screen and the app in the foreground.
  static const autoRefreshInterval = Duration(seconds: 30);

  /// The phone's clock: when a board arrived, and how long ago. Tests move
  /// it forward.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<StopsPage> createState() => _StopsPageState();
}

class _StopsPageState extends State<StopsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  // null while not polling: app in the background or page not on screen
  Timer? _autoRefreshTimer;
  bool _autoRefreshing = false;
  // The app is hidden or paused
  bool _inBackground = false;
  // After a busy answer (429), ticks are skipped until then
  DateTime? _skipTicksUntil;

  // After a failed refresh the last buses stay this long, as estimates;
  // a bus due more than [_staleRowGrace] ago is dropped from them
  static const _staleFor = Duration(minutes: 5);
  static const _staleRowGrace = Duration(minutes: 1);
  // Two refresh intervals: a board that arrived longer ago, with no failure
  // since, is not live any more (one on its way back on screen, or busy)
  static const _liveFor = Duration(minutes: 1);
  // Without a Retry-After
  static const _busyDefault = Duration(seconds: 60);

  // --- Stops ---
  List<BusStop> _stops = [];

  // --- Routes ---
  List<RouteAlert> _routes = [];

  // The board of every stop a card shows, saved stops and route origins
  // alike: a stop is requested once, whatever the cards that show it
  final Map<int, _BoardView> _boards = {};

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

  /// Deleting a card without the swipe, for screen readers.
  static const _deleteAction = CustomSemanticsAction(label: 'Borrar');

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
    if (widget.active) _startAutoRefresh();
    BusWaitService.current.addListener(_onWaitChanged);
  }

  @override
  void didUpdateWidget(StopsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _resumeAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
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
        if (_inBackground) {
          _inBackground = false;
          BusWaitService.sync();
          // After the next frame: when the app locks on its way back, that
          // frame turns this page inactive first, and nothing is requested
          WidgetsBinding.instance.endOfFrame.then((_) {
            if (mounted) _resumeAutoRefresh();
          });
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _inBackground = true;
        _stopAutoRefresh();
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
    _autoRefreshTimer = Timer.periodic(StopsPage.autoRefreshInterval, (_) {
      // Busy (429): wait out the Retry-After, without a word
      final skipUntil = _skipTicksUntil;
      if (skipUntil != null && DateTime.now().isBefore(skipUntil)) return;
      _autoRefresh();
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// On screen again: refreshed at once, then every 30 s.
  void _resumeAutoRefresh() {
    if (!widget.active || _inBackground || _autoRefreshTimer != null) return;
    _autoRefresh();
    _startAutoRefresh();
  }

  /// Refreshes every card without spinners, so the rows do not flicker.
  Future<void> _autoRefresh() async {
    if (_autoRefreshing) return; // slow network: don't pile up requests
    _autoRefreshing = true;
    try {
      _loadGpsStatus();
      await _refresh(_shownStopIds);
    } finally {
      _autoRefreshing = false;
    }
  }

  /// Every stop a card shows: the saved stops and the route origins.
  Set<int> get _shownStopIds => {
        ..._stops.map((s) => s.id),
        ..._routes.map((r) => r.originStopId),
      };

  /// The one way boards are fetched: on open, every tick, back on screen,
  /// on pull to refresh, and for a stop or route just added. Each stop
  /// once, all in parallel. With [spinner] a card with no buses to show
  /// yet says it is loading.
  Future<void> _refresh(Set<int> ids, {bool spinner = false}) async {
    if (ids.isEmpty) return;
    if (spinner) {
      setState(() {
        for (final id in ids) {
          final view = _boards[id];
          _boards[id] = _BoardView(
              lastGood: view?.lastGood,
              receivedAt: view?.receivedAt,
              failure: view?.failure,
              loading: true);
        }
      });
    }
    final results = await MvdApiService.getBoards(ids);
    results.forEach((id, result) =>
        BusWaitService.onArrivals(id, result.valueOrNull?.arrivals));

    Duration? busyFor;
    for (final result in results.values) {
      if (result case ApiError(failure: ApiFailure.busy, :final retryAfter)) {
        final wait = retryAfter ?? _busyDefault;
        if (busyFor == null || wait > busyFor) busyFor = wait;
      }
    }
    if (busyFor != null) _skipTicksUntil = DateTime.now().add(busyFor);

    // The home widget shows the first enabled route: fresher than the
    // background check, at least 15 min apart. Not awaited: it catches
    // its own errors
    final enabledRoutes = CacheService.getEnabledRoutes();
    final widgetRoute = enabledRoutes.firstOrNull;
    if (widgetRoute != null && results.containsKey(widgetRoute.originStopId)) {
      unawaited(WidgetFeed.update(
          enabledRoutes: enabledRoutes, boards: results, now: DateTime.now()));
    }

    if (!mounted) return;
    setState(() {
      results.forEach((id, result) {
        final view = _boards[id];
        _boards[id] = switch (result) {
          ApiOk(:final value) =>
            _BoardView(lastGood: value, receivedAt: StopsPage.clock()),
          // Nothing new and nothing to say: the next ticks wait
          ApiError(failure: ApiFailure.busy) => _BoardView(
              lastGood: view?.lastGood,
              receivedAt: view?.receivedAt,
              failure: view?.failure),
          ApiError(:final failure) => _BoardView(
              lastGood: view?.lastGood,
              receivedAt: view?.receivedAt,
              failure: failure),
        };
      });
    });
  }

  void _loadAll() {
    _loadStops();
    _loadRoutes();
    _refresh(_shownStopIds, spinner: true);
    _loadNews();
    _loadGpsStatus();
    // Stops saved offline as "Parada N" get their name and lines; not
    // awaited, the cards show at once
    MvdApiService.healPlaceholderStops().then((healed) {
      if (healed > 0 && mounted) _loadStops();
    });
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
            size: TimbreIconSize.row, color: TimbreColors.rojoLed),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
  }

  // ---------------------------------------------------------------- Stops ---

  void _loadStops() => setState(() => _stops = CacheService.getAllStops());

  Future<void> _addStop() async {
    final choice = await _showAddStopDialog();
    if (choice == null || !mounted) return;
    final stopId = choice.id;

    // 0 or more than 7 digits: no request, it cannot exist
    if (!MvdApiService.isValidStopId(stopId)) {
      _showError('No existe la parada $stopId. Revisá el número.');
      return;
    }
    // Re-adding would overwrite the saved alert settings
    if (CacheService.getStop(stopId) != null) {
      _showError('La parada $stopId ya está guardada');
      return;
    }

    final snack = ScaffoldMessenger.of(context);
    // Picked from the catalog or the nearby stops: already known
    var stop = choice.stop;
    if (stop == null) {
      snack.showSnackBar(const SnackBar(content: Text('Buscando parada…')));
      switch (await MvdApiService.getStopDetails(stopId)) {
        case ApiOk(:final value):
          stop = value.toBusStop();
        case ApiError(failure: ApiFailure.notFound):
          _showError('No existe la parada $stopId. Revisá el número.');
          return;
        case ApiError():
          // Offline: kept with a placeholder name, healed on a later start
          stop = BusStop(id: stopId, name: 'Parada $stopId');
      }
    }
    await CacheService.saveStop(stop);

    if (mounted) {
      snack.clearSnackBars();
      _loadStops();
      _refresh({stop.id}, spinner: true);
    }
  }

  Future<_StopChoice?> _showAddStopDialog() => showDialog<_StopChoice>(
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
    final settings = await _showAlertSettings(stop.name,
        _stopPhrase(stop.id, stop.name), stop.etaAlertMinutes, stop.schedule);
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
      _forgetUnshownBoard(stop.id);
    });
    CacheService.deleteStop(stop.id).then((_) => _syncAlerts());
  }

  /// Drops the board of [stopId] once no card shows it any more.
  void _forgetUnshownBoard(int stopId) {
    if (!_shownStopIds.contains(stopId)) _boards.remove(stopId);
  }

  // ---------------------------------------------------------------- Routes --

  void _loadRoutes() => setState(() => _routes = CacheService.getAllRoutes());

  Future<void> _addRouteManually() async {
    final result = await _showAddRouteDialog();
    if (result == null || !mounted) return;

    final snack = ScaffoldMessenger.of(context);
    // Already looked up if the dialog listed the stop's lines
    var origin = result.origin;
    if (origin == null) {
      snack.showSnackBar(const SnackBar(content: Text('Buscando parada…')));
      switch (await MvdApiService.getStopDetails(result.originStopId)) {
        case ApiOk(:final value):
          origin = value;
        case ApiError(failure: ApiFailure.notFound):
          _showError(
              'No existe la parada ${result.originStopId}. Revisá el número.');
          return;
        case ApiError():
          break; // offline: a placeholder name
      }
    }
    final id = CacheService.nextRouteId();
    final route = RouteAlert(
      id: id,
      originStopId: result.originStopId,
      originName: origin?.displayName ?? 'Parada ${result.originStopId}',
      destinationName: result.destinationName,
      preferredLines: result.preferredLines,
      preferredDestinations: result.preferredDestinations,
      preferredVariantIds: result.preferredVariantIds,
    );
    await CacheService.saveRoute(route);

    if (mounted) {
      snack.clearSnackBars();
      _loadRoutes();
      _refresh({route.originStopId}, spinner: true);
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
        _routeName(route),
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

  /// Threshold and schedule of a stop or route alert. [spokenTitle] is
  /// what screen readers hear instead of the uppercase [title].
  Future<(int, AlertSchedule)?> _showAlertSettings(String title,
          String spokenTitle, int minutes, AlertSchedule schedule) =>
      showModalBottomSheet<(int, AlertSchedule)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AlertSettingsSheet(
            title: title,
            spokenTitle: spokenTitle,
            minutes: minutes,
            schedule: schedule),
      );

  void _deleteRoute(RouteAlert route) {
    // Dismissible requires the item to leave the list synchronously
    setState(() {
      _routes.removeWhere((r) => r.id == route.id);
      _forgetUnshownBoard(route.originStopId);
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
                  Semantics(
                    label: trip.destination.isEmpty
                        ? 'Línea ${trip.line}'
                        : 'Línea ${trip.line} a '
                            '${spokenName(trip.destination)}',
                    excludeSemantics: true,
                    child: Text(
                      trip.destination.isEmpty
                          ? 'Línea ${trip.line}'
                          : '${trip.line} → ${trip.destination}',
                      style: TimbreText.destination.copyWith(fontSize: 20),
                    ),
                  ),
                const SizedBox(height: 8),
                Semantics(
                  label: trip.isRealTime
                      ? '${spokenName(stopName)}, con GPS'
                      : 'Según horario ${trip.etaLabel}, sin GPS todavía, '
                          '${spokenName(stopName)}',
                  excludeSemantics: true,
                  child: Text(
                    trip.isRealTime
                        ? '$stopName · con GPS'
                        : 'Según horario ${trip.etaLabel}, sin GPS '
                            'todavía · $stopName',
                    style: TimbreText.subtitle,
                  ),
                ),
                const SizedBox(height: 18),
                if (waiting)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, -1),
                    icon: const PixelIcon(PixelGlyphs.bell,
                        size: TimbreIconSize.row),
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
                    icon: const PixelIcon(PixelGlyphs.bellRing,
                        size: TimbreIconSize.row),
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
        _showError('No se pudo activar el aviso. Revisá que las '
            'notificaciones estén permitidas y probá de nuevo.');
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
                label: Text('$unread',
                    semanticsLabel: unread == 1
                        ? '1 novedad sin leer'
                        : '$unread novedades sin leer'),
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
              child: const PixelIcon(PixelGlyphs.plus,
                  size: TimbreIconSize.rowLarge),
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
      onRefresh: () {
        _loadGpsStatus();
        return _refresh({for (final s in _stops) s.id});
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
                // One phrase for screen readers, with the swipe to delete
                // as an action
                child: Semantics(
                  container: true,
                  label: _stopPhrase(stop.id, stop.name),
                  customSemanticsActions: {
                    _deleteAction: () => _deleteStop(stop),
                  },
                  excludeSemantics: true,
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
          _buildArrivals('s${stop.id}', stop.id, stop.name),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () => widget.onOpenStopInComoIr(stop.id),
                icon: const PixelIcon(PixelGlyphs.map,
                    size: TimbreIconSize.row),
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
      onRefresh: () {
        _loadGpsStatus();
        return _refresh({for (final r in _routes) r.originStopId});
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

  /// A route reads its origin's board, through its lines and directions.
  Widget _buildRouteCard(RouteAlert route) {
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
                // One phrase for screen readers, with the swipe to delete
                // as an action
                child: Semantics(
                  container: true,
                  label: _routePhrase(route),
                  customSemanticsActions: {
                    _deleteAction: () => _deleteRoute(route),
                  },
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const PixelIcon(PixelGlyphs.stop,
                            size: TimbreIconSize.mark,
                            color: TimbreColors.etiquetaCartel),
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
                                'Hacia: '
                                    '${route.preferredDestinations.join(", ")}',
                            ].join(' · '),
                            style: TimbreText.caption
                                .copyWith(color: TimbreColors.tenue)),
                      ],
                    ],
                  ),
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
          _buildArrivals('r${route.id}', route.originStopId, route.originName,
              accepts: route.accepts),
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
      margin:
          const EdgeInsets.symmetric(horizontal: TimbreSpace.l, vertical: 6),
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
              size: TimbreIconSize.row, color: TimbreColors.ambar),
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
  /// Opens the threshold and schedule settings. A setting, not live data:
  /// only the bell is lit.
  Widget _buildAlertSettingsRow(
      int minutes, AlertSchedule schedule, VoidCallback onTap) {
    return Semantics(
      container: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TimbreSpace.touch),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Row(children: [
              const PixelIcon(PixelGlyphs.bellRing,
                  size: TimbreIconSize.mark, color: TimbreColors.ambar),
              const SizedBox(width: TimbreSpace.s),
              Expanded(
                child: Text('Aviso $minutes min antes · ${schedule.label}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TimbreColors.etiquetaCartel)),
              ),
              const PixelIcon(PixelGlyphs.chevronRight,
                  size: TimbreIconSize.mark,
                  color: TimbreColors.etiquetaCartel),
            ]),
          ),
        ),
      ),
    );
  }

  /// The next buses of [stopId] that [accepts] lets through: three rows,
  /// all of them (up to six) on request. After a failed refresh the last
  /// buses stay for a while under the error, as estimates.
  Widget _buildArrivals(String key, int stopId, String stopName,
      {bool Function(BusArrival)? accepts}) {
    final view = _boards[stopId];
    final board = view?.lastGood;
    final failure = view?.failure;
    const waiting = Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
    // Nothing to show yet: loading, or busy before the first board
    if (board == null && (failure == null || view!.loading)) return waiting;
    // An error inside a card is a red LED; a warning over a list is the
    // avisoNoche panel
    if (failure == ApiFailure.notFound) {
      return const _BoardNote(
        icon: PixelGlyphs.warning,
        color: TimbreColors.rojoLed,
        text: 'Esta parada ya no existe. Deslizá la tarjeta para borrarla.',
      );
    }
    List<BusArrival> accepted(ArrivalsBoard b) =>
        accepts == null ? b.arrivals : b.arrivals.where(accepts).toList();
    final now = DateTime.now();
    if (failure != null) {
      // Offline must not look like "no buses are coming", and old minutes
      // must not look live
      if (board == null || now.difference(board.fetchedAt) >= _staleFor) {
        return const _BoardNote(
          icon: PixelGlyphs.warning,
          color: TimbreColors.rojoLed,
          text: 'No se pudo actualizar. Deslizá para reintentar',
        );
      }
      final cutoff = now.subtract(_staleRowGrace);
      final stale = accepted(board)
          .where((a) => !a.expectedAt.isBefore(cutoff))
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BoardNote(
            icon: PixelGlyphs.warning,
            color: TimbreColors.rojoLed,
            text: 'No se pudo actualizar. Datos de las '
                '${MvdApiService.montevideoClock(board.fetchedAt)}. '
                'Deslizá para reintentar.',
          ),
          if (stale.isNotEmpty)
            _buildRows(key, stale, board.arrivals, stopId, stopName,
                stale: true),
        ],
      );
    }
    // No failure, but no new board for a while either: old minutes must
    // not look live. Estimates, then, past [_staleFor], a wait as before
    // the first board — busy says nothing, and a refresh may be on its way
    final received = view!.receivedAt;
    final age = received == null
        ? Duration.zero
        : StopsPage.clock().difference(received);
    if (age >= _liveFor) {
      final cutoff = now.subtract(_staleRowGrace);
      final stale = age >= _staleFor
          ? const <BusArrival>[]
          : accepted(board!)
              .where((a) => !a.expectedAt.isBefore(cutoff))
              .toList();
      if (stale.isEmpty) return waiting;
      return _buildRows(key, stale, board!.arrivals, stopId, stopName,
          stale: true);
    }
    final arrivals = accepted(board!);
    if (arrivals.isEmpty) {
      return const _BoardNote(
        icon: PixelGlyphs.bus,
        color: TimbreColors.tenue,
        text: 'Sin ómnibus próximos',
      );
    }
    return _buildRows(key, arrivals, board.arrivals, stopId, stopName);
  }

  /// [arrivals] of a board whose buses are [all]. A [stale] row is an
  /// estimate from the last board: not lit, not followed, not tappable.
  Widget _buildRows(String key, List<BusArrival> arrivals,
      List<BusArrival> all, int stopId, String stopName,
      {bool stale = false}) {
    final wait = BusWaitService.current.value;
    final now = DateTime.now();
    final rows = arrivals.take(6).toList();
    final open = _expanded.contains(key) || rows.length <= 3;
    final shown = open ? rows : rows.take(3).toList();
    // The followed trip, by its id, among all the buses of the stop
    final waited = [
      for (final a in shown)
        !stale &&
            wait != null &&
            wait.stopId == stopId &&
            wait.follows(a, all, now),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(indent: 14, endIndent: 14),
          ArrivalRow(
            arrival: shown[i],
            waited: waited[i],
            stale: stale,
            onTap: stale
                ? null
                : () => _showWaitSheet(stopId, stopName, shown[i],
                    waiting: waited[i]),
          ),
        ],
        if (rows.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () => setState(() =>
                    open ? _expanded.remove(key) : _expanded.add(key)),
                icon: PixelIcon(
                    open ? PixelGlyphs.minus : PixelGlyphs.chevronDown,
                    size: TimbreIconSize.row),
                label: Text(open ? 'Ver menos' : 'Ver las ${rows.length}'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _deleteBackground() => Container(
        margin:
            const EdgeInsets.symmetric(horizontal: TimbreSpace.l, vertical: 6),
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

/// What the cards of one stop show: the last board that arrived, and why
/// the latest refresh failed, if it did.
class _BoardView {
  const _BoardView(
      {this.lastGood, this.receivedAt, this.failure, this.loading = false});

  final ArrivalsBoard? lastGood;

  /// When [lastGood] arrived, on the phone's clock ([StopsPage.clock]):
  /// its `fetchedAt` is the server's, which may be skewed or edge-cached.
  final DateTime? receivedAt;

  /// The latest refresh failed; null after a good one. A busy answer
  /// changes nothing.
  final ApiFailure? failure;

  /// Being fetched with a spinner, for a card with nothing to show yet.
  final bool loading;
}

/// A card of the stops and routes tabs: an ink panel on the board.
class _Board extends StatelessWidget {
  const _Board({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: TimbreSpace.l, vertical: 6),
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
        PixelIcon(icon, size: TimbreIconSize.row, color: color),
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
              size: TimbreIconSize.row, color: TimbreColors.etiquetaCartel),
        ),
      );
}

/// What the add-stop dialog pops: a typed number to look up, or a stop
/// picked from the catalog or the nearby stops, saved as it is.
typedef _StopChoice = ({int id, BusStop? stop});

/// Add-stop dialog: type the stop number, search by street names (through
/// the proxy only) or pick one of the stops around the user ("Paradas
/// cercanas"). Pops with a [_StopChoice].
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
          'Permití la ubicación para buscar paradas cercanas.',
        NearbyStopsError.permissionDeniedForever =>
          'El permiso de ubicación está desactivado para la app. '
              'Activalo en Ajustes.',
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
              // Stop numbers have at most 7 digits
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
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
              icon: const PixelIcon(PixelGlyphs.gps, size: TimbreIconSize.row),
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
          onPressed: () {
            final id = int.tryParse(_controller.text);
            Navigator.pop<_StopChoice>(
                context, id == null ? null : (id: id, stop: null));
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }

  /// A listed stop is saved with the name, lines and location it is
  /// listed with: nothing more to look up, and the Mapa can place it.
  void _pick(int id, String name, List<String> lines, double latitude,
          double longitude) =>
      Navigator.pop<_StopChoice>(context, (
        id: id,
        stop: BusStop(
            id: id,
            name: name,
            lines: [...lines],
            latitude: latitude,
            longitude: longitude),
      ));

  /// A stop around the user. Without lines (the catalog could not get
  /// them) the line ends at the distance.
  Widget _buildNearbyTile(NearbyStop stop) {
    final meters = stop.distanceMeters.round();
    void pick() => _pick(
        stop.id, stop.name, stop.lines, stop.latitude, stop.longitude);
    return Semantics(
      button: true,
      label: '${_stopPhrase(stop.id, stop.name)}, a $meters metros'
          '${stop.lines.isEmpty ? '' : ', líneas ${stop.lines.join(', ')}'}',
      onTap: pick,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        // A passive mark: not lit
        leading: const PixelIcon(PixelGlyphs.stop,
            size: 22, color: TimbreColors.etiquetaCartel),
        title: Text(stop.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: TimbreColors.papel)),
        // Merged into the tile's style, so it keeps the app font
        subtitle: Text(
          '#${stop.id} · $meters m'
          '${stop.lines.isEmpty ? '' : ' · ${stop.lines.join(', ')}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TimbreText.caption,
        ),
        onTap: pick,
      ),
    );
  }

  /// A stop found by its streets: the same tile as a nearby one, with
  /// the number under the name.
  Widget _buildMatchTile(CatalogStop stop) {
    void pick() => _pick(
        stop.id, stop.name, stop.lines, stop.latitude, stop.longitude);
    return Semantics(
      button: true,
      label: _stopPhrase(stop.id, stop.name),
      onTap: pick,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const PixelIcon(PixelGlyphs.stop,
            size: 22, color: TimbreColors.etiquetaCartel),
        title: Text(stop.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: TimbreColors.papel)),
        subtitle: Text('#${stop.id}', style: TimbreText.caption),
        onTap: pick,
      ),
    );
  }
}

/// Add-route dialog: origin stop and destination label. Once the stop is
/// looked up, its lines and where they go are picked as chips; none
/// picked = all. Where a line goes comes from the stop's directions, or,
/// for a line without any, from its upcoming buses (`destino`).
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
  // Looked-up stop with its lines and directions (null = not looked up yet)
  StopDetails? _stop;
  // Upcoming buses of the stop: where a line without directions is heading
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
    // In parallel: the directions may leave a line out
    final board = MvdApiService.getBoard(stopId);
    StopDetails? stop;
    String? error;
    switch (await MvdApiService.getStopDetails(stopId)) {
      case ApiOk(:final value):
        stop = value;
      case ApiError(failure: ApiFailure.notFound):
        error = 'No existe la parada $stopId. Revisá el número.';
      case ApiError():
        error = 'No se pudieron cargar las líneas. Revisá la conexión.';
    }
    final upcoming = (await board).valueOrNull?.arrivals;
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

  /// Where the picked lines (or all) go, by destination, with the variants
  /// of each: the stop's directions, and for a line without any, its
  /// upcoming buses.
  SplayTreeMap<String, Set<int>> get _visibleDirections {
    final directions = _stop?.directions ?? const <StopDirection>[];
    bool picked(String line) => _lines.isEmpty || _lines.contains(line);
    final withDirections = {for (final d in directions) d.line};
    final chips = SplayTreeMap<String, Set<int>>();
    for (final d in directions) {
      if (!picked(d.line)) continue;
      chips.putIfAbsent(d.destination, () => {}).addAll(d.variantIds);
    }
    for (final a in _arrivals) {
      if (a.destination.isEmpty ||
          !picked(a.line) ||
          withDirections.contains(a.line)) {
        continue;
      }
      final variants = chips.putIfAbsent(a.destination, () => {});
      if (a.variantId case final variant?) variants.add(variant);
    }
    return chips;
  }

  void _save() {
    final stopId = int.tryParse(_stopCtrl.text);
    if (stopId == null || _destCtrl.text.trim().isEmpty) return;
    final stop = _stop;
    final directions = _visibleDirections;
    final destinations = [
      for (final d in directions.keys)
        if (_directions.contains(d)) d,
    ];
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
        preferredDestinations: destinations,
        // A bus of a picked variant matches whatever its label says
        preferredVariantIds: {
          for (final d in destinations) ...directions[d]!,
        }.toList()
          ..sort(),
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
    final directions = _visibleDirections.keys.toList();

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
                  // Screen readers say "obligatorio", not "asterisco"
                  label: const Text('Parada de origen *',
                      semanticsLabel: 'Parada de origen, obligatorio'),
                  hintText: 'Ej: 1234',
                  prefixIcon: const _FieldIcon(PixelGlyphs.stop),
                  suffixIcon: IconButton(
                    onPressed: _loading ? null : _lookUp,
                    tooltip: 'Ver líneas',
                    icon: const PixelIcon(PixelGlyphs.search,
                        size: TimbreIconSize.row),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _destCtrl,
                decoration: const InputDecoration(
                  label: Text('Destino *',
                      semanticsLabel: 'Destino, obligatorio'),
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
                Semantics(
                  label: _stopPhrase(stop.id, stop.displayName),
                  excludeSemantics: true,
                  child: Text(stop.displayName, style: TimbreText.stopName),
                ),
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
  // Looked up by the dialog (null = not looked up)
  final StopDetails? origin;
  final List<String> preferredLines;
  final List<String> preferredDestinations;
  final List<int> preferredVariantIds;

  const _RouteFormData({
    required this.originStopId,
    required this.destinationName,
    this.origin,
    required this.preferredLines,
    required this.preferredDestinations,
    required this.preferredVariantIds,
  });
}

/// Threshold and schedule of a stop or route alert, e.g. 5 min before,
/// Monday to Friday 7:30–8:30. Pops with the chosen values.
class _AlertSettingsSheet extends StatefulWidget {
  final String title;

  /// What screen readers hear instead of the uppercase [title].
  final String spokenTitle;
  final int minutes;
  final AlertSchedule schedule;

  const _AlertSettingsSheet(
      {required this.title,
      required this.spokenTitle,
      required this.minutes,
      required this.schedule});

  @override
  State<_AlertSettingsSheet> createState() => _AlertSettingsSheetState();
}

class _AlertSettingsSheetState extends State<_AlertSettingsSheet> {
  static const _dayChips = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
  // What screen readers say for each chip
  static const _dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
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
            Semantics(
              header: true,
              label: widget.spokenTitle,
              excludeSemantics: true,
              child: Text(widget.title, style: TimbreText.stopName),
            ),
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
                    label: Text(_dayChips[day - 1],
                        semanticsLabel: _dayNames[day - 1]),
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

/// "Parada 574, San Jose y Andes": a stop for screen readers, the API name
/// in words. A stop saved offline is just "Parada 574".
String _stopPhrase(int id, String name) =>
    name == 'Parada $id' ? name : 'Parada $id, ${spokenName(name)}';

/// "De San Jose y Andes a Trabajo": the origin is an API name, the
/// destination the user's own words.
String _routeName(RouteAlert route) =>
    'De ${spokenName(route.originName)} a ${route.destinationName}';

/// The route card for screen readers: [_routeName] and the picked lines
/// and directions.
String _routePhrase(RouteAlert route) => [
      _routeName(route),
      if (route.preferredLines.isNotEmpty)
        'líneas ${route.preferredLines.join(', ')}',
      if (route.preferredDestinations.isNotEmpty)
        'hacia ${route.preferredDestinations.map(spokenName).join(', ')}',
    ].join(', ');
