import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../services/app_passcode.dart';
import '../services/device_auth.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/led_keypad.dart';
import 'widgets/pixel_icon.dart';

/// What [PasscodeEntry] shows after a code: nothing (null, accepted), an
/// error, or a wait.
sealed class PasscodeFeedback {
  const PasscodeFeedback();
}

/// Clears the digits and shows [message] in red.
final class PasscodeError extends PasscodeFeedback {
  const PasscodeError(this.message);

  final String message;
}

/// Clears the digits and keeps the keypad off until [until], counting down.
final class PasscodeWait extends PasscodeFeedback {
  const PasscodeWait(this.until);

  final DateTime until;
}

/// The key that opens the system prompt for a fingerprint or a face.
class PasscodeBiometric {
  const PasscodeBiometric({required this.kind, required this.onPressed});

  final BiometricKind kind;
  final VoidCallback onPressed;
}

/// The glyph of the quick unlock: a face for Face ID, else a fingerprint.
PixelGlyph biometricGlyph(BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => PixelGlyphs.face,
  BiometricKind.fingerprint || BiometricKind.touchId => PixelGlyphs.fingerprint,
};

/// The app's code typed on the LED keypad: [leading], the sign, a line of
/// text, the code as LEDs ([CodeDots]), the keypad and [actions] under it.
///
/// After the last digit the keypad goes off while [onSubmit] works. A wrong
/// code lights the dots red for a moment, then clears them; the line says
/// why, in red, until the next digit. A wait counts the seconds down with
/// [AppPasscode.clock], digits off; the quick unlock key still works.
class PasscodeEntry extends StatefulWidget {
  const PasscodeEntry({
    super.key,
    required this.sign,
    required this.signLabel,
    required this.message,
    required this.onSubmit,
    this.waitUntil,
    this.biometric,
    this.leading,
    this.actions = const [],
    this.error,
    this.enabled = true,
  });

  /// Doto sign, uppercase: 'BLOQUEADA', 'TU CÓDIGO'.
  final String sign;

  /// The header screen readers hear: 'Aplicación bloqueada'.
  final String signLabel;

  /// Fira line under the sign.
  final String message;

  /// Called with the 4 digits; null = accepted (stays filled and disabled:
  /// the caller moves on), PasscodeError = clear + show, PasscodeWait = clear
  /// + countdown, keypad off until then.
  final Future<PasscodeFeedback?> Function(String code) onSubmit;

  /// A wait already running when it opens.
  final DateTime? waitUntil;

  final PasscodeBiometric? biometric;

  /// Above the sign: LedLock, a glyph.
  final Widget? leading;

  /// Under the keypad: «¿Olvidaste el código?», «Ahora no».
  final List<Widget> actions;

  /// Shown at once, in red (e.g. «No coinciden…»).
  final String? error;

  /// False while a system prompt is open: every key off.
  final bool enabled;

  @override
  State<PasscodeEntry> createState() => _PasscodeEntryState();
}

class _PasscodeEntryState extends State<PasscodeEntry> {
  /// How long a wrong code stays on the dots, in red.
  static const _redFor = Duration(milliseconds: 650);

  var _code = '';
  var _busy = false;
  var _accepted = false;
  var _red = false;
  String? _error;
  DateTime? _waitUntil;
  var _secondsLeft = 0;

  // The line is a live region when it has news (an error, a wait, the wait
  // over), not for every second of the countdown
  var _live = false;

  Timer? _redTimer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
    _live = _error != null;
    final until = widget.waitUntil;
    if (until != null) _startWait(until);
  }

  @override
  void didUpdateWidget(PasscodeEntry old) {
    super.didUpdateWidget(old);
    final error = widget.error;
    if (error != null && error != old.error) {
      _error = error;
      _live = true;
    }
    // The wait it already counts, passed again by a rebuild of the lock,
    // does not start over
    final until = widget.waitUntil;
    if (until != null && until != old.waitUntil && until != _waitUntil) {
      _startWait(until);
    }
  }

  @override
  void dispose() {
    _redTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  bool get _typing =>
      widget.enabled && !_busy && !_accepted && _waitUntil == null;

  void _type(String digit) {
    if (!_typing || _code.length >= AppPasscode.length) return;
    setState(() {
      _code += digit;
      if (_error != null) {
        _error = null;
        _live = false;
      }
    });
    if (_code.length == AppPasscode.length) _submit();
  }

  void _erase() {
    if (!_typing || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final PasscodeFeedback? feedback;
    try {
      feedback = await widget.onSubmit(_code);
    } catch (_) {
      // The keypad never stays off
      if (mounted) {
        setState(() {
          _busy = false;
          _code = '';
        });
      }
      rethrow;
    }
    if (!mounted) return;
    switch (feedback) {
      case null:
        setState(() {
          _busy = false;
          _accepted = true;
        });
      case PasscodeError(:final message):
        _wrong(() => _error = message);
      case PasscodeWait(:final until):
        _wrong(() {
          _error = null;
          _startWait(until);
        });
    }
  }

  /// The dots go red for a moment, then empty; [show] says why.
  void _wrong(VoidCallback show) {
    unawaited(HapticFeedback.heavyImpact());
    setState(() {
      _red = true;
      _live = true;
      show();
    });
    _redTimer?.cancel();
    _redTimer = Timer(_redFor, () {
      if (!mounted) return;
      setState(() {
        _red = false;
        _busy = false;
        _code = '';
      });
    });
  }

  void _startWait(DateTime until) {
    _waitUntil = until;
    _live = true;
    _count();
  }

  // The whole seconds left, again when they change; at the end the message
  // comes back and the digits turn on
  void _count() {
    _tick?.cancel();
    final until = _waitUntil;
    if (until == null) return;
    // The clock of the wait itself, so a test that moves it moves this too
    final left = until.difference(AppPasscode.clock()).inMilliseconds;
    if (left <= 0) {
      _waitUntil = null;
      return;
    }
    _secondsLeft = (left / 1000).ceil();
    _tick = Timer(Duration(milliseconds: left - (_secondsLeft - 1) * 1000), () {
      if (!mounted) return;
      setState(() {
        _count();
        _live = _waitUntil == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waitUntil != null;
    final error = _error;
    final leading = widget.leading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(height: 20)],
        Semantics(
          header: true,
          label: widget.signLabel,
          excludeSemantics: true,
          // Never below its size: smaller dots stop reading as letters. A
          // sign too wide for the board with large text gets smaller, never
          // cut
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.sign,
                textAlign: TextAlign.center,
                style: TimbreText.cartel(30).copyWith(letterSpacing: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          liveRegion: _live,
          child: Text(
            waiting
                ? 'Demasiados intentos. Probá de nuevo en $_secondsLeft s'
                : error ?? widget.message,
            textAlign: TextAlign.center,
            style: TimbreText.body.copyWith(
              height: 1.4,
              color: waiting || error != null
                  ? TimbreColors.rojoLed
                  : TimbreColors.etiquetaCartel,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          container: true,
          label: '${_code.length} de ${AppPasscode.length} cifras',
          child: CodeDots(filled: _code.length, error: _red),
        ),
        const SizedBox(height: 28),
        // A phone 320 dp wide leaves 272 dp of board: the keys shrink with
        // it, still well over the touch size, instead of running off it
        FittedBox(
          fit: BoxFit.scaleDown,
          child: LedKeypad(
            onDigit: _typing ? _type : null,
            onErase: _typing && _code.isNotEmpty ? _erase : null,
            biometric: widget.biometric,
            enabled: widget.enabled && !_busy && !_accepted,
          ),
        ),
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...widget.actions,
        ],
      ],
    );
  }
}

/// A new code, typed twice on the LED keypad: first [sign] and [message]
/// with [actions] («Ahora no»), then «REPETILO» with «Volver». Two different
/// codes go back to the first step with an error; the same code twice goes
/// to [onCreated], keypad off. No Back handling: the host owns it.
class PasscodeCreate extends StatefulWidget {
  const PasscodeCreate({
    super.key,
    required this.sign,
    required this.signLabel,
    required this.message,
    required this.onCreated,
    this.leading,
    this.actions = const [],
  });

  final String sign;
  final String signLabel;
  final String message;

  /// The new code, typed the same twice. The keypad stays off after it.
  final Future<void> Function(String code) onCreated;

  /// Above the sign on both steps.
  final Widget? leading;

  /// Under the keypad on the first step.
  final List<Widget> actions;

  @override
  State<PasscodeCreate> createState() => _PasscodeCreateState();
}

class _PasscodeCreateState extends State<PasscodeCreate> {
  static const _mismatch = 'No coinciden. Elegí el código de nuevo.';

  // The leading moves from one step to the other instead of starting over
  // (a LedLock would boot again)
  final _leading = GlobalKey();

  String? _first;
  String? _error;
  bool _saving = false;

  Future<PasscodeFeedback?> _choose(String code) async {
    setState(() {
      _first = code;
      _error = null;
    });
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Repetí el código. Ingresá el mismo código otra vez.',
        Directionality.of(context),
      ),
    );
    return null;
  }

  Future<PasscodeFeedback?> _repeat(String code) async {
    if (code != _first) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _first = null;
        _error = _mismatch;
      });
      return null;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreated(code);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return null;
  }

  void _back() => setState(() {
    _first = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final leading = widget.leading == null
        ? null
        : KeyedSubtree(key: _leading, child: widget.leading!);
    if (_first == null) {
      return PasscodeEntry(
        key: const ValueKey('choose'),
        sign: widget.sign,
        signLabel: widget.signLabel,
        message: widget.message,
        error: _error,
        leading: leading,
        actions: widget.actions,
        onSubmit: _choose,
      );
    }
    return PasscodeEntry(
      key: const ValueKey('repeat'),
      sign: 'REPETILO',
      signLabel: 'Repetí el código',
      message: 'Ingresá el mismo código otra vez.',
      leading: leading,
      actions: [
        TextButton(
          onPressed: _saving ? null : _back,
          child: const Text('Volver'),
        ),
      ],
      onSubmit: _repeat,
    );
  }
}
