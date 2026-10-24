import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'services/background_worker.dart';
import 'services/bus_wait_service.dart';
import 'services/cache_service.dart';
import 'services/notification_service.dart';
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

/// Fira and Doto ship inside the app (SIL OFL 1.1): their licenses show up
/// in the system license page next to the packages.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in const [
      ('Fira Sans', 'OFL-FiraSans.txt'),
      ('Fira Sans Extra Condensed', 'OFL-FiraSansExtraCondensed.txt'),
      ('Doto', 'OFL-Doto.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/fonts/$file');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}

class MiTransporteMVDApp extends StatelessWidget {
  const MiTransporteMVDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timbre MVD',
      debugShowCheckedModeBanner: false,
      theme: buildTimbreTheme(),
      home: const HomePage(),
    );
  }
}
