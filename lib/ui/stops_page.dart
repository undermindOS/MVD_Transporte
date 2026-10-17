import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/route_alert.dart';
import '../services/background_worker.dart';
import '../services/cache_service.dart';
import '../services/mvd_api_service.dart';
import '../services/notification_service.dart';

class StopsPage extends StatefulWidget {
  /// Opens the stop in Cómo Ir (official deep link).
  final ValueChanged<int> onOpenStopInComoIr;

  const StopsPage({super.key, required this.onOpenStopInComoIr});

  @override
  State<StopsPage> createState() => _StopsPageState();
}

class _StopsPageState extends State<StopsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Rebuild so the FAB tooltip follows the selected tab
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadAll() {
    _loadStops();
    _loadRoutes();
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
    messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
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

  Future<int?> _showAddStopDialog() async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar parada'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Número de parada',
            hintText: 'Ej: 1234',
            prefixIcon: Icon(Icons.directions_bus),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleStopNotification(BusStop stop) async {
    stop.notificationsEnabled = !stop.notificationsEnabled;
    await stop.save();
    setState(() {});
    await _syncAlerts(enabling: stop.notificationsEnabled);
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
    final filtered = all?.where((a) => route.acceptsLine(a.line)).toList();

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
    snack.showSnackBar(const SnackBar(content: Text('Buscando parada…')));

    final BusStop? resolved;
    try {
      resolved = await MvdApiService.resolveStop(result.originStopId);
    } on StopNotFoundException {
      _showError('No existe la parada ${result.originStopId}');
      return;
    }
    final id = CacheService.nextRouteId();
    final route = RouteAlert(
      id: id,
      originStopId: result.originStopId,
      originName: resolved?.name ?? 'Parada ${result.originStopId}',
      destinationName: result.destinationName,
      preferredLines: result.preferredLines,
    );
    await CacheService.saveRoute(route);

    if (mounted) {
      snack.clearSnackBars();
      _loadRoutes();
      await _syncAlerts(enabling: true);
    }
  }

  Future<_RouteFormData?> _showAddRouteDialog() async {
    final stopCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    final lineCtrl = TextEditingController();
    return showDialog<_RouteFormData>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar ruta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: stopCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Parada de origen *',
                hintText: 'Ej: 1234',
                prefixIcon: Icon(Icons.my_location),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: destCtrl,
              decoration: const InputDecoration(
                labelText: 'Destino *',
                hintText: 'Ej: Centro',
                prefixIcon: Icon(Icons.place),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lineCtrl,
              decoration: const InputDecoration(
                labelText: 'Líneas preferidas (opcional)',
                hintText: 'Ej: 183, 64D',
                prefixIcon: Icon(Icons.directions_bus),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final stopId = int.tryParse(stopCtrl.text);
              if (stopId == null || destCtrl.text.trim().isEmpty) return;
              final lines = lineCtrl.text
                  .split(RegExp(r'[,\s]+'))
                  // API line names are upper case ("64D", "G8")
                  .map((s) => s.trim().toUpperCase())
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(
                ctx,
                _RouteFormData(
                  originStopId: stopId,
                  destinationName: destCtrl.text.trim(),
                  preferredLines: lines,
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRouteEnabled(RouteAlert route) async {
    route.enabled = !route.enabled;
    await route.save();
    setState(() {});
    await _syncAlerts(enabling: route.enabled);
  }

  void _deleteRoute(RouteAlert route) {
    // Dismissible requires the item to leave the list synchronously
    setState(() {
      _routes.removeWhere((r) => r.id == route.id);
      _routeArrivals.remove(route.id);
    });
    CacheService.deleteRoute(route.id).then((_) => _syncAlerts());
  }

  // ---------------------------------------------------------------- Build ---

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: primary,
          indicatorColor: primary,
          tabs: const [
            Tab(icon: Icon(Icons.place_outlined), text: 'Paradas'),
            Tab(icon: Icon(Icons.route_outlined), text: 'Rutas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStopsTab(primary),
          _buildRoutesTab(primary),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _tabController.index == 0
            ? _addStop()
            : _addRouteManually(),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        tooltip: _tabController.index == 0
            ? 'Agregar parada'
            : 'Agregar ruta',
        child: const Icon(Icons.add),
      ),
    );
  }

  // --------------------------------------------------------- Stops tab -----

  Widget _buildStopsTab(Color primary) {
    if (_stops.isEmpty) {
      return _buildEmptyState(
        primary,
        icon: Icons.directions_bus_outlined,
        title: 'Sin paradas guardadas',
        subtitle:
            'Toca + para agregar una parada\ny recibir alertas cuando llegue el colectivo',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        for (final s in _stops) {
          await _refreshStopArrivals(s.id);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _stops.length,
        itemBuilder: (_, i) => _buildStopCard(_stops[i], primary),
      ),
    );
  }

  Widget _buildStopCard(BusStop stop, Color primary) {
    final arrivals = _stopArrivals[stop.id];
    final failed = _stopArrivals.containsKey(stop.id) && arrivals == null;
    final isLoading = _stopLoading[stop.id] ?? false;

    return Dismissible(
      key: Key('stop_${stop.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      onDismissed: (_) => _deleteStop(stop),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.place, color: primary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(stop.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Text('#${stop.id}',
                    style:
                        const TextStyle(color: Colors.black38, fontSize: 13)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _toggleStopNotification(stop),
                  child: Icon(
                    stop.notificationsEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: stop.notificationsEnabled
                        ? primary
                        : Colors.black38,
                    size: 22,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _buildArrivalRow(arrivals, isLoading, failed, primary),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => widget.onOpenStopInComoIr(stop.id),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver en Cómo Ir'),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- Routes tab ----

  Widget _buildRoutesTab(Color primary) {
    return RefreshIndicator(
      onRefresh: () async {
        for (final r in _routes) {
          await _refreshRouteArrivals(r);
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (_routes.isEmpty)
            _buildEmptyState(
              primary,
              icon: Icons.route_outlined,
              title: 'Sin rutas guardadas',
              subtitle: 'Toca + para guardar una alerta de salida',
            )
          else
            ..._routes.map((r) => _buildRouteCard(r, primary)),
        ],
      ),
    );
  }

  Widget _buildRouteCard(RouteAlert route, Color primary) {
    final arrivals = _routeArrivals[route.id];
    final failed = _routeArrivals.containsKey(route.id) && arrivals == null;
    final isLoading = _routeLoading[route.id] ?? false;

    return Dismissible(
      key: Key('route_${route.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      onDismissed: (_) => _deleteRoute(route),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Icon(Icons.my_location, color: primary, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(route.originName,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
                ),
                GestureDetector(
                  onTap: () => _toggleRouteEnabled(route),
                  child: Icon(
                    route.enabled
                        ? Icons.notifications_active
                        : Icons.notifications_off_outlined,
                    color: route.enabled ? primary : Colors.black38,
                    size: 22,
                  ),
                ),
              ]),
              // Arrow + destination
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.arrow_downward,
                      color: primary.withAlpha(120), size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      route.destinationName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              if (route.preferredLines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Líneas: ${route.preferredLines.join(", ")}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45),
                  ),
                ),
              const SizedBox(height: 4),
              _buildArrivalRow(arrivals, isLoading, failed, primary),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- Shared --------

  Widget _buildArrivalRow(List<BusArrival>? arrivals, bool isLoading,
      bool failed, Color primary) {
    if (isLoading) {
      return const SizedBox(
        height: 20,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Offline must not look like "no buses are coming"
    if (failed) {
      return const Text('No se pudo actualizar. Deslizá para reintentar',
          style: TextStyle(color: Colors.redAccent, fontSize: 13));
    }
    if (arrivals == null || arrivals.isEmpty) {
      return const Text('Sin colectivos próximos',
          style: TextStyle(color: Colors.black45, fontSize: 13));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: arrivals
          .take(6)
          .map((a) => _buildArrivalChip(a, primary))
          .toList(),
    );
  }

  Widget _buildArrivalChip(BusArrival arrival, Color primary) {
    final isImminent = arrival.isRealTime && arrival.etaMinutes <= 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isImminent ? primary : primary.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            arrival.line,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isImminent ? Colors.white : primary,
            ),
          ),
          const SizedBox(width: 4),
          // Timetable estimate, not a GPS-tracked bus
          if (!arrival.isRealTime) ...[
            Icon(Icons.schedule, size: 12, color: primary.withAlpha(180)),
            const SizedBox(width: 2),
          ],
          Text(
            arrival.etaLabel,
            style: TextStyle(
              fontSize: 12,
              color: isImminent ? Colors.white70 : primary.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    Color primary, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: primary.withAlpha(100)),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.black45, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _deleteBackground() => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      );
}

/// Internal form data for the add-route dialog.
class _RouteFormData {
  final int originStopId;
  final String destinationName;
  final List<String> preferredLines;

  const _RouteFormData({
    required this.originStopId,
    required this.destinationName,
    required this.preferredLines,
  });
}
