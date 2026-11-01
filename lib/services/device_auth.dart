import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart'
    show AndroidAuthMessages;
import 'package:local_auth_darwin/local_auth_darwin.dart' show IOSAuthMessages;

/// What opens the app in place of its code. Android does not say whether
/// it is a fingerprint or a face, so there it is always «huella».
enum BiometricKind {
  fingerprint('huella', 'tu huella'),
  faceId('Face ID', 'Face ID'),
  touchId('Touch ID', 'Touch ID');

  const BiometricKind(this.label, this.phrase);

  /// After «con» in a label: «Desbloquear con huella».
  final String label;

  /// After «con» in a sentence: «Abrí Timbre MVD con tu huella».
  final String phrase;
}

/// The system authentication prompt: fingerprint, face, PIN or pattern.
/// Tests pass a fake to `MiTransporteMVDApp`.
abstract class DeviceAuth {
  /// The device has a lock method the prompt can use: a screen lock, or
  /// biometrics it accepts without one.
  Future<bool> isAvailable();

  /// The biometrics enrolled and usable right now, for the quick unlock;
  /// null when there are none or the check failed.
  Future<BiometricKind?> biometrics();

  /// Shows the prompt with [reason]; true when the person got through.
  ///
  /// With [biometricOnly] only a fingerprint or a face gets through, and
  /// the prompt's other button reads «Usar código». Without it the phone's
  /// screen lock (PIN, pattern or password) works too.
  ///
  /// A [sticky] prompt comes back when the app returns from the background
  /// and its answer waits for it; otherwise leaving the app closes it with
  /// a no. Prompts opened from the open app are not sticky (AppLock).
  ///
  /// Throws a `PlatformException` with a `local_auth` error code when the
  /// prompt could not run or was closed: `NotAvailable`, `LockedOut`,
  /// `PermanentlyLockedOut`, and on iOS also `UserCancelled`, `UserFallback`
  /// or `BiometricNotAvailable`. On iOS `NotAvailable` also comes after a
  /// failed try.
  Future<bool> authenticate(String reason,
      {bool biometricOnly = false, bool sticky = true});
}

class LocalDeviceAuth implements DeviceAuth {
  const LocalDeviceAuth();

  static final _localAuth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      // Android: a secure screen lock or enrolled biometrics; iOS: a
      // passcode. Fingerprint hardware with nothing enrolled is not enough.
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      debugPrint('❌ Authentication check failed: $e');
      return false;
    }
  }

  @override
  Future<BiometricKind?> biometrics() async {
    try {
      // Android lists only weak and strong biometrics; iOS lists Face ID or
      // Touch ID, and only when they are enrolled and allowed
      final types = await _localAuth.getAvailableBiometrics();
      if (types.isEmpty) return null;
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        return BiometricKind.fingerprint;
      }
      return types.contains(BiometricType.face)
          ? BiometricKind.faceId
          : BiometricKind.touchId;
    } catch (e) {
      debugPrint('❌ Biometrics check failed: $e');
      return null;
    }
  }

  @override
  Future<bool> authenticate(String reason,
          {bool biometricOnly = false, bool sticky = true}) =>
      _localAuth.authenticate(
        localizedReason: reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: 'Timbre MVD',
            biometricHint: 'Confirmá que sos vos',
            // Only with biometricOnly: the button under the fingerprint
            // goes back to the app's keypad
            cancelButton: biometricOnly ? 'Usar código' : 'Cancelar',
          ),
          IOSAuthMessages(
            // After a failed Face ID try: back to the app's keypad
            localizedFallbackTitle: biometricOnly ? 'Usar código' : null,
            // The plugin's own alert after too many tries
            lockOut: 'Face ID y Touch ID se bloquearon por muchos intentos. '
                'Bloqueá y desbloqueá el teléfono para volver a usarlos.',
            cancelButton: 'Aceptar',
          ),
        ],
        options: AuthenticationOptions(
          // The prompt comes back if the app goes to the background
          stickyAuth: sticky,
          biometricOnly: biometricOnly,
          // Error codes instead of the plugin's own dialogs, in English
          useErrorDialogs: false,
          // No extra «Confirmar» tap after a face is recognized
          sensitiveTransaction: false,
        ),
      );
}
