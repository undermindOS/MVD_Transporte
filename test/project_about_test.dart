import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

import 'package:stm_app/ui/project_about_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'support/layout.dart';

class _Browser extends UrlLauncherPlatform {
  final opened = <String>[];
  bool result = true;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return result;
  }
}

void main() {
  late _Browser browser;
  setUpAll(loadBundledFonts);
  setUp(() {
    browser = _Browser();
    UrlLauncherPlatform.instance = browser;
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('About reads offline and fits a phone at ${scale}x', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: buildTimbreTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ProjectAboutPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(browser.opened, isEmpty);
      expect(find.text('Timbre MVD'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('khrestenkov.com'), 250);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('khrestenkov.com'));
      await tester.pumpAndSettle();
      expect(browser.opened, ['https://khrestenkov.com/es/']);
    });
  }

  testWidgets('an unavailable browser gives a useful error', (tester) async {
    browser.result = false;
    await tester.pumpWidget(
      MaterialApp(theme: buildTimbreTheme(), home: const ProjectAboutPage()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Más sobre el proyecto'), 250);
    await tester.tap(find.text('Más sobre el proyecto'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudo abrir el navegador.'),
      findsOneWidget,
    );
  });
}
