// Platform brand files that are easy to break by re-running an old icon
// generator or copying a sample: the themed (monochrome) launcher icon,
// the night board colors and the white status-bar silhouette for
// notifications.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/home_widget_feed.dart';
import 'package:stm_app/services/stop_widgets_feed.dart';

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

  test('the stop widgets are night boards in three sizes', () {
    const kotlin = 'android/app/src/main/kotlin/com/liberontech/stmapp';
    final provider = _read('$kotlin/TimbreStopWidget.kt');
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    final layouts = {
      for (final size in ['small', 'medium', 'large'])
        size: _read('$res/layout/widget_stop_$size.xml'),
    };
    final row = _read('$res/layout/widget_stop_row.xml');

    for (final (size, kind) in [
      ('small', 'TimbreProximoWidget'),
      ('medium', 'TimbreParadaWidget'),
      ('large', 'TimbreMisParadasWidget'),
    ]) {
      // The app redraws each provider by its class name
      expect(StopWidgetsFeed.providers, contains(kind));
      expect(provider, contains('class $kind : TimbreStopWidget()'));
      expect(manifest, contains('android:name=".$kind"'));
      expect(manifest, contains('@xml/widget_stop_${size}_info'));
      final info = _read('$res/xml/widget_stop_${size}_info.xml');
      expect(info,
          contains('android:initialLayout="@layout/widget_stop_$size"'));
      // The picker shows sample data (Android 12+)
      expect(info, contains('android:previewLayout='
          '"@layout/widget_stop_${size}_preview"'));
      expect(_read('$res/layout/widget_stop_${size}_preview.xml'),
          contains('SAN JOSE y ANDES'));

      final layout = layouts[size]!;
      expect(layout, contains('android:id="@android:id/background"'));
      expect(layout, contains('@drawable/widget_background'));
      expect(layout, contains('@drawable/widget_led_band'));
      // Refresh is a 44 dp target; so are Mi STM and Recarga
      expect(
          layout,
          matches(RegExp(r'w_refresh"\s+android:layout_width="44dp"\s+'
              r'android:layout_height="44dp"')));
      for (final m
          in RegExp(r'android:minHeight="(\d+)dp"').allMatches(layout)) {
        expect(int.parse(m.group(1)!), greaterThanOrEqualTo(44));
      }
      // Only views RemoteViews can draw: no View, no Space
      expect(layout, isNot(contains('<View')));
      expect(layout, isNot(contains('<Space')));
    }
    expect(row, isNot(contains('<View')));

    // Every view the provider fills exists in a layout (android.R.id is
    // the system's)
    final all = layouts.values.join() + row;
    for (final id in RegExp(r'(?<!android\.)R\.id\.(\w+)')
        .allMatches(provider)
        .map((m) => m.group(1)!)
        .toSet()) {
      expect(all, contains('@+id/$id'), reason: id);
    }
    // It reads the keys the app writes, and writes the ones it reads
    for (final key in [
      StopWidgetsFeed.keySavedStops,
      StopWidgetsFeed.keyShownStops,
      StopWidgetsFeed.keyPlacedWidgets,
    ]) {
      expect(provider, contains('"$key"'), reason: key);
    }
    expect(provider, contains('"stop_board_"'));
    expect(StopWidgetsFeed.keyBoard(574), 'stop_board_574');
    // Its refresh button reaches the app's Dart code
    expect(manifest,
        contains('es.antonborri.home_widget.HomeWidgetBackgroundReceiver'));
    expect(manifest,
        contains('es.antonborri.home_widget.HomeWidgetBackgroundService'));

    // Times are estimates, never amber; line numbers get a dim outline
    final time = RegExp(r'w_row_time"[^>]*').firstMatch(row)!.group(0)!;
    expect(time, contains('@color/papel'));
    expect(_read('$res/drawable/widget_badge_lit_bg.xml'),
        contains('@color/ambar_tenue'));
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
