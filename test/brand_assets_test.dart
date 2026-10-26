// Platform brand files that are easy to break by re-running an old icon
// generator or copying a sample: the themed (monochrome) launcher icon,
// the night board colors and the white status-bar silhouette for
// notifications.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const res = 'android/app/src/main/res';

  test('adaptive icon has a monochrome layer for Android 13 themed icons',
      () {
    final xml = _read('$res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(xml, contains('<monochrome>'));
    expect(xml, contains('@drawable/ic_launcher_monochrome'));
    expect(File('$res/drawable-xxxhdpi/ic_launcher_monochrome.png').existsSync(),
        isTrue);
  });

  test('launcher icon and splash are the night board, no blue left', () {
    // Adaptive icon: the ink board with unlit LEDs is an image layer
    final xml = _read('$res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(xml, contains('@drawable/ic_launcher_background'));
    expect(
        File('$res/drawable-xxxhdpi/ic_launcher_background.png').existsSync(),
        isTrue);
    // Splash and window background: the app background, day and night
    for (final styles in ['values-v31', 'values-night-v31']) {
      expect(_read('$res/$styles/styles.xml'), contains('#070F22'),
          reason: styles);
    }
    for (final styles in ['values', 'values-night']) {
      expect(_read('$res/$styles/styles.xml'), contains('@color/noche'),
          reason: styles);
    }
    expect(_read('$res/values/colors.xml'), contains('#070F22'));
    for (final file in [
      '$res/values/colors.xml',
      '$res/values-v31/styles.xml',
      '$res/values-night-v31/styles.xml',
      'flutter_native_splash.yaml',
    ]) {
      final text = _read(file).toUpperCase();
      expect(text, isNot(contains('#0038A8')), reason: file);
      expect(text, isNot(contains('#00266F')), reason: file);
    }
  });

  test('notifications use the white bus silhouette, not the launcher icon',
      () {
    expect(File('$res/drawable/ic_stat_timbre.xml').existsSync(), isTrue);
    final service = _read('lib/services/notification_service.dart');
    expect(service, contains('@drawable/ic_stat_timbre'));
    expect(service, isNot(contains('@mipmap/ic_launcher')));

    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('com.liberontech.stmapp.NOTIFICATION_ICON'));
    expect(manifest, contains('@drawable/ic_stat_timbre'));
    expect(_read('lib/services/bus_wait_service.dart'),
        contains('com.liberontech.stmapp.NOTIFICATION_ICON'));
  });

  test('iOS has light, dark and tinted 1024 px icons', () {
    const set = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final name in [
      'Icon-App-1024x1024@1x.png',
      'Icon-App-Dark-1024x1024@1x.png',
      'Icon-App-Tinted-1024x1024@1x.png',
    ]) {
      expect(File('$set/$name').existsSync(), isTrue, reason: name);
    }
  });
}
