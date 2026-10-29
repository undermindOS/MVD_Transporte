import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/cache_service.dart';
import 'welcome_page.dart';

/// The welcome of the first launch until «Empezar», then [child], the app.
///
/// It is `home` of the MaterialApp, under the lock: a code or the older
/// lock opens first. Until the welcome is over [child] is not built, so
/// nothing of the app loads or asks for anything. Closing the app before
/// the end starts the welcome over next time.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, required this.child});

  /// The app (HomePage).
  final Widget child;

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  late bool _done =
      CacheService.get<bool>(CacheService.keyWelcomeDone) ?? false;

  void _finish() {
    // Not awaited: Hive has it in memory at once and writes it right after
    // (see CacheService.set)
    unawaited(CacheService.set(CacheService.keyWelcomeDone, true));
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) =>
      _done ? widget.child : WelcomePage(onDone: _finish);
}
