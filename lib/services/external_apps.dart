import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The one way out to another app: the system browser ([SystemBrowser]),
/// the mail app, a news link. The biometric lock listens to [launches]:
/// coming back from an app opened here is not coming back from the
/// background, so it does not lock again (see `AppLock`).
abstract final class ExternalApps {
  static final _launches = _Launches();

  /// Notified right before every launch.
  static Listenable get launches => _launches;

  static Future<bool> launch(Uri uri, {required LaunchMode mode}) {
    _launches.notify();
    return launchUrl(uri, mode: mode);
  }
}

class _Launches extends ChangeNotifier {
  void notify() => notifyListeners();
}
