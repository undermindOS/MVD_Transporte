import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/cartel.dart';
import 'widgets/led_lock.dart';
import 'widgets/led_matrix.dart';
import 'widgets/pixel_icon.dart';

/// The whole lock screen is the LED board: ink, dim amber dots, the lock
/// lit in amber. Unlocking asks the system prompt through [onUnlock];
/// while it is open the lock keeps scanning.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock});

  /// Completes when the prompt closes, whatever the answer.
  final Future<void> Function() onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _scanning = false;

  Future<void> _unlock() async {
    setState(() => _scanning = true);
    try {
      await widget.onUnlock();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: TimbreColors.tinta,
      ),
      child: Scaffold(
        backgroundColor: TimbreColors.tinta,
        body: Stack(children: [
          const Positioned.fill(
            child: LedMatrix(
              pitch: 8,
              dot: 2.4,
              color: TimbreColors.ambar,
              opacity: 0.09,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 24),
                        Column(children: [
                          LedLock(scanning: _scanning),
                          const SizedBox(height: 32),
                          Semantics(
                            header: true,
                            label: 'Aplicación bloqueada',
                            excludeSemantics: true,
                            child: Text(
                              'BLOQUEADA',
                              textAlign: TextAlign.center,
                              style: TimbreText.cartel(30)
                                  .copyWith(letterSpacing: 2),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tus paradas y rutas guardadas están protegidas',
                            textAlign: TextAlign.center,
                            style: TimbreText.body.copyWith(
                              height: 1.4,
                              color: TimbreColors.etiquetaCartel,
                            ),
                          ),
                          const SizedBox(height: 36),
                          FilledButton.icon(
                            onPressed: _scanning ? null : _unlock,
                            icon: const PixelIcon(PixelGlyphs.unlock,
                                size: 24),
                            label: const Text('Desbloquear'),
                            style: FilledButton.styleFrom(
                              backgroundColor: TimbreColors.ambar,
                              foregroundColor: TimbreColors.tinta,
                              disabledBackgroundColor: TimbreColors.ambarTenue,
                              disabledForegroundColor: TimbreColors.tinta,
                              minimumSize: const Size(220, 56),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontFamily: TimbreFonts.fira,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ]),
                        const Padding(
                          padding: EdgeInsets.only(top: 32, bottom: 20),
                          child: CartelCompacto(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
