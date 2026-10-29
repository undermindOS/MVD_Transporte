import 'package:flutter/material.dart';

import '../services/official_sites.dart';
import 'app_lock.dart';
import 'info_page.dart';
import 'map/mapa_page.dart';
import 'services_page.dart';
import 'stops_page.dart';
import 'widgets/pixel_icon.dart';
import 'widgets/timbre_app_bar.dart';

// ---------------------------------------------------------------------------
// Tab model — single source of truth for navigation structure
// ---------------------------------------------------------------------------

class _TabDef {
  final String label;
  final PixelGlyph icon;

  /// Line under the page title in the header.
  final String? subtitle;

  const _TabDef({
    required this.label,
    required this.icon,
    this.subtitle,
  });
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

/// Native tabs only: Mis paradas, Mapa and Servicios. Mi STM, Recarga, Cómo
/// Ir and Avisos are official sites and open in the system browser (see
/// [OfficialSite]).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// Pages pushed over the home page (Horarios, Info): Mis paradas and the
  /// Mapa stop polling while one covers them. Registered in `main.dart`. A
  /// dialog or a sheet leaves the board in sight, so only full pages count.
  static final routeObserver = RouteObserver<PageRoute<dynamic>>();

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  // Indexes into [_tabs] and the IndexedStack
  static const _stopsTab = 0;
  static const _mapaTab = 1;

  int _currentIndex = _stopsTab;

  // A page pushed on top (Horarios, Info) hides the tabs
  bool _covered = false;

  // The Mapa is built on its first visit, then kept (camera included):
  // nothing of it loads or polls before
  bool _mapaOpened = false;

  // --- Tab definitions (order matters) ---
  static const List<_TabDef> _tabs = [
    _TabDef(
      label: 'Mis paradas',
      icon: PixelGlyphs.bus,
    ),
    // No subtitle: the map keeps the room
    _TabDef(
      label: 'Mapa',
      icon: PixelGlyphs.streets,
    ),
    _TabDef(
      label: 'Servicios',
      icon: PixelGlyphs.grid,
      subtitle: 'Sitios oficiales, en tu navegador',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) HomePage.routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    HomePage.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() => setState(() => _covered = false);

  // --- System browser ---

  Future<void> _openInBrowser(Uri uri) async {
    final opened = await SystemBrowser.open(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No se pudo abrir el navegador. Revisá que tengas uno activado.'),
      ));
    }
  }

  void _openInfoPage() {
    final lock = AppLock.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InfoPage(
          biometricLockEnabled: lock.enabled,
          onToggleBiometricLock: lock.setEnabled,
        ),
      ),
    );
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    // Under the lock screen (see AppLock) the page stays built, out of sight
    final locked = AppLock.of(context).locked;
    // Polls only while on screen
    final mapaActive = _currentIndex == _mapaTab && !_covered && !locked;

    return Scaffold(
      appBar: buildTimbreAppBar(
        context,
        title: _tabs[_currentIndex].label,
        subtitle: _tabs[_currentIndex].subtitle,
        actions: [
          IconButton(
            icon: const PixelIcon(PixelGlyphs.info),
            tooltip: 'Info',
            onPressed: _openInfoPage,
          ),
        ],
      ),
      // Keeps each tab's state (loaded arrivals, selected sub-tab)
      body: IndexedStack(
        index: _currentIndex,
        children: [
          StopsPage(
            // Polls only while on screen
            active: _currentIndex == _stopsTab && !_covered && !locked,
            onOpenStopInComoIr: (stopId) =>
                _openInBrowser(OfficialSite.comoIrStop(stopId)),
          ),
          if (_mapaOpened)
            // The IndexedStack keeps a hidden tab's tickers running
            TickerMode(
              enabled: mapaActive,
              child: MapaPage(active: mapaActive),
            )
          else
            const SizedBox.shrink(),
          ServicesPage(onOpen: (site) => _openInBrowser(site.uri)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() {
          _currentIndex = index;
          if (index == _mapaTab) _mapaOpened = true;
        }),
        destinations: _tabs
            .map((tab) => NavigationDestination(
                  icon: PixelIcon(tab.icon),
                  // The selected tab is lit
                  selectedIcon: PixelIcon(tab.icon, glow: true),
                  label: tab.label,
                ))
            .toList(),
      ),
    );
  }
}
