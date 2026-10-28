import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'services/background_worker.dart';
import 'services/bus_wait_service.dart';
import 'services/cache_service.dart';
import 'services/device_auth.dart';
import 'services/notification_service.dart';
import 'ui/app_lock.dart';
import 'ui/home_page.dart';
import 'ui/theme/timbre_theme.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);


  await CacheService.init();
  await NotificationService.init();
  await BackgroundWorker.init();
  // "Estoy esperando": messages from the Android service isolate
  FlutterForegroundTask.initCommunicationPort();
  await BusWaitService.init();

  _registerFontLicenses();

  FlutterNativeSplash.remove();
  runApp(const MiTransporteMVDApp());
}

/// Fira and Doto (SIL OFL 1.1) and part of the pixel icons (pixelarticons,
/// MIT) ship inside the app: their licenses show up in the system license
/// page next to the packages.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Fira Sans', 'fonts/OFL-FiraSans.txt'),
      ('Fira Sans Extra Condensed', 'fonts/OFL-FiraSansExtraCondensed.txt'),
      ('Doto', 'fonts/OFL-Doto.txt'),
      ('pixelarticons', 'licenses/MIT-pixelarticons.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/$file');
      yield LicenseEntryWithLineBreaks([name], text);
    }
  });
}

class MiTransporteMVDApp extends StatelessWidget {
  const MiTransporteMVDApp({
    super.key,
    this.deviceAuth = const LocalDeviceAuth(),
  });

  /// The system authentication prompt of the biometric lock.
  final DeviceAuth deviceAuth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timbre MVD',
      debugShowCheckedModeBanner: false,
      theme: buildTimbreTheme(),
      navigatorObservers: [
        // Tells Mis paradas when a page covers it, so it stops polling
        HomePage.routeObserver,
        // Back closes nothing while the app is locked
        AppLock.routeGuard,
      ],
      // The lock covers the Navigator: every page, sheet and dialog
      builder: (context, child) =>
          AppLock(deviceAuth: deviceAuth, child: child!),
      home: const HomePage(),
    );
  }
}
