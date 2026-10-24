// Platform brand files that are easy to break by re-running an old icon
// generator or copying a sample: the themed (monochrome) launcher icon,
// the brand blue and the white status-bar silhouette for notifications.

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

  test('launcher and splash use the flag blue #0038A8', () {
    expect(_read('$res/values/colors.xml'), contains('#0038A8'));
    expect(_read('$res/values-v31/styles.xml'), contains('#0038A8'));
    expect(_read('$res/values/colors.xml'), isNot(contains('#0066CC')));
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
