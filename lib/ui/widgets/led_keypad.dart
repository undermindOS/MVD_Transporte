import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_passcode.dart';
import '../passcode_entry.dart';
import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';
import 'pixel_icon.dart';

/// The code as LEDs: a square of four dots per digit, lit amber for each
/// digit typed, unlit for the rest; all red after a wrong code. Decoration:
/// the screen reader hears the count from `PasscodeEntry`.
class CodeDots extends StatelessWidget {
  const CodeDots({
    super.key,
    required this.filled,
    this.length = AppPasscode.length,
    this.error = false,
  });

  /// Digits typed.
  final int filled;
  final int length;

  /// The code was wrong: every square lit in [TimbreColors.rojoLed].
  final bool error;

  /// Side of one digit's square, and the space between two.
  static const side = 16.0;
  static const gap = 20.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(length * side + (length - 1) * gap, side),
        painter: _CodeDotsPainter(filled: filled, length: length, error: error),
      ),
    );
  }
}

class _CodeDotsPainter extends CustomPainter {
  _CodeDotsPainter({
    required this.filled,
    required this.length,
    required this.error,
  });

  final int filled;
  final int length;
  final bool error;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = CodeDots.side / 2;
    // The gap between pixels of the icons and the Doto letters
    const inset = cell * 0.07;
    final lit = error ? TimbreColors.rojoLed : TimbreColors.ambar;
    for (var i = 0; i < length; i++) {
      final on = error || i < filled;
      final square = Rect.fromLTWH(
        i * (CodeDots.side + CodeDots.gap),
        0,
        CodeDots.side,
        CodeDots.side,
      );
      if (on) {
        // The light of a lit LED around the square
        canvas.drawRect(
          square,
          Paint()
            ..color = lit.withValues(alpha: 0.5)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
        );
      }
      // Empty: a dim mark, not an unlit LED of the board (1.35:1), so the
      // places left can be seen (3:1 or more for marks that mean something)
      final paint = Paint()..color = on ? lit : TimbreColors.tenue;
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          canvas.drawRect(
            Rect.fromLTWH(
              square.left + x * cell + inset,
              y * cell + inset,
              cell - 2 * inset,
              cell - 2 * inset,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CodeDotsPainter old) =>
      old.filled != filled || old.length != length || old.error != error;
}

/// The code keypad on the LED board: `1 2 3 / 4 5 6 / 7 8 9 / [quick
/// unlock] 0 [erase]`. The digits are dark LED windows with Fira digits in
/// [TimbreColors.papel]; a pressed key lights up (raised panel, amber
/// digit), then fades out. The quick unlock and erase keys are glyphs
/// without a window. Each key is one button for screen readers.
class LedKeypad extends StatelessWidget {
  const LedKeypad({
    super.key,
    required this.onDigit,
    required this.onErase,
    this.biometric,
    this.enabled = true,
  });

  /// A digit key: '0' to '9'. Null turns the digit keys off.
  final ValueChanged<String>? onDigit;

  /// Null turns the erase key off: nothing to erase.
  final VoidCallback? onErase;

  /// The quick unlock key, bottom left; empty without it.
  final PasscodeBiometric? biometric;

  /// False turns every key off, the quick unlock one too.
  final bool enabled;

  static const keyWidth = 84.0;
  static const keyHeight = 64.0;
  static const columnGap = 16.0;
  static const rowGap = 12.0;

  /// The quick unlock and erase glyphs: 7 device pixels a cell at 3×.
  static const glyphSize = 28.0;

  /// The whole keypad: 284 × 292. The keys keep their size with large text.
  static const size = Size(
    3 * keyWidth + 2 * columnGap,
    4 * keyHeight + 3 * rowGap,
  );

  @override
  Widget build(BuildContext context) {
    final digit = enabled ? onDigit : null;
    final erase = enabled ? onErase : null;
    final quick = biometric;

    Widget key(String d) => _Key(
      label: d,
      onPressed: digit == null ? null : () => digit(d),
      digit: d,
    );
    Widget row(List<Widget> keys) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        keys[0],
        const SizedBox(width: columnGap),
        keys[1],
        const SizedBox(width: columnGap),
        keys[2],
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([key('1'), key('2'), key('3')]),
          const SizedBox(height: rowGap),
          row([key('4'), key('5'), key('6')]),
          const SizedBox(height: rowGap),
          row([key('7'), key('8'), key('9')]),
          const SizedBox(height: rowGap),
          row([
            quick == null
                ? const SizedBox(width: keyWidth, height: keyHeight)
                : _Key(
                    label: 'Desbloquear con ${quick.kind.label}',
                    onPressed: enabled ? quick.onPressed : null,
                    glyph: biometricGlyph(quick.kind),
                    ink: TimbreColors.ambar,
                  ),
            key('0'),
            _Key(label: 'Borrar', onPressed: erase, glyph: PixelGlyphs.erase),
          ]),
        ],
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.digit,
    this.glyph,
    this.ink = TimbreColors.papel,
  });

  /// What the screen reader says.
  final String label;
  final VoidCallback? onPressed;

  /// A digit key, in its LED window.
  final String? digit;

  /// Or a glyph key, without a window until pressed.
  final PixelGlyph? glyph;

  /// The digit or glyph when not pressed.
  final Color ink;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 220);

  // With reduced motion a press stays lit this long and goes out at once
  static const _hold = Duration(milliseconds: 120);

  static const _digitStyle = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w600,
    fontSize: 30,
    height: 1,
  );

  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: _fade,
  );

  bool _focused = false;

  void _highlight(bool down) {
    if (down) {
      _light.value = 1;
      return;
    }
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _light.animateTo(
      0,
      duration: still ? _hold : _fade,
      curve: still ? const Threshold(1) : Curves.easeOut,
    );
  }

  void _press() {
    unawaited(HapticFeedback.lightImpact());
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onPressed != null;
    final window = widget.digit != null;
    final radius = BorderRadius.circular(TimbreRadii.control);
    return Semantics(
      container: true,
      button: true,
      enabled: on,
      label: widget.label,
      child: SizedBox(
        width: LedKeypad.keyWidth,
        height: LedKeypad.keyHeight,
        child: InkWell(
          onTap: on ? _press : null,
          onHighlightChanged: _highlight,
          onFocusChange: (focused) => setState(() => _focused = focused),
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _light,
              builder: (context, _) {
                // A key turned off by its own press still fades out
                final t = _light.value;
                final ink = Color.lerp(
                  on ? widget.ink : TimbreColors.tenue,
                  TimbreColors.ambar,
                  t,
                )!;
                final rest = window ? TimbreColors.noche : Colors.transparent;
                final edge = window
                    ? TimbreColors.lineaNoche
                    : Colors.transparent;
                final digit = widget.digit;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    // Pressed: a raised panel, lit
                    color: Color.lerp(rest, TimbreColors.tintaAlta, t),
                    borderRadius: radius,
                    border: Border.all(
                      color: _focused
                          ? TimbreColors.ambar
                          : Color.lerp(edge, TimbreColors.ambarTenue, t)!,
                      width: _focused ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: digit != null
                        // The keys keep their size: the digits stop growing
                        ? MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.3,
                            child: Text(
                              digit,
                              style: _digitStyle.copyWith(
                                color: ink,
                                shadows: [
                                  Shadow(
                                    color: TimbreColors.ambar.withValues(
                                      alpha: 0.6 * t,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : PixelIcon(
                            widget.glyph!,
                            size: LedKeypad.glyphSize,
                            color: ink,
                            glow: t > 0.5,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
