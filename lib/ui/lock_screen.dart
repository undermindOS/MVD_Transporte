import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'passcode_entry.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/led_board.dart';
import 'widgets/led_lock.dart';
import 'widgets/pixel_icon.dart';

/// The older lock, from before the app had a code: the LED board, the lock
/// lit in amber, «BLOQUEADA» and «Desbloquear». Unlocking asks the system
/// prompt through [onUnlock]; while it is open the lock keeps scanning.
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
    return LedBoard(
      child: Column(children: [
        LedLock(scanning: _scanning),
        const SizedBox(height: 32),
        Semantics(
          header: true,
          label: 'Aplicación bloqueada',
          excludeSemantics: true,
          child: Text(
            'BLOQUEADA',
            textAlign: TextAlign.center,
            style: TimbreText.cartel(30).copyWith(letterSpacing: 2),
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
          icon: const PixelIcon(PixelGlyphs.unlock, size: 24),
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
    );
  }
}

/// The lock with the app's code: the LED board, a smaller [LedLock],
/// «BLOQUEADA», the code dots and the keypad, «¿Olvidaste el código?» and
/// the TIMBRE MVD plate. While a system prompt is open ([scanning]) the
/// lock scans and every key waits.
class CodeLockScreen extends StatelessWidget {
  const CodeLockScreen({
    super.key,
    required this.onCode,
    required this.onForgot,
    this.waitUntil,
    this.biometric,
    this.scanning = false,
    this.noScreenLock = false,
  });

  /// A code typed on the keypad, and what to show after it.
  final Future<PasscodeFeedback?> Function(String code) onCode;

  /// «¿Olvidaste el código?»: the phone's own lock.
  final Future<void> Function() onForgot;

  /// A wait already running when the screen comes up.
  final DateTime? waitUntil;

  /// The quick unlock key; null without it.
  final PasscodeBiometric? biometric;

  /// A system prompt is open: the lock scans and the keypad waits.
  final bool scanning;

  /// «¿Olvidaste el código?» on a phone without a screen lock: the note
  /// that says how to get in without the code.
  final bool noScreenLock;

  // Nothing can stand in for the code: only starting over opens the app
  static const _noScreenLockAndroid =
      'Tu teléfono no tiene bloqueo de pantalla, así que no puede confirmar '
      'que sos vos. Para entrar sin el código, borrá los datos de Timbre MVD '
      'en los ajustes del teléfono: se borran tus paradas y rutas.';
  static const _noScreenLockIos =
      'Tu teléfono no tiene bloqueo de pantalla, así que no puede confirmar '
      'que sos vos. Para entrar sin el código, borrá Timbre MVD y volvé a '
      'instalarla: se borran tus paradas y rutas.';

  @override
  Widget build(BuildContext context) {
    final note = defaultTargetPlatform == TargetPlatform.iOS
        ? _noScreenLockIos
        : _noScreenLockAndroid;
    return LedBoard(
      child: PasscodeEntry(
        sign: 'BLOQUEADA',
        signLabel: 'Aplicación bloqueada',
        message: 'Ingresá tu código',
        onSubmit: onCode,
        waitUntil: waitUntil,
        biometric: biometric,
        enabled: !scanning,
        leading: LedLock(pitch: 6, scanning: scanning),
        actions: [
          TextButton(
            onPressed: scanning ? null : onForgot,
            child: const Text('¿Olvidaste el código?'),
          ),
          if (noScreenLock)
            // Inline: the lock is above the Navigator, no dialogs here
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  note,
                  textAlign: TextAlign.center,
                  style: TimbreText.body.copyWith(
                    height: 1.4,
                    color: TimbreColors.etiquetaCartel,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// After «¿Olvidaste el código?» and the phone's lock: «CÓDIGO NUEVO» and
/// its repetition; «Ahora no» opens the app with the old code.
class NewCodeScreen extends StatelessWidget {
  const NewCodeScreen({
    super.key,
    required this.onCreated,
    required this.onSkip,
  });

  final Future<void> Function(String code) onCreated;

  /// «Ahora no»: in, with the old code.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return LedBoard(
      child: PasscodeCreate(
        sign: 'CÓDIGO NUEVO',
        signLabel: 'Código nuevo',
        message: 'Elegí 4 cifras nuevas para abrir la app.',
        onCreated: onCreated,
        actions: [
          TextButton(onPressed: onSkip, child: const Text('Ahora no')),
        ],
      ),
    );
  }
}
