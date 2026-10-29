import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'external_apps.dart';

/// Web services of the Intendencia de Montevideo the app links to.
///
/// They open in the system browser — Chrome Custom Tabs on Android,
/// SFSafariViewController on iOS — never in an embedded WebView: Google Play
/// forbids apps that are "a webview of a website without permission", and
/// the Mi STM login (SAML SSO → ID Uruguay) belongs in a browser the user
/// can trust, where the app cannot read or inject into the page (RFC 8252).
/// The Mis paradas widget (TimbreStopWidget.kt) repeats two of these.
enum OfficialSite {
  miStm('https://stm.gub.uy/app/mistm/cuenta/pages/principal.xhtml'),
  recarga('https://stm.gub.uy/app/mistm/cuenta/recargaRapida.xhtml'),
  comoIr('https://m.montevideo.gub.uy/comoir/'),
  avisos('https://stm.gub.uy/app/mistm/cuenta/pages/notificaciones.xhtml');

  const OfficialSite(this.url);

  final String url;

  Uri get uri => Uri.parse(url);

  /// Official deep link: the Cómo Ir SPA reads /comoir/parada?numero=N.
  static Uri comoIrStop(int stopId) =>
      Uri.parse('${comoIr.url}parada?numero=$stopId');
}

class SystemBrowser {
  /// Opens [uri] in Custom Tabs / SFSafariViewController. Returns false when
  /// no browser could show it.
  static Future<bool> open(Uri uri) async {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    try {
      // Without a Custom Tabs browser url_launcher falls back to its own
      // WebView activity — use the full browser instead.
      final mode = await supportsLaunchMode(LaunchMode.inAppBrowserView)
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication;
      final opened = await ExternalApps.launch(uri, mode: mode);
      // On iOS the result describes the page's first load, not the browser:
      // false = closed before the page loaded.
      return opened || isIOS;
    } on PlatformException catch (e) {
      debugPrint('⚠️ Browser launch error: ${e.code} ${e.message}');
      // iOS throws code 'Error' when the first load fails, but
      // SFSafariViewController stays open and shows Safari's own error page.
      return isIOS && e.code == 'Error';
    }
  }
}
