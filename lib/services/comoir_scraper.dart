import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/route_alert.dart';
import 'cache_service.dart';

/// Scraped route data extracted from Cómo Ir WebView.
class DetectedRoute {
  final int originStopId;
  final String originName;
  final String destinationName;
  final List<String> lines;

  const DetectedRoute({
    required this.originStopId,
    required this.originName,
    required this.destinationName,
    required this.lines,
  });

  bool get isValid =>
      originStopId > 0 && originName.isNotEmpty && destinationName.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'originStopId': originStopId,
        'originName': originName,
        'destinationName': destinationName,
        'lines': lines,
      };

  factory DetectedRoute.fromJson(Map<String, dynamic> j) => DetectedRoute(
        originStopId: (j['originStopId'] as num?)?.toInt() ?? 0,
        originName: j['originName'] as String? ?? '',
        destinationName: j['destinationName'] as String? ?? '',
        lines: (j['lines'] as List?)?.cast<String>() ?? [],
      );
}

/// Injects JavaScript into the Cómo Ir page to extract
/// active route data (origin stop, destination, lines).
class ComoIrScraper {
  static const String _comoIrFragment = 'comoir';

  /// JavaScript that tries multiple strategies to extract route info.
  /// Returns a JSON string or empty string if nothing found.
  static const String _extractJs = r'''
(function() {
  try {
    // Strategy 1: Look for itinerary leg elements
    var legs = document.querySelectorAll(
      '[class*="leg"], [class*="itinerary"], [class*="Leg"], [class*="Itinerary"]'
    );

    // Strategy 2: Look for line badges / route chips
    var lineBadges = Array.from(document.querySelectorAll(
      '[class*="line"], [class*="route"], [class*="bus"], [class*="linea"]'
    )).map(function(el) {
      return el.innerText.trim();
    }).filter(function(t) {
      return t.length > 0 && t.length <= 6 && /^\d/.test(t);
    });

    // Strategy 3: Look for stop names
    var stopEls = document.querySelectorAll(
      '[class*="stop"], [class*="parada"], [class*="origin"], [class*="from"]'
    );
    var originText = stopEls.length > 0 ? stopEls[0].innerText.trim() : '';

    var destEls = document.querySelectorAll(
      '[class*="destination"], [class*="destino"], [class*="to"], [class*="llegada"]'
    );
    var destText = destEls.length > 0 ? destEls[0].innerText.trim() : '';

    // Strategy 4: Look for a data-stop-id attribute on the first leg
    var stopId = 0;
    var stopIdEl = document.querySelector('[data-stop-id], [data-parada], [data-id]');
    if (stopIdEl) {
      var raw = stopIdEl.getAttribute('data-stop-id') ||
                stopIdEl.getAttribute('data-parada') ||
                stopIdEl.getAttribute('data-id');
      stopId = parseInt(raw) || 0;
    }

    // Strategy 5: URL hash or query params may contain stop IDs
    var hash = window.location.hash || '';
    var search = window.location.search || '';
    var hashMatch = hash.match(/parada[=\/](\d+)/i) ||
                    search.match(/parada[=\/](\d+)/i) ||
                    hash.match(/stop[=\/](\d+)/i);
    if (hashMatch && stopId === 0) {
      stopId = parseInt(hashMatch[1]) || 0;
    }

    // Strategy 6: React/Angular state in window
    var appState = null;
    var stateKeys = ['__INITIAL_STATE__', '__STATE__', '__APP_STATE__', 'appState'];
    for (var i = 0; i < stateKeys.length; i++) {
      if (window[stateKeys[i]]) { appState = window[stateKeys[i]]; break; }
    }

    if (appState) {
      try {
        var stateStr = typeof appState === 'string' ? appState : JSON.stringify(appState);
        var stopMatch = stateStr.match(/"originStop(?:Id)?"\s*:\s*(\d+)/);
        if (stopMatch) stopId = parseInt(stopMatch[1]);
        var lineMatch = stateStr.match(/"(?:line|linea|route)"\s*:\s*"([^"]{1,6})"/g);
        if (lineMatch) {
          lineMatch.forEach(function(m) {
            var v = m.match(/"([^"]{1,6})"$/);
            if (v && /^\d/.test(v[1])) lineBadges.push(v[1]);
          });
        }
      } catch(e) {}
    }

    // Deduplicate lines
    var uniqueLines = lineBadges.filter(function(v, i, a) {
      return a.indexOf(v) === i;
    }).slice(0, 8);

    return JSON.stringify({
      originStopId: stopId,
      originName: originText.substring(0, 80),
      destinationName: destText.substring(0, 80),
      lines: uniqueLines
    });
  } catch(e) {
    return '';
  }
})()
''';

  /// Call from onPageFinished when URL contains 'comoir'.
  /// Returns a [DetectedRoute] if a valid route was found, null otherwise.
  static Future<DetectedRoute?> tryExtract(
      WebViewController controller, String url) async {
    if (!url.contains(_comoIrFragment)) return null;

    try {
      final result =
          await controller.runJavaScriptReturningResult(_extractJs);
      final raw = result.toString().replaceAll(r'\"', '"');

      // Strip outer quotes added by WebView JS serialization
      final jsonStr = raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1)
          : raw;

      if (jsonStr.isEmpty || jsonStr == 'null' || jsonStr == '""') return null;

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final route = DetectedRoute.fromJson(map);

      if (!route.isValid) return null;

      debugPrint('🗺️ Ruta detectada: ${route.originName} → ${route.destinationName}'
          ' (parada ${route.originStopId}, líneas: ${route.lines})');

      // Cache for widget use
      await CacheService.set(
        CacheService.keyLastDetectedRoute,
        jsonEncode(route.toJson()),
      );

      return route;
    } catch (e) {
      debugPrint('⚠️ ComoIr scrape error: $e');
      return null;
    }
  }

  /// Load the last detected route from cache (for display in widget / UI).
  static DetectedRoute? loadCached() {
    final raw = CacheService.get<String>(CacheService.keyLastDetectedRoute);
    if (raw == null) return null;
    try {
      return DetectedRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Convert a detected route into a [RouteAlert] and save it.
  static Future<RouteAlert> saveAsAlert(DetectedRoute detected) async {
    final id = CacheService.nextRouteId();
    final alert = RouteAlert(
      id: id,
      originStopId: detected.originStopId,
      originName: detected.originName.isNotEmpty
          ? detected.originName
          : 'Parada ${detected.originStopId}',
      destinationName: detected.destinationName,
      preferredLines: detected.lines,
      enabled: true,
    );
    await CacheService.saveRoute(alert);
    return alert;
  }
}
