import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'services/background_worker.dart';
import 'services/cache_service.dart';
import 'services/notification_service.dart';
import 'ui/home_page.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);


  await CacheService.init();
  await NotificationService.init();
  await BackgroundWorker.init();

  FlutterNativeSplash.remove();
  runApp(const MiTransporteMVDApp());
}

class MiTransporteMVDApp extends StatelessWidget {
  const MiTransporteMVDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVD Transporte',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0066CC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066CC),
          primary: const Color(0xFF0066CC),
          secondary: const Color(0xFF0099FF),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          indicatorColor: Color(0x330066CC),
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
