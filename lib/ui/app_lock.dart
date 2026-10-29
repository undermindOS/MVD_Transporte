import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import '../services/background_worker.dart';
import '../services/cache_service.dart';
import '../services/device_auth.dart';
import '../services/external_apps.dart';
import '../services/notification_service.dart';
import 'lock_screen.dart';

/// The biometric lock, above the Navigator (`MaterialApp.builder` in
/// `main.dart`): while locked, every page, sheet, dialog and snackbar of the
/// app is under the lock screen — not painted, not tappable, not focusable,
/// not heard by TalkBack or VoiceOver — and the back button closes none of
/// them.
///
/// Before the first unlock the app is not built at all, so nothing loads.
/// After it, the app stays mounted under the lock: unlocking brings back the
/// same page, sheet or dialog.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.deviceAuth, required this.child});

  final DeviceAuth deviceAuth;

  /// The app's Navigator.
  final Widget child;

  /// Holds back the pages, sheets and dialogs pushed over the home page
  /// while the app is locked. Registered in `main.dart`.
  static NavigatorObserver get routeGuard => _routeGuard;
  static final _routeGuard = _RouteGuard();

  /// The phone's clock: when the app left, when a prompt closed. Tests move
  /// it forward.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// The lock above [context]. The caller rebuilds when [AppLockState.locked]
  /// or [AppLockState.enabled] change.
  static AppLockState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppLockScope>();
    assert(scope != null, 'No AppLock above this context');
    return scope!.state;
  }

  @override
  State<AppLock> createState() => AppLockState();
}

class AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  // The app is built from the first unlock on
  bool _unlockedOnce = false;
  // The system auth UI (esp. PIN/pattern fallback on Android) pauses and
  // resumes the activity; without this guard resume would re-lock in a loop.
  bool _isAuthenticating = false;
  DateTime? _lastAuthFinishedAt;
  bool _setupDone = false;

  // A Custom Tab or the mail app is another activity: opening one pauses the
  // app, and coming back from it must not re-lock. Only a pause that starts
  // right after the launch counts, so a later trip to the background still
  // locks.
  DateTime? _launchedAt;
  DateTime? _leftAt;

  // Device has no usable lock method — locking would trap the user forever.
  static const _authUnavailableCodes = {
    auth_error.notAvailable,
    auth_error.notEnrolled,
    auth_error.passcodeNotSet,
  };

  /// The lock screen is up.
  bool get locked => _locked;

  /// The person turned the lock on in Info.
  bool get enabled => _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ExternalApps.launches.addListener(_onExternalLaunch);
    _enabled =
        CacheService.get<bool>(CacheService.keyBiometricEnabled) ?? false;
    _setLocked(_enabled);
    if (_enabled) {
      _authenticate();
    } else {
      _unlock();
    }
  }

  @override
  void dispose() {
    ExternalApps.launches.removeListener(_onExternalLaunch);
    WidgetsBinding.instance.removeObserver(this);
    AppLock._routeGuard.locked = false;
    super.dispose();
  }

  void _setLocked(bool value) {
    if (!mounted) return;
    setState(() {
      _locked = value;
      if (!value) _unlockedOnce = true;
    });
    AppLock._routeGuard.locked = value;
  }

  void _onExternalLaunch() => _launchedAt = AppLock.clock();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleResume();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _leftAt ??= AppLock.clock();
      // A system dialog (a permission request) or a peek at the recent apps
      // only makes the app inactive: it never left
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _handleResume() async {
    final leftAt = _leftAt;
    if (leftAt == null) return;
    final launchedAt = _launchedAt;
    _leftAt = null;
    _launchedAt = null;
    final justAuthenticated = _lastAuthFinishedAt != null &&
        AppLock.clock().difference(_lastAuthFinishedAt!) <
            const Duration(seconds: 2);
    final backFromAppOpenedHere = launchedAt != null &&
        leftAt.difference(launchedAt) < const Duration(seconds: 3);
    if (_enabled &&
        !_isAuthenticating &&
        !justAuthenticated &&
        !backFromAppOpenedHere) {
      _setLocked(true);
      await _authenticate();
    }
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    _setLocked(false);
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
      if (!await widget.deviceAuth.isAvailable()) {
        await _unlock();
        return;
      }

      final ok = await widget.deviceAuth
          .authenticate('Autenticate para acceder a Timbre MVD');

      if (ok) {
        await _unlock();
      }
      // A failed or cancelled prompt leaves the lock screen, with
      // «Desbloquear» to try again
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
      _lastAuthFinishedAt = AppLock.clock();
    }
  }

  /// Turns the lock on (after the system prompt confirms it) or off, from
  /// the Info switch. Returns the resulting state, so the switch can
  /// reflect a cancelled confirmation.
  Future<bool> setEnabled(bool value) async {
    if (value) {
      if (!await widget.deviceAuth.isAvailable()) {
        if (mounted) {
          // biometricOnly is off: a PIN or a pattern is enough
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tu dispositivo no tiene bloqueo de pantalla. '
                'Configuralo en Ajustes.'),
          ));
        }
        return _enabled;
      }

      _isAuthenticating = true;
      try {
        final ok = await widget.deviceAuth
            .authenticate('Confirmá para activar el bloqueo biométrico');
        if (!ok) return _enabled;
      } catch (e) {
        debugPrint('❌ Authentication error: $e');
        return _enabled;
      } finally {
        _isAuthenticating = false;
        _lastAuthFinishedAt = AppLock.clock();
      }
    }

    await CacheService.set(CacheService.keyBiometricEnabled, value);
    if (mounted) setState(() => _enabled = value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Bloqueo biométrico activado'
            : 'Bloqueo biométrico desactivado'),
      ));
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return _AppLockScope(
      state: this,
      locked: _locked,
      enabled: _enabled,
      child: Stack(fit: StackFit.expand, children: [
        if (_unlockedOnce)
          // Kept mounted, out of sight and out of reach
          Offstage(
            offstage: _locked,
            child: TickerMode(
              enabled: !_locked,
              child: ExcludeFocus(excluding: _locked, child: widget.child),
            ),
          ),
        if (_locked)
          // Its own messenger: the app's snackbars stay with the app
          ScaffoldMessenger(
            // A screen of its own for screen readers, as a page would be
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: LockScreen(onUnlock: _authenticate),
            ),
          ),
      ]),
    );
  }
}

class _AppLockScope extends InheritedWidget {
  const _AppLockScope({
    required this.state,
    required this.locked,
    required this.enabled,
    required super.child,
  });

  final AppLockState state;
  final bool locked;
  final bool enabled;

  @override
  bool updateShouldNotify(_AppLockScope oldWidget) =>
      locked != oldWidget.locked || enabled != oldWidget.enabled;
}

/// While locked, the back button or gesture would close the page, sheet or
/// dialog on top unseen: every route pushed over the first one says it
/// cannot be popped. The first one has nothing under it, so back still
/// leaves the app, as it does on the lock screen.
class _RouteGuard extends NavigatorObserver {
  final _canPop = ValueNotifier<bool>(true);
  late final _hold = _HoldPop(_canPop);

  set locked(bool value) => _canPop.value = !value;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && route is ModalRoute) {
      route.registerPopEntry(_hold);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  void _release(Route<dynamic> route) {
    if (route is ModalRoute) route.unregisterPopEntry(_hold);
  }
}

class _HoldPop extends PopEntry<Object?> {
  _HoldPop(this.canPopNotifier);

  @override
  final ValueListenable<bool> canPopNotifier;
}
