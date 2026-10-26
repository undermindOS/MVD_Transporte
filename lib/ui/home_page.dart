import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import '../services/background_worker.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../services/official_sites.dart';
import 'info_page.dart';
import 'lock_screen.dart';
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

/// Native tabs only. Mi STM, Recarga, Cómo Ir and Avisos are official sites
/// and open in the system browser (see [OfficialSite]).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // Authentication
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _biometricLockEnabled = false;
  // The system auth UI (esp. PIN/pattern fallback on Android) pauses and
  // resumes the activity; without this guard resume would re-lock in a loop.
  bool _isAuthenticating = false;
  DateTime? _lastAuthFinishedAt;
  bool _setupDone = false;

  // A Custom Tab is another activity: opening one pauses the app, and coming
  // back from it must not re-lock. Only a pause that starts right after the
  // launch counts, so a later trip to the background still locks.
  DateTime? _browserOpenedAt;
  DateTime? _leftAt;

  // Device has no usable lock method — locking would trap the user forever.
  static const _authUnavailableCodes = {
    auth_error.notAvailable,
    auth_error.notEnrolled,
    auth_error.passcodeNotSet,
  };

  // --- Tab definitions (order matters) ---
  static const List<_TabDef> _tabs = [
    _TabDef(
      label: 'Mis paradas',
      icon: PixelGlyphs.bus,
    ),
    _TabDef(
      label: 'Servicios',
      icon: PixelGlyphs.grid,
      subtitle: 'Sitios oficiales, en tu navegador',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBiometricSetting();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResume();
    } else {
      _leftAt ??= DateTime.now();
    }
  }

  Future<void> _handleResume() async {
    final justAuthenticated = _lastAuthFinishedAt != null &&
        DateTime.now().difference(_lastAuthFinishedAt!) <
            const Duration(seconds: 2);
    final backFromBrowser = _browserOpenedAt != null &&
        _leftAt != null &&
        _leftAt!.difference(_browserOpenedAt!) < const Duration(seconds: 3);
    _browserOpenedAt = null;
    _leftAt = null;
    if (_biometricLockEnabled &&
        !_isAuthenticating &&
        !justAuthenticated &&
        !backFromBrowser) {
      setState(() => _isAuthenticated = false);
      await _authenticate();
    }
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
        localizedReason: 'Autenticate para acceder a Timbre MVD',
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
      ));
    }
    return value;
  }

  // --- System browser ---

  Future<void> _openInBrowser(Uri uri) async {
    _browserOpenedAt = DateTime.now();
    final opened = await SystemBrowser.open(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir el navegador'),
      ));
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
            onOpenStopInComoIr: (stopId) =>
                _openInBrowser(OfficialSite.comoIrStop(stopId)),
          ),
          ServicesPage(onOpen: (site) => _openInBrowser(site.uri)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
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

  /// The LED board with the lock; the button opens the system prompt.
  Widget _buildLockScreen() => LockScreen(onUnlock: _authenticate);
}
