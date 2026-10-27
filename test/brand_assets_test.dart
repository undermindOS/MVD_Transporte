// Platform brand files that are easy to break by re-running an old icon
// generator or copying a sample: the themed (monochrome) launcher icon,
// the night board colors and the white status-bar silhouette for
// notifications.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/home_widget_feed.dart';

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
    // Behind the Flutter view: the board on every Android version, day
    // and night. The -v31 files win on Android 12+, and
    // flutter_native_splash:create rewrites them with the system color
    for (final styles in [
      'values',
      'values-night',
      'values-v31',
      'values-night-v31',
    ]) {
      final normal = RegExp(r'<style name="NormalTheme".*?</style>',
              dotAll: true)
          .firstMatch(_read('$res/$styles/styles.xml'))!
          .group(0)!;
      expect(normal,
          contains('<item name="android:windowBackground">@color/noche</item>'),
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
    // The accent is the navy of the board: on a light shade amber would
    // turn brown, the navy stays itself
    expect(service, contains('color: TimbreColors.tinta'));
    expect(service, isNot(contains('TimbreColors.ambar')));
  });

  test('the home widget is a small night board', () {
    final layout = _read('$res/layout/mvd_transporte_widget.xml');
    expect(layout, contains('@drawable/widget_background'));
    // Mi STM and Recarga are 44 dp touch targets
    final heights = RegExp(r'android:minHeight="(\d+)dp"')
        .allMatches(layout)
        .map((m) => int.parse(m.group(1)!));
    expect(heights, hasLength(2));
    expect(heights, everyElement(greaterThanOrEqualTo(44)));
    expect(layout, contains('@drawable/widget_plate'));
    expect(layout, isNot(contains('#FFFFFFFF')));
    expect(_read('$res/drawable/widget_background.xml'),
        contains('@color/tinta'));
    // The widget picker shows the real layout (Android 12+)
    expect(_read('$res/xml/mvd_transporte_widget_info.xml'),
        contains('android:previewLayout="@layout/mvd_transporte_widget"'));
    // Every view the provider fills exists in the layout
    final provider = _read('android/app/src/main/kotlin/com/liberontech/'
        'stmapp/MVDTransporteWidgetProvider.kt');
    for (final id in RegExp(r'R\.id\.(\w+)')
        .allMatches(provider)
        .map((m) => m.group(1)!)
        .toSet()) {
      expect(layout, contains('@+id/$id'), reason: id);
    }
    // It reads the keys the app writes, and hides the row 2 min after
    // its bus was due
    for (final key in [
      WidgetFeed.keyLine,
      WidgetFeed.keyDestination,
      WidgetFeed.keyEtaMinutes,
      WidgetFeed.keyClockTime,
      WidgetFeed.keyExpectedAtMs,
    ]) {
      expect(provider, contains('"$key"'), reason: key);
    }
    expect(provider, contains('EXPIRED_AFTER_MS = 2 * 60 * 1000L'));
  });

  test('iOS has light, dark and tinted 1024 px icons', () {
    // Light status bar text over the dark launch screen
    final plist = _read('ios/Runner/Info.plist');
    expect(plist, contains('<string>UIStatusBarStyleLightContent</string>'));
    // The launch screen view under the image is the board, not white
    expect(_read('ios/Runner/Base.lproj/LaunchScreen.storyboard'),
        isNot(contains('red="1" green="1" blue="1"')));
    // The brand name, and what the location is for
    expect(plist,
        contains('<key>CFBundleName</key>\n\t\t<string>Timbre MVD</string>'));
    const location = '<string>Timbre MVD usa tu ubicación para mostrarte '
        'las paradas cercanas.</string>';
    for (final key in [
      'NSLocationWhenInUseUsageDescription',
      // geolocator references it: App Store review wants it present
      'NSLocationAlwaysAndWhenInUseUsageDescription',
    ]) {
      expect(plist, contains('<key>$key</key>\n\t\t$location'),
          reason: key);
    }
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
