import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Layout test support: real fonts and a real phone screen.

/// Loads the fonts bundled with the app, so layout tests measure real
/// glyphs: the default test font draws every glyph as a 1 em square, two
/// to three times wider than Fira Sans Extra Condensed.
Future<void> loadBundledFonts() async {
  const families = {
    'FiraSans': ['Regular', 'Medium', 'SemiBold', 'Bold'],
    'FiraSansExtraCondensed': ['SemiBold', 'Bold', 'ExtraBold'],
    'Doto': ['Black'],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final style in family.value) {
      final bytes =
          File('assets/fonts/${family.key}-$style.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// A 390 × 844 phone (iPhone 12-15, most mid-range Androids) instead of
/// the 800 × 600 test window.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
