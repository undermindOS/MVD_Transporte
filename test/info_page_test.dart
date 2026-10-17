import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/ui/info_page.dart';

void main() {
  Future<void> pumpInfo(
      WidgetTester tester, Future<bool> Function(bool) onToggle) {
    return tester.pumpWidget(MaterialApp(
      home: InfoPage(
        biometricLockEnabled: false,
        onToggleBiometricLock: onToggle,
      ),
    ));
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('switch reflects a confirmed toggle', (tester) async {
    await pumpInfo(tester, (value) async => value);

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isTrue);
  });

  testWidgets('switch stays off when confirmation is cancelled',
      (tester) async {
    await pumpInfo(tester, (value) async => false);

    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
  });

  testWidgets('shows data source attribution', (tester) async {
    await pumpInfo(tester, (value) async => value);
    expect(find.textContaining('Fuente de datos'), findsOneWidget);
    expect(find.textContaining('Intendencia de Montevideo'), findsWidgets);
    // Covers every IM service the native screens read
    expect(find.textContaining('novedades del transporte'), findsOneWidget);
    expect(find.textContaining('estado del GPS'), findsOneWidget);
  });
}
