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

  static const String _stmHost = 'stm.gub.uy';
  static const String _mainPageFragment = 'principal.xhtml';

  /// Call this from onPageFinished in the WebView.
  /// Only runs on the official STM main account page.
  static Future<void> tryExtract(
      WebViewController controller, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host != _stmHost ||
        !uri.path.endsWith(_mainPageFragment)) {
      return;
    }

    final js = _buildSelectorJs(_balanceSelectors);
    try {
      final result = await controller.runJavaScriptReturningResult(js);
      final raw = result.toString().replaceAll('"', '').trim();

      if (raw.isEmpty || raw == 'null') {
        debugPrint('⚠️ Balance not found on page');
        return;
      }

      final balance = _normalizeBalance(raw);
      if (balance == null) {
        debugPrint('⚠️ Balance text not recognized');
        return;
      }
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

  @visibleForTesting
  static String? normalizeBalance(String raw) => _normalizeBalance(raw);

  static String? _normalizeBalance(String raw) {
    // Strip surrounding quotes added by JS serialization
    var balance = raw.replaceAll(RegExp(r'^"|"$'), '').trim();
    // A selector may hit a container ("Saldo disponible\n$ 123,50"):
    // keep only the amount
    final amount = RegExp(r'\$\s?\d[\d.,]*').firstMatch(balance);
    if (amount != null) return amount.group(0)!.replaceAll(' ', '');
    // If it's just a number, prefix with $ sign
    if (RegExp(r'^\d+[.,]?\d*$').hasMatch(balance)) {
      return '\$$balance';
    }
    // Long text without an amount is not a balance — don't put it on the widget
    return balance.length <= 20 ? balance : null;
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  }
}
