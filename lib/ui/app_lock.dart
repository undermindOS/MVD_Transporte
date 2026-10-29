import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_passcode.dart';
import '../services/background_worker.dart';
import '../services/cache_service.dart';
import '../services/device_auth.dart';
import '../services/external_apps.dart';
import '../services/notification_service.dart';
import 'lock_screen.dart';
import 'passcode_entry.dart';

/// The lock, above the Navigator (`MaterialApp.builder` in `main.dart`):
/// while locked, every page, sheet, dialog and snackbar of the app is under
/// the lock screen — not painted, not tappable, not focusable, not heard by
/// TalkBack or VoiceOver — and the back button closes none of them.
///
/// The app's own code opens it, typed on the keypad; with the quick unlock
/// on, a fingerprint or a face opens it first. A forgotten code: the phone's
/// own screen lock, then a new code. The older lock — the phone's prompt
/// only, from before the app had a code — stays until the welcome ends.
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

  /// The lock above [context]. The caller rebuilds when what the getters of
  /// [AppLockState] return changes.
  static AppLockState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AppLockScope>();
    assert(scope != null, 'No AppLock above this context');
    return scope!.state;
  }

  @override
  State<AppLock> createState() => AppLockState();
}

class AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool _hasCode = false;
  // The older lock: on without a code, until the welcome sets one or turns
  // the lock off
  bool _legacy = false;
  bool _biometric = false;
  BiometricKind? _biometricKind;
  bool _locked = false;
  // The app is built from the first unlock on
  bool _unlockedOnce = false;
  // The system auth UI (esp. PIN/pattern fallback on Android) pauses and
  // resumes the activity; without this guard resume would re-lock in a loop.
  bool _isAuthenticating = false;
  DateTime? _lastAuthFinishedAt;
  bool _setupDone = false;
  // After «¿Olvidaste el código?» and the phone's lock: a new code
  bool _choosingNewCode = false;
  // «¿Olvidaste el código?» on a phone without a screen lock
  bool _noScreenLock = false;
  // Gone and back while a prompt opened from the open app (Info, the
  // welcome) was up: it locks when that prompt closes without a yes
  bool _tripDuringPrompt = false;
  // Every lock gets a fresh lock screen: no digit typed before it stays
  int _lockCount = 0;

  // A Custom Tab or the mail app is another activity: opening one pauses the
  // app, and coming back from it must not re-lock. Only a pause that starts
  // right after the launch counts, so a later trip to the background still
  // locks.
  DateTime? _launchedAt;
  DateTime? _leftAt;

  /// The lock screen is up.
  bool get locked => _locked;

  /// A lock is on: the app's code, or the older lock until the welcome
  /// ends.
  bool get enabled => _hasCode || _legacy;

  /// The app has a code of its own.
  bool get hasCode => _hasCode;

  /// A fingerprint or a face opens the app in place of the code. Only with
  /// a code.
  bool get biometric => _hasCode && _biometric;

  /// What the phone offers for the quick unlock; null when nothing is
  /// enrolled. [refreshBiometrics] asks again.
  BiometricKind? get biometricKind => _biometricKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ExternalApps.launches.addListener(_onExternalLaunch);
    _hasCode = AppPasscode.isSet;
    _legacy = !_hasCode &&
        (CacheService.get<bool>(CacheService.keyBiometricEnabled) ?? false);
    _biometric =
        CacheService.get<bool>(CacheService.keyLockBiometric) ?? false;
    _setLocked(enabled);
    if (enabled) {
      _askOnLock();
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
      if (value) _lockCount++;
      _locked = value;
      if (!value) _unlockedOnce = true;
      _choosingNewCode = false;
      _noScreenLock = false;
    });
    AppLock._routeGuard.locked = value;
  }

  // Scans the lock and holds the keypad while a system prompt is open
  void _setAuthenticating(bool value) {
    _isAuthenticating = value;
    if (mounted) setState(() {});
  }

  /// After a prompt opened from the open app: the 2 s for the pause and
  /// resume it may cause, and the lock it held back if the app left while
  /// it was up. A yes ends it there: only the phone's owner gets one.
  void _promptFromAppClosed({required bool yes}) {
    _setAuthenticating(false);
    _lastAuthFinishedAt = AppLock.clock();
    if (!_tripDuringPrompt) return;
    _tripDuringPrompt = false;
    if (!yes && enabled && !_locked) {
      _setLocked(true);
      unawaited(_askOnLock());
    }
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
    if (!enabled || justAuthenticated || backFromAppOpenedHere) return;
    if (_isAuthenticating) {
      // Back with a prompt still up. On the lock screen the lock stays as it
      // is; over the open app the prompt decides when it closes (a sticky
      // prompt outlives the trip, and Android's PIN screen pauses the app)
      if (!_locked) _tripDuringPrompt = true;
      return;
    }
    _setLocked(true);
    await _askOnLock();
  }

  /// What a lock asks first: with a code, the quick unlock if it is on (the
  /// keypad is under it); with the older lock, the phone's prompt.
  Future<void> _askOnLock() async {
    if (_hasCode) {
      await refreshBiometrics();
      if (biometric && _biometricKind != null && _locked) {
        await _promptBiometric();
      }
    } else if (_legacy) {
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

  /// The older lock: the phone's prompt, which takes its screen lock too.
  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    _setAuthenticating(true);
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
      // Fail closed: LockedOut / PermanentlyLockedOut keep the lock screen,
      // and so does any code while the phone still has a lock method (on
      // iOS NotAvailable also follows a failed try). Only open when it has
      // none: locking would trap the user forever.
      if (!await widget.deviceAuth.isAvailable()) {
        await _unlock();
      }
    } catch (e) {
      debugPrint('❌ Authentication error: $e');
    } finally {
      _setAuthenticating(false);
      _lastAuthFinishedAt = AppLock.clock();
    }
  }

  /// The quick unlock: a fingerprint or a face. Only a yes opens; a cancel,
  /// «Usar código», a lockout or any error leaves the keypad.
  Future<void> _promptBiometric() async {
    if (_isAuthenticating || _biometricKind == null) return;
    _setAuthenticating(true);
    try {
      final ok = await widget.deviceAuth
          .authenticate('Desbloqueá Timbre MVD', biometricOnly: true);
      if (ok && _locked) await _unlock();
    } catch (e) {
      debugPrint('❌ Quick unlock: $e');
    } finally {
      _setAuthenticating(false);
      _lastAuthFinishedAt = AppLock.clock();
    }
  }

  /// A code typed on the lock screen.
  Future<PasscodeFeedback?> _onCode(String code) async {
    switch (await AppPasscode.check(code)) {
      case CodeCheck.ok:
        await _unlock();
        return null;
      case CodeCheck.wrong:
        return const PasscodeError('Código incorrecto');
      case CodeCheck.wait:
        return PasscodeWait(
            AppPasscode.waitUntil ?? AppLock.clock().add(AppPasscode.wait));
    }
  }

  /// «¿Olvidaste el código?»: the phone's own lock opens the app, then the
  /// lock screen asks for a new code. A phone without a screen lock cannot
  /// tell who holds it, so then nothing opens.
  Future<void> _forgot() async {
    // The note comes back as news if this one finds no screen lock either
    if (_noScreenLock) setState(() => _noScreenLock = false);
    final confirmed = await confirmWithPhoneLock(
        'Usá el bloqueo de tu teléfono para entrar a Timbre MVD');
    if (!mounted || !_locked) return;
    setState(() {
      _choosingNewCode = confirmed == true;
      _noScreenLock = confirmed == null;
    });
  }

  /// The phone's own lock (PIN, pattern, password or its biometrics) in
  /// place of a forgotten code, with [reason] in the prompt: true when it
  /// confirmed, false when it did not, null when the phone has no screen
  /// lock and cannot confirm anything. A confirmation forgets the wrong
  /// codes and the wait, as the right code does.
  ///
  /// From the open app (Info) the prompt does not outlive a trip to the
  /// background, and such a trip without a yes locks the app.
  Future<bool?> confirmWithPhoneLock(String reason) async {
    if (_isAuthenticating) return false;
    final fromApp = !_locked;
    _setAuthenticating(true);
    bool? confirmed = false;
    try {
      if (await widget.deviceAuth.isAvailable()) {
        confirmed =
            await widget.deviceAuth.authenticate(reason, sticky: !fromApp);
        if (confirmed) AppPasscode.forgetWrongCodes();
      } else {
        confirmed = null;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Phone lock: ${e.code} ${e.message}');
      confirmed = await widget.deviceAuth.isAvailable() ? false : null;
    } catch (e) {
      debugPrint('❌ Phone lock: $e');
      confirmed = false;
    } finally {
      _promptFromAppClosed(yes: confirmed == true);
    }
    return confirmed;
  }

  /// The new code after «¿Olvidaste el código?».
  Future<void> _onNewCode(String code) async {
    await AppPasscode.set(code);
    await _unlock();
  }

  /// Asks the phone again what it offers for the quick unlock.
  Future<BiometricKind?> refreshBiometrics() async {
    final kind = await widget.deviceAuth.biometrics();
    if (mounted && kind != _biometricKind) {
      setState(() => _biometricKind = kind);
    }
    return kind;
  }

  /// Saves [code] as the app's code and drops the older lock. Does not lock
  /// now: the next trip to the background does.
  Future<void> setCode(String code) async {
    await AppPasscode.set(code);
    unawaited(CacheService.remove(CacheService.keyBiometricEnabled));
    if (mounted) {
      setState(() {
        _hasCode = true;
        _legacy = false;
      });
    }
  }

  /// Checks [code] against the app's code (Info: change it, turn it off).
  /// Wrong codes count toward the wait, as on the lock screen.
  Future<CodeCheck> checkCode(String code) => AppPasscode.check(code);

  /// Turns every lock off: the code, the quick unlock, the older lock.
  void removeLock() {
    AppPasscode.clear();
    unawaited(CacheService.remove(CacheService.keyLockBiometric));
    unawaited(CacheService.remove(CacheService.keyBiometricEnabled));
    setState(() {
      _hasCode = false;
      _legacy = false;
      _biometric = false;
    });
  }

  /// Turns the quick unlock on, once the system prompt has seen a
  /// fingerprint or a face, or off. Needs a code and enrolled biometrics.
  /// Returns the resulting state, so a switch can reflect a cancelled
  /// prompt. The prompt does not outlive a trip to the background, and such
  /// a trip without a yes locks the app.
  Future<bool> setBiometric(bool value) async {
    if (!value) {
      unawaited(CacheService.remove(CacheService.keyLockBiometric));
      if (mounted) setState(() => _biometric = false);
      return false;
    }
    if (!_hasCode || _isAuthenticating) return biometric;
    final kind = await refreshBiometrics();
    if (kind == null) return biometric;

    _setAuthenticating(true);
    var ok = false;
    try {
      ok = await widget.deviceAuth.authenticate(
          'Confirmá para abrir Timbre MVD con ${kind.phrase}',
          biometricOnly: true,
          sticky: false);
    } catch (e) {
      debugPrint('❌ Quick unlock: $e');
    } finally {
      _promptFromAppClosed(yes: ok);
    }
    if (!ok) return biometric;

    unawaited(CacheService.set(CacheService.keyLockBiometric, true));
    if (mounted) setState(() => _biometric = true);
    return true;
  }

  Widget _lockScreen() {
    // The older lock
    if (!_hasCode) return LockScreen(onUnlock: _authenticate);
    if (_choosingNewCode) {
      return NewCodeScreen(onCreated: _onNewCode, onSkip: _unlock);
    }
    final kind = _biometricKind;
    return CodeLockScreen(
      onCode: _onCode,
      onForgot: _forgot,
      waitUntil: AppPasscode.waitUntil,
      biometric: biometric && kind != null
          ? PasscodeBiometric(kind: kind, onPressed: _promptBiometric)
          : null,
      scanning: _isAuthenticating,
      noScreenLock: _noScreenLock,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AppLockScope(
      state: this,
      locked: _locked,
      enabled: enabled,
      hasCode: _hasCode,
      biometric: biometric,
      biometricKind: _biometricKind,
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
              child: KeyedSubtree(
                key: ValueKey(_lockCount),
                child: _lockScreen(),
              ),
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
    required this.hasCode,
    required this.biometric,
    required this.biometricKind,
    required super.child,
  });

  final AppLockState state;
  final bool locked;
  final bool enabled;
  final bool hasCode;
  final bool biometric;
  final BiometricKind? biometricKind;

  @override
  bool updateShouldNotify(_AppLockScope oldWidget) =>
      locked != oldWidget.locked ||
      enabled != oldWidget.enabled ||
      hasCode != oldWidget.hasCode ||
      biometric != oldWidget.biometric ||
      biometricKind != oldWidget.biometricKind;
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
