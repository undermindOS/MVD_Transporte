import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/balance_scraper.dart';
import '../services/background_worker.dart';
import '../services/comoir_scraper.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import 'info_page.dart';
import 'stops_page.dart';

// ---------------------------------------------------------------------------
// Tab model — single source of truth for navigation structure
// ---------------------------------------------------------------------------

enum _TabKind { webview, native }

class _TabDef {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final _TabKind kind;
  final String? url;
  final Widget Function()? pageBuilder;

  const _TabDef({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.kind,
    this.url,
    this.pageBuilder,
  });

  bool get isWebView => kind == _TabKind.webview;
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

class TransporteWebViewPage extends StatefulWidget {
  const TransporteWebViewPage({super.key});

  @override
  State<TransporteWebViewPage> createState() => _TransporteWebViewPageState();
}

class _TransporteWebViewPageState extends State<TransporteWebViewPage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _canGoBack = false;
  int _currentIndex = 0;

  // Cache native page widgets to avoid recreating on every rebuild
  final Map<int, Widget> _nativePageCache = {};

  // Authentication
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _biometricLockEnabled = false;

  // Session freshness tracking
  static const Duration _sessionRefreshThreshold = Duration(hours: 2);

  // Transport Service URLs
  static const String _mainUrl =
      'https://stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml';
  static const String _topUpUrl =
      'https://stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml';
  static const String _notificationsUrl =
      'https://stm.gub.uy/app/mistm/cuenta/pages/notificaciones.xhtml';
  static const String _howToGoUrl = 'https://m.montevideo.gub.uy/comoir/';

  // --- Tab definitions (order matters) ---
  static final List<_TabDef> _tabs = [
    const _TabDef(
      label: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      kind: _TabKind.webview,
      url: _mainUrl,
    ),
    const _TabDef(
      label: 'Recarga',
      icon: Icons.credit_card_outlined,
      selectedIcon: Icons.credit_card,
      kind: _TabKind.webview,
      url: _topUpUrl,
    ),
    _TabDef(
      label: 'Mis paradas',
      icon: Icons.directions_bus_outlined,
      selectedIcon: Icons.directions_bus,
      kind: _TabKind.native,
      pageBuilder: () => const StopsPage(),
    ),
    const _TabDef(
      label: 'Cómo Ir',
      icon: Icons.map_outlined,
      selectedIcon: Icons.map,
      kind: _TabKind.webview,
      url: _howToGoUrl,
    ),
    const _TabDef(
      label: 'Avisos',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      kind: _TabKind.webview,
      url: _notificationsUrl,
    ),
  ];

  /// Current tab is the WebView tab?
  bool get _isWebViewTab => _tabs[_currentIndex].isWebView;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBiometricSetting();
    _requestLocationPermission();
    _initializeWebView();
    _loadInitialUrl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveLastActiveTime();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  Future<void> _handleResume() async {
    if (_biometricLockEnabled) {
      setState(() => _isAuthenticated = false);
      await _authenticate();
    }
    if (_isAuthenticated) {
      _refreshIfSessionStale();
    }
  }

  // --- Session management (using CacheService) ---

  Future<void> _saveLastActiveTime() async {
    await CacheService.set(
      CacheService.keyLastActiveTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _loadInitialUrl() async {
    final lastActiveMs =
        CacheService.get<int>(CacheService.keyLastActiveTime);
    await CacheService.set(
      CacheService.keyLastActiveTime,
      DateTime.now().millisecondsSinceEpoch,
    );

    if (lastActiveMs != null) {
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastActiveMs),
      );
      if (elapsed >= _sessionRefreshThreshold) {
        debugPrint(
            '⏰ Инактивность ${elapsed.inHours}ч — очищаем кеш WebView');
        await _controller.clearCache();
      }
    }

    await _controller.loadRequest(Uri.parse(_mainUrl));
  }

  Future<void> _refreshIfSessionStale() async {
    final lastActiveMs =
        CacheService.get<int>(CacheService.keyLastActiveTime);
    if (lastActiveMs == null) return;

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastActiveMs),
    );

    if (elapsed >= _sessionRefreshThreshold) {
      debugPrint('⏰ Resuming after ${elapsed.inHours}h — refreshing session');
      await _controller.clearCache();
      if (mounted) {
        setState(() => _currentIndex = 0);
        await _controller.loadRequest(Uri.parse(_mainUrl));
      }
    }

    await CacheService.set(
      CacheService.keyLastActiveTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // --- Permissions & auth ---

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    debugPrint(status.isGranted
        ? '✅ Location permission granted'
        : '❌ Location permission denied');
  }

  Future<void> _loadBiometricSetting() async {
    final enabled =
        CacheService.get<bool>(CacheService.keyBiometricEnabled) ?? false;
    setState(() => _biometricLockEnabled = enabled);

    if (_biometricLockEnabled) {
      await _authenticate();
    } else {
      setState(() => _isAuthenticated = true);
      await _setupAfterAuth();
    }
  }

  Future<void> _setupAfterAuth() async {
    await NotificationService.requestPermissions();
    if (CacheService.getStopsWithNotificationsEnabled().isNotEmpty) {
      await BackgroundWorker.registerPeriodicTask();
    }
  }

  Future<void> _authenticate() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canAuth && !isSupported) {
        setState(() => _isAuthenticated = true);
        await _setupAfterAuth();
        return;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'Autentícate para acceder a MVD Transporte',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      setState(() => _isAuthenticated = ok);
      if (ok) {
        await _setupAfterAuth();
      }
      // При неудачной аутентификации оставляем экран блокировки
      // с кнопкой «Desbloquear» для повторной попытки
    } catch (e) {
      debugPrint('❌ Authentication error: $e');
      setState(() => _isAuthenticated = true);
      await _setupAfterAuth();
    }
  }

  Future<void> _toggleBiometricLock(bool value) async {
    if (value) {
      final canAuth = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canAuth && !isSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Tu dispositivo no soporta autenticación biométrica'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      try {
        final ok = await _localAuth.authenticate(
          localizedReason: 'Confirma para activar el bloqueo biométrico',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
        if (!ok) return;
      } catch (e) {
        debugPrint('❌ Authentication error: $e');
        return;
      }
    }

    await CacheService.set(CacheService.keyBiometricEnabled, value);
    setState(() => _biometricLockEnabled = value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Bloqueo biométrico activado'
            : 'Bloqueo biométrico desactivado'),
        backgroundColor: value ? Colors.green : Colors.orange,
      ));
    }
  }

  // --- WebView ---

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (url) async {
            setState(() => _isLoading = false);
            final canGoBack = await _controller.canGoBack();
            setState(() => _canGoBack = canGoBack);
            // Try to extract card balance for home screen widget
            await BalanceScraper.tryExtract(_controller, url);
            // Try to extract active route from Cómo Ir page
            await ComoIrScraper.tryExtract(_controller, url);
          },
          onWebResourceError: (error) {
            debugPrint(
                '❌ WebView Error ${error.errorCode}: ${error.description}');
          },
          onNavigationRequest: (request) {
            debugPrint('🔗 Navigating to: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  void _switchToTab(int index) {
    setState(() => _currentIndex = index);
    final tab = _tabs[index];
    if (tab.isWebView && tab.url != null) {
      _controller.loadRequest(Uri.parse(tab.url!));
    }
  }

  void _openInfoPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InfoPage(
          biometricLockEnabled: _biometricLockEnabled,
          onToggleBiometricLock: _toggleBiometricLock,
        ),
      ),
    );
    // Refresh state after returning from Info page (biometric toggle may have changed)
    if (mounted) {
      final enabled =
          CacheService.get<bool>(CacheService.keyBiometricEnabled) ?? false;
      setState(() => _biometricLockEnabled = enabled);
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    if (_biometricLockEnabled && !_isAuthenticated) {
      return _buildLockScreen();
    }

    return PopScope(
      canPop: !_canGoBack || !_isWebViewTab,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && _canGoBack && _isWebViewTab) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _tabs[_currentIndex].label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Info',
              onPressed: _openInfoPage,
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _switchToTab,
          destinations: _tabs
              .map((tab) => NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label,
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final tab = _tabs[_currentIndex];

    if (tab.isWebView) {
      return Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).primaryColor,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cargando...',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    // Native tab — cache widget to avoid recreating on every rebuild
    return _nativePageCache.putIfAbsent(
      _currentIndex,
      () => tab.pageBuilder!(),
    );
  }

  Widget _buildLockScreen() {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primary, primary.withAlpha((0.7 * 255).toInt())],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 100, color: Colors.white),
                const SizedBox(height: 32),
                const Text(
                  'MVD Transporte',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Aplicación bloqueada',
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.fingerprint, size: 28),
                  label: const Text(
                    'Desbloquear',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
