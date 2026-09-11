import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'cache_service.dart';

class BalanceScraper {
  static const String _widgetName = 'MVDTransporteWidgetProvider';

  // Multiple selectors to try in order (STM site may vary)
  static const List<String> _balanceSelectors = [
    '[class*="saldo"]',
    '[class*="balance"]',
    '[id*="saldo"]',
    '[id*="balance"]',
    '.saldo-disponible',
    '.saldo',
    '[data-saldo]',
  ];

  static const String _mainPageFragment = 'principal.xhtml';

  /// Call this from onPageFinished in the WebView.
  /// Only runs on the STM main account page.
  static Future<void> tryExtract(
      WebViewController controller, String url) async {
    if (!url.contains(_mainPageFragment)) return;

    final js = _buildSelectorJs(_balanceSelectors);
    try {
      final result = await controller.runJavaScriptReturningResult(js);
      final raw = result.toString().replaceAll('"', '').trim();

      if (raw.isEmpty || raw == 'null') {
        debugPrint('⚠️ Balance not found on page');
        return;
      }

      final balance = _normalizeBalance(raw);
      debugPrint('💳 Balance extraído: $balance');

      await CacheService.saveCardBalance(balance);
      await HomeWidget.saveWidgetData<String>('card_balance', balance);
      await HomeWidget.saveWidgetData<String>(
        'balance_updated',
        _formatTimestamp(DateTime.now()),
      );
      await HomeWidget.updateWidget(name: _widgetName);
    } catch (e) {
      debugPrint('⚠️ Balance scrape error: $e');
    }
  }

  static String _buildSelectorJs(List<String> selectors) {
    final parts = selectors.map((s) {
      return "document.querySelector('$s')?.innerText?.trim()";
    }).join(' || ');
    return '($parts) ?? ""';
  }

  static String _normalizeBalance(String raw) {
    // Strip surrounding quotes added by JS serialization
    var balance = raw.replaceAll(RegExp(r'^"|"$'), '').trim();
    // If it's just a number, prefix with $ sign
    if (RegExp(r'^\d+[.,]?\d*$').hasMatch(balance)) {
      balance = '\$$balance';
    }
    return balance;
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  }
}
