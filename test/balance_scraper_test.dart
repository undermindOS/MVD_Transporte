import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/balance_scraper.dart';

void main() {
  test('keeps only the amount when a container element matched', () {
    expect(BalanceScraper.normalizeBalance(r'Saldo disponible\n$ 123,50'),
        r'$123,50');
  });

  test('prefixes bare numbers with \$', () {
    expect(BalanceScraper.normalizeBalance('250'), r'$250');
  });

  test('rejects long text without an amount', () {
    expect(
        BalanceScraper.normalizeBalance(
            'Consulte su saldo ingresando a su cuenta'),
        isNull);
  });
}
