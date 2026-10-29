import 'package:flutter/material.dart';

import '../services/app_passcode.dart';
import 'app_lock.dart';
import 'passcode_entry.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/led_board.dart';
import 'widgets/timbre_app_bar.dart';

/// «CÓDIGO NUEVO», opened from Info's «Código de acceso»: a new code typed
/// twice on the LED keypad becomes the app's code (`AppLockState.setCode`).
/// Pops with true once it is saved; Back leaves it as it was.
class NewCodePage extends StatelessWidget {
  const NewCodePage({super.key});

  @override
  Widget build(BuildContext context) =>
      _CodePage(child: _NewCode(onSaved: () => Navigator.of(context).pop(true)));
}

/// «TU CÓDIGO», opened from Info before the code changes or the lock goes
/// off: the code in use, or the phone's own lock after «¿Olvidaste el
/// código?». Wrong codes and the wait count as on the lock screen (the same
/// `AppPasscode.check`). Pops with true once confirmed; to change the code,
/// «CÓDIGO NUEVO» comes first on the same page.
class CodeCheckPage extends StatefulWidget {
  /// «Cambiar código»: the code in use, then a new one.
  const CodeCheckPage.change({super.key}) : _change = true;

  /// «Código de acceso» off: the code in use; Info turns the lock off.
  const CodeCheckPage.turnOff({super.key}) : _change = false;

  final bool _change;

  @override
  State<CodeCheckPage> createState() => _CodeCheckPageState();
}

class _CodeCheckPageState extends State<CodeCheckPage> {
  static const _noScreenLockNote = 'Tu teléfono no tiene bloqueo de '
      'pantalla, así que no puede confirmar que sos vos. Sin el código no se '
      'puede cambiar ni desactivar.';

  // The code in use was right, or the phone's lock confirmed: the new code
  var _confirmed = false;

  // The phone's prompt is open
  var _asking = false;

  // «¿Olvidaste el código?» on a phone without a screen lock
  var _noScreenLock = false;

  String get _reason => widget._change
      ? 'Usá el bloqueo de tu teléfono para cambiar el código'
      : 'Usá el bloqueo de tu teléfono para desactivar el código';

  void _onConfirmed() {
    if (widget._change) {
      setState(() => _confirmed = true);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<PasscodeFeedback?> _check(String code) async {
    switch (await AppLock.of(context).checkCode(code)) {
      case CodeCheck.ok:
        if (mounted) _onConfirmed();
        return null;
      case CodeCheck.wrong:
        return const PasscodeError('Código incorrecto');
      case CodeCheck.wait:
        return PasscodeWait(AppPasscode.waitUntil ??
            AppPasscode.clock().add(AppPasscode.wait));
    }
  }

  /// The phone's own lock in place of the code. A phone without a screen
  /// lock cannot tell who holds it: then nothing changes.
  Future<void> _forgot() async {
    final lock = AppLock.of(context);
    setState(() {
      _asking = true;
      _noScreenLock = false;
    });
    final confirmed = await lock.confirmWithPhoneLock(_reason);
    if (!mounted) return;
    setState(() {
      _asking = false;
      _noScreenLock = confirmed == null;
    });
    if (confirmed == true) _onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return _CodePage(
          child: _NewCode(onSaved: () => Navigator.of(context).pop(true)));
    }
    return _CodePage(
      child: PasscodeEntry(
        sign: 'TU CÓDIGO',
        signLabel: 'Tu código',
        message: 'Ingresá tu código actual.',
        onSubmit: _check,
        waitUntil: AppPasscode.waitUntil,
        enabled: !_asking,
        actions: [
          TextButton(
            onPressed: _asking ? null : _forgot,
            child: const Text('¿Olvidaste el código?',
                textAlign: TextAlign.center),
          ),
          if (_noScreenLock)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  _noScreenLockNote,
                  textAlign: TextAlign.center,
                  style: TimbreText.body.copyWith(
                      height: 1.4, color: TimbreColors.etiquetaCartel),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «CÓDIGO NUEVO» and «REPETILO»: saved as the app's code, then [onSaved].
/// It locks on the next trip to the background, not now.
class _NewCode extends StatelessWidget {
  const _NewCode({required this.onSaved});

  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return PasscodeCreate(
      sign: 'CÓDIGO NUEVO',
      signLabel: 'Código nuevo',
      message: 'Elegí 4 cifras para abrir la app.',
      onCreated: (code) async {
        await AppLock.of(context).setCode(code);
        if (context.mounted) onSaved();
      },
    );
  }
}

/// A page of the code: the identity bar with the back arrow, as Privacidad,
/// and the LED board under it, where the keypad lives.
class _CodePage extends StatelessWidget {
  const _CodePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildTimbreAppBar(context, title: 'Código'),
      // The plate is already in the bar
      body: LedBoard(plate: false, child: child),
    );
  }
}
