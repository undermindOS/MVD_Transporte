import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

  StreamSubscription<Uri?>? _widgetClickSub;

  // Authentication
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _biometricLockEnabled = false;
  // The system auth UI (esp. PIN/pattern fallback on Android) pauses and
  // resumes the activity; without this guard resume would re-lock in a loop.
  bool _isAuthenticating = false;
  DateTime? _lastAuthFinishedAt;
  bool _setupDone = false;

  // Device has no usable lock method — locking would trap the user forever.
  static const _authUnavailableCodes = {
    auth_error.notAvailable,
    auth_error.notEnrolled,
    auth_error.passcodeNotSet,
  };

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
    // Location is requested in context, when Cómo Ir asks for it
    _initializeWebView();
    _loadInitialUrl();
    // Home screen widget buttons while the app is already running
    _widgetClickSub = HomeWidget.widgetClicked.listen(
      (uri) {
        final index = _tabIndexFromWidgetUri(uri);
        if (index != null && mounted) _switchToTab(index);
      },
      onError: (Object e) => debugPrint('⚠️ widgetClicked error: $e'),
    );
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Widget buttons send mvdtransporte://tab?index=N (see
  /// MVDTransporteWidgetProvider.kt).
  static int? _tabIndexFromWidgetUri(Uri? uri) {
    if (uri == null || uri.scheme != 'mvdtransporte' || uri.host != 'tab') {
      return null;
    }
    final index = int.tryParse(uri.queryParameters['index'] ?? '');
    return index != null && index >= 0 && index < _tabs.length ? index : null;
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
    final justAuthenticated = _lastAuthFinishedAt != null &&
        DateTime.now().difference(_lastAuthFinishedAt!) <
            const Duration(seconds: 2);
    if (_biometricLockEnabled && !_isAuthenticating && !justAuthenticated) {
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

    // Cold start from a home screen widget button opens that tab
    Uri? launchUri;
    try {
      launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (e) {
      debugPrint('⚠️ HomeWidget launch check error: $e');
    }
    final widgetTab = _tabIndexFromWidgetUri(launchUri);
    if (widgetTab != null && mounted) {
      _switchToTab(widgetTab);
      return;
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

  Future<void> _loadBiometricSetting() async {
    final enabled =
        CacheService.get<bool>(CacheService.keyBiometricEnabled) ?? false;
    setState(() => _biometricLockEnabled = enabled);

    if (_biometricLockEnabled) {
      await _authenticate();
    } else {
      await _unlock();
    }
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    setState(() => _isAuthenticated = true);
    await _setupAfterAuth();
  }

  /// One-time setup after the first unlock. Notification permission is asked
  /// only if the user already has alerts (otherwise when enabling one).
  Future<void> _setupAfterAuth() async {
    if (_setupDone) return;
    _setupDone = true;
    if (BackgroundWorker.hasActiveAlerts) {
      await NotificationService.requestPermissions();
    }
    await BackgroundWorker.sync();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canAuth && !isSupported) {
        await _unlock();
        return;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'Autentícate para acceder a MVD Transporte',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (ok) {
        await _unlock();
      } else if (mounted) {
        setState(() => _isAuthenticated = false);
      }
      // При неудачной аутентификации оставляем экран блокировки
      // с кнопкой «Desbloquear» для повторной попытки
    } on PlatformException catch (e) {
      debugPrint('❌ Authentication error: ${e.code} ${e.message}');
      // Fail closed: LockedOut / PermanentlyLockedOut keep the lock screen.
      // Only open when the device has no lock method at all.
      if (_authUnavailableCodes.contains(e.code)) {
        await _unlock();
      }
    } catch (e) {
      debugPrint('❌ Authentication error: $e');
    } finally {
      _isAuthenticating = false;
      _lastAuthFinishedAt = DateTime.now();
    }
  }

  /// Returns the resulting state of the lock (so the Info page switch can
  /// reflect a cancelled confirmation).
  Future<bool> _toggleBiometricLock(bool value) async {
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
        return _biometricLockEnabled;
      }

      _isAuthenticating = true;
      try {
        final ok = await _localAuth.authenticate(
          localizedReason: 'Confirma para activar el bloqueo biométrico',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
        if (!ok) return _biometricLockEnabled;
      } catch (e) {
        debugPrint('❌ Authentication error: $e');
        return _biometricLockEnabled;
      } finally {
        _isAuthenticating = false;
        _lastAuthFinishedAt = DateTime.now();
      }
    }

    await CacheService.set(CacheService.keyBiometricEnabled, value);
    if (mounted) setState(() => _biometricLockEnabled = value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Bloqueo biométrico activado'
            : 'Bloqueo biométrico desactivado'),
        backgroundColor: value ? Colors.green : Colors.orange,
      ));
    }
    return value;
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
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _isLoading = false);
            await _updateCanGoBack();
            // Try to extract card balance for home screen widget
            await BalanceScraper.tryExtract(_controller, url);
            // Try to extract active route from Cómo Ir page
            await ComoIrScraper.tryExtract(_controller, url);
          },
          // SPA navigation (Cómo Ir) changes history without onPageFinished
          onUrlChange: (_) => _updateCanGoBack(),
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

    // Android WebView denies the Geolocation API unless the host app grants
    // it per origin — without this, "mi ubicación" in Cómo Ir never works.
    // (iOS WKWebView asks the user on its own.)
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          final host = Uri.tryParse(request.origin)?.host ?? '';
          if (!_isOfficialHost(host)) {
            return const GeolocationPermissionsResponse(
                allow: false, retain: false);
          }
          final status = await Permission.location.request();
          return GeolocationPermissionsResponse(
              allow: status.isGranted, retain: false);
        },
      );
    }
  }

  static bool _isOfficialHost(String host) =>
      host == 'montevideo.gub.uy' ||
      host.endsWith('.montevideo.gub.uy') ||
      host == 'stm.gub.uy' ||
      host.endsWith('.stm.gub.uy');

  Future<void> _updateCanGoBack() async {
    final canGoBack = await _controller.canGoBack();
    if (mounted) setState(() => _canGoBack = canGoBack);
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
