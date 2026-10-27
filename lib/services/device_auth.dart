import 'package:local_auth/local_auth.dart';

/// The system authentication prompt: fingerprint, face, PIN or pattern.
/// Tests pass a fake to `MiTransporteMVDApp`.
abstract class DeviceAuth {
  /// The device has a lock method the prompt can use.
  Future<bool> isAvailable();

  /// Shows the prompt with [reason]; true when the person got through.
  /// Throws a `PlatformException` with a `local_auth` error code
  /// (`NotAvailable`, `LockedOut`…) when the prompt could not run.
  Future<bool> authenticate(String reason);
}

class LocalDeviceAuth implements DeviceAuth {
  const LocalDeviceAuth();

  static final _localAuth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async =>
      await _localAuth.canCheckBiometrics ||
      await _localAuth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) => _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // The prompt comes back if the app goes to the background
          stickyAuth: true,
          // A PIN or a pattern is enough
          biometricOnly: false,
        ),
      );
}
