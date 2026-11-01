import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/device_auth.dart';
import '../app_lock.dart';
import '../passcode_entry.dart';
import '../privacy_policy_page.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import '../widgets/led_board.dart';
import '../widgets/led_lock.dart';
import '../widgets/pixel_icon.dart';
import '../widgets/timbre_bus.dart';
import '../widgets/widget_refresh_options.dart';

/// The welcome of the first launch, each step a [LedBoard] with its dot on
/// top: «Hola» (what the app does), «Sin cuentas ni registros», «Tu código»
/// (the app's own code, optional) and «Huella» after it (the quick
/// unlock), then «Listo», which says how the app opens. [onDone] after
/// «Empezar».
///
/// «Tu código» comes only without a code: a welcome started over after the
/// app was closed skips it. «Huella» comes only with a code, when the phone
/// has a fingerprint or a face enrolled and the quick unlock is still off.
///
/// Back goes a step back until a code is saved, then does nothing; on
/// «Hola» it leaves the app. The steps cross-fade in 200 ms, at once with
/// reduced motion.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onDone});

  /// «Empezar».
  final VoidCallback onDone;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _Step {
  hola(1),
  sinCuentas(2),
  codigo(3),
  huella(3),
  listo(4);

  const _Step(this.dot);

  /// Its dot on top: «Huella» belongs to the third step.
  final int dot;
}

class _WelcomePageState extends State<WelcomePage> {
  static const _fade = Duration(milliseconds: 200);
  static const _gap = SizedBox(height: 14);

  var _step = _Step.hola;

  // A step on its way: the phone asked for its biometrics, the code being
  // saved, a system prompt open
  var _busy = false;

  // What «Huella» offers, kept while it is on screen
  BiometricKind? _kind;

  void _go(_Step step) => setState(() {
        _step = step;
        _busy = false;
      });

  /// Back: a step back until the code is saved.
  void _back() {
    switch (_step) {
      // Not while the step after it is on its way
      case _Step.sinCuentas:
        if (!_busy) _go(_Step.hola);
      case _Step.codigo:
        if (!_busy) _go(_Step.sinCuentas);
      case _Step.hola || _Step.huella || _Step.listo:
        break;
    }
  }

  /// Bundled with the app: it opens here, also offline.
  void _openPrivacyPolicy() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()));

  /// «Continuar» on «Sin cuentas ni registros».
  Future<void> _continueToCode() async {
    final lock = AppLock.of(context);
    if (!lock.hasCode) {
      // Back long before the code is typed twice
      unawaited(lock.refreshBiometrics());
      _go(_Step.codigo);
      return;
    }
    // A code saved before the app was closed: no new one
    setState(() => _busy = true);
    final kind = await lock.refreshBiometrics();
    if (mounted) _afterCode(lock, kind);
  }

  /// «Huella» when the phone has a fingerprint or a face and the quick
  /// unlock is still off, else «Listo».
  void _afterCode(AppLockState lock, BiometricKind? kind) {
    if (kind != null && !lock.biometric) {
      _kind = kind;
      _go(_Step.huella);
    } else {
      _go(_Step.listo);
    }
  }

  /// The code typed twice is the app's code from now on. It locks on the
  /// next trip to the background, not now.
  Future<void> _onCreated(String code) async {
    final lock = AppLock.of(context);
    setState(() => _busy = true);
    await lock.setCode(code);
    if (mounted) _afterCode(lock, lock.biometricKind);
  }

  /// «Ahora no» on «Tu código»: no lock at all, the older one neither.
  void _skipCode() {
    AppLock.of(context).removeLock();
    _go(_Step.listo);
  }

  /// «Usar huella»: on once the system prompt says yes. A cancelled prompt
  /// stays here, without an error.
  Future<void> _useBiometric() async {
    final lock = AppLock.of(context);
    setState(() => _busy = true);
    final on = await lock.setBiometric(true);
    if (!mounted) return;
    if (on) {
      _go(_Step.listo);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.of(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return PopScope(
      // Under the lock screen Back is the lock screen's: it leaves the app
      canPop: _step == _Step.hola || lock.locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !lock.locked) _back();
      },
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : _fade,
        transitionBuilder: _crossFade,
        child: LedBoard(
          key: ValueKey(_step),
          header: _StepDots(_step.dot),
          child: ConstrainedBox(
            // Lines a phone wide, also on a tablet
            constraints: const BoxConstraints(maxWidth: 420),
            child: switch (_step) {
              _Step.hola => _hola(),
              _Step.sinCuentas => _sinCuentas(),
              _Step.codigo => _codigo(),
              _Step.huella => _huella(_kind!),
              _Step.listo => _listo(lock),
            },
          ),
        ),
      ),
    );
  }

  /// The new step fades in over the old one, which stays as it was under
  /// it: the board itself never dims. The old one takes no taps and says
  /// nothing.
  static Widget _crossFade(Widget child, Animation<double> animation) =>
      AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final leaving = animation.status == AnimationStatus.reverse;
          return IgnorePointer(
            ignoring: leaving,
            child: ExcludeSemantics(
              excluding: leaving,
              child: Opacity(
                opacity: leaving ? 1 : animation.value,
                child: child,
              ),
            ),
          );
        },
      );

  Widget _hola() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: TimbreColors.lineaNoche),
            ),
            child: const TimbreAppIcon(size: 96),
          ),
          const SizedBox(height: 20),
          const _Sign('HOLA', label: 'Hola'),
          const SizedBox(height: 12),
          const Text(
            'Timbre MVD te muestra los ómnibus de Montevideo como el cartel '
            'de la parada.',
            textAlign: TextAlign.center,
            style: _lead,
          ),
          const SizedBox(height: 24),
          const _Line(
            PixelGlyphs.bus,
            title: 'Mis paradas',
            text: 'Los minutos en vivo de tus paradas, con el GPS de cada '
                'ómnibus.',
          ),
          _gap,
          const _Line(
            PixelGlyphs.streets,
            title: 'Mapa',
            text: 'Los ómnibus que vienen a tus paradas.',
          ),
          _gap,
          const _Line(
            PixelGlyphs.bellRing,
            title: 'Estoy esperando',
            text: 'Te avisamos cuando tu ómnibus está cerca.',
          ),
          const SizedBox(height: 20),
          const Text(
            'App no oficial: no está afiliada con la Intendencia de '
            'Montevideo, el STM ni ninguna empresa de transporte.',
            textAlign: TextAlign.center,
            style: _caption,
          ),
          const SizedBox(height: 24),
          _Primary('Continuar', onPressed: () => _go(_Step.sinCuentas)),
        ],
      );

  Widget _sinCuentas() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Sign('SIN CUENTAS\nNI REGISTROS',
              label: 'Sin cuentas ni registros'),
          const SizedBox(height: 28),
          const _Line(
            PixelGlyphs.check,
            text: 'No tenés que crear una cuenta: la app no te pide nombre, '
                'mail ni teléfono.',
          ),
          _gap,
          const _Line(
            PixelGlyphs.check,
            text: 'No registramos lo que hacés ni lo que buscás. Sin '
                'publicidad, analíticas ni rastreo.',
          ),
          _gap,
          const _Line(
            PixelGlyphs.check,
            text: 'Lo que guardás queda en tu teléfono, no en servidores '
                'nuestros.',
          ),
          const SizedBox(height: 32),
          _Primary('Continuar', onPressed: _busy ? null : _continueToCode),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _openPrivacyPolicy,
            child: const Text('Leer la política de privacidad',
                textAlign: TextAlign.center),
          ),
        ],
      );

  Widget _codigo() => PasscodeCreate(
        sign: 'TU CÓDIGO',
        signLabel: 'Tu código',
        message: 'Elegí 4 cifras para abrir la app.',
        onCreated: _onCreated,
        actions: [
          TextButton(
            onPressed: _busy ? null : _skipCode,
            child: const Text('Ahora no'),
          ),
        ],
      );

  Widget _huella(BiometricKind kind) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixelIcon(biometricGlyph(kind),
              size: 96, color: TimbreColors.ambar, glow: true),
          const SizedBox(height: 24),
          // «HUELLA», «FACE ID», «TOUCH ID»; heard «Huella»
          _Sign(kind.label.toUpperCase(),
              label: kind.label[0].toUpperCase() + kind.label.substring(1)),
          const SizedBox(height: 12),
          Text(
            'Abrí Timbre MVD con ${kind.phrase}. Si no funciona, usás el '
            'código.',
            textAlign: TextAlign.center,
            style: _lead,
          ),
          const SizedBox(height: 32),
          _Primary('Usar ${kind.label}',
              onPressed: _busy ? null : _useBiometric),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => _go(_Step.listo),
            child: const Text('Ahora no'),
          ),
        ],
      );

  Widget _listo(AppLockState lock) {
    final kind = lock.biometricKind;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // With a code the lock boots and its shackle drops: locked
        if (lock.hasCode)
          const LedLock()
        else
          const PixelIcon(PixelGlyphs.unlock,
              size: 96, color: TimbreColors.ambar, glow: true),
        const SizedBox(height: 24),
        const _Sign('LISTO', label: 'Listo'),
        const SizedBox(height: 24),
        if (lock.hasCode) ...[
          const _Line(PixelGlyphs.lock,
              text: 'La app pide tu código al abrirse.'),
          if (lock.biometric && kind != null) ...[
            _gap,
            _Line(biometricGlyph(kind),
                text: 'También se abre con ${kind.phrase}.'),
          ],
        ] else
          const _Line(PixelGlyphs.unlock, text: 'La app se abre sin código.'),
        _gap,
        const _Line(PixelGlyphs.gear,
            text: 'Podés cambiarlo cuando quieras en Ajustes.'),
        if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: 24),
          const WidgetRefreshOptions(),
        ],
        const SizedBox(height: 24),
        _Primary('Empezar', onPressed: widget.onDone),
      ],
    );
  }
}

const _lead = TextStyle(
  fontFamily: TimbreFonts.fira,
  fontSize: 16,
  height: 1.4,
  color: TimbreColors.papel,
);

/// TimbreText.caption a notch larger: it is read, not glanced at.
const _caption = TextStyle(
  fontFamily: TimbreFonts.fira,
  fontSize: 13,
  height: 1.4,
  color: TimbreColors.etiquetaCartel,
);

/// Where the welcome is: a small LED square per step, the current one lit,
/// the others unlit.
class _StepDots extends StatelessWidget {
  const _StepDots(this.current);

  /// From 1.
  final int current;

  static const count = 4;
  static const side = 10.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Paso $current de $count',
      child: CustomPaint(
        size: const Size(count * side + (count - 1) * gap, side),
        painter: _StepDotsPainter(current),
      ),
    );
  }
}

class _StepDotsPainter extends CustomPainter {
  const _StepDotsPainter(this.current);

  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    // Four pixels a square, as the code's dots
    const cell = _StepDots.side / 2;
    // The gap between pixels of the icons and the Doto letters
    const inset = cell * 0.07;
    for (var i = 0; i < _StepDots.count; i++) {
      final lit = i == current - 1;
      final left = i * (_StepDots.side + _StepDots.gap);
      if (lit) {
        // The light of a lit LED around the square
        canvas.drawRect(
          Rect.fromLTWH(left, 0, _StepDots.side, _StepDots.side),
          Paint()
            ..color = TimbreColors.ambar.withValues(alpha: 0.5)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
        );
      }
      // The other steps: dim marks that can be seen, as the code's empty
      // dots
      final paint = Paint()
        ..color = lit ? TimbreColors.ambar : TimbreColors.tenue;
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          canvas.drawRect(
            Rect.fromLTWH(left + x * cell + inset, y * cell + inset,
                cell - 2 * inset, cell - 2 * inset),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StepDotsPainter old) => old.current != current;
}

/// A step's sign in Doto, amber; screen readers hear [label] as a header.
class _Sign extends StatelessWidget {
  const _Sign(this.text, {required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: label,
      excludeSemantics: true,
      // Never below its size: smaller dots stop reading as letters. Too
      // wide for the board with large text, it gets smaller, never cut
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TimbreText.cartel(30).copyWith(letterSpacing: 2),
          ),
        ),
      ),
    );
  }
}

/// A line of a step: a dim LED glyph, the name in bold when there is one,
/// and a sentence. One phrase for screen readers.
class _Line extends StatelessWidget {
  const _Line(this.glyph, {this.title, required this.text});

  final PixelGlyph glyph;
  final String? title;
  final String text;

  static const _title = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: TimbreColors.papel,
  );
  static const _detail = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontSize: 14,
    height: 1.4,
    color: TimbreColors.etiquetaCartel,
  );
  static const _statement = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontSize: 15,
    height: 1.4,
    color: TimbreColors.papel,
  );

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Not lit: a label, not where you act, as in Info
          PixelIcon(glyph,
              size: TimbreIconSize.rowLarge,
              color: TimbreColors.etiquetaCartel),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title, style: _title),
                Text(text, style: title == null ? _statement : _detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The main button of a step: amber, a stadium, as «Desbloquear» on the
/// lock screen.
class _Primary extends StatelessWidget {
  const _Primary(this.label, {required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  static final _style = FilledButton.styleFrom(
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
  );

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: _style,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
