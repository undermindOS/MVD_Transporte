import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The one way out to another app: the system browser ([SystemBrowser]),
/// the mail app, a news link, the system settings. The biometric lock
/// listens to [launches]: coming back from an app opened here is not coming
/// back from the background, so it does not lock again (see `AppLock`).
abstract final class ExternalApps {
  static final _launches = _Launches();

  /// Notified right before every launch.
  static Listenable get launches => _launches;

  static Future<bool> launch(Uri uri, {required LaunchMode mode}) =>
      open(() => launchUrl(uri, mode: mode));

  /// Another app shown by a plugin call instead of a URL: the app's page
  /// in the system settings.
  static Future<bool> open(Future<bool> Function() opener) {
    _launches.notify();
    return opener();
  }
}

class _Launches extends ChangeNotifier {
  void notify() => notifyListeners();
}
