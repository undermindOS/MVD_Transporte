// The code keypad: PasscodeEntry sends the 4 digits once and shows what
// came of them (busy, a wrong code in red, the wait counting down with
// AppPasscode.clock, accepted), Borrar and the quick unlock key;
// PasscodeCreate asks for the code twice (match, mismatch, «Volver»); the
// sign, the dots and the keys as screen readers get them; the three glyphs
// of the lock.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/device_auth.dart';
import 'package:stm_app/ui/passcode_entry.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/widgets/led_board.dart';
import 'package:stm_app/ui/widgets/led_keypad.dart';
import 'package:stm_app/ui/widgets/led_lock.dart';
import 'package:stm_app/ui/widgets/pixel_icon.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: buildTimbreTheme(),
  builder: (context, navigator) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: navigator!,
  ),
  home: LedBoard(child: child),
);

PasscodeEntry _entry({
  Future<PasscodeFeedback?> Function(String code)? onSubmit,
  DateTime? waitUntil,
  PasscodeBiometric? biometric,
  bool enabled = true,
}) => PasscodeEntry(
  sign: 'BLOQUEADA',
  signLabel: 'Aplicación bloqueada',
  message: 'Ingresá tu código',
  onSubmit: onSubmit ?? (_) async => null,
  waitUntil: waitUntil,
  biometric: biometric,
  enabled: enabled,
);

PasscodeCreate _create(List<String> created, {Widget? leading}) =>
    PasscodeCreate(
      sign: 'TU CÓDIGO',
      signLabel: 'Tu código',
      message: 'Elegí 4 cifras para abrir la app.',
      leading: leading,
      actions: [TextButton(onPressed: () {}, child: const Text('Ahora no'))],
      onCreated: (code) async => created.add(code),
    );

Future<void> _type(WidgetTester tester, String code) async {
  for (final digit in code.split('')) {
    await tester.ensureVisible(find.text(digit));
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

Color? _ink(WidgetTester tester, String digit) =>
    tester.widget<Text>(find.text(digit)).style?.color;

CodeDots _dots(WidgetTester tester) =>
    tester.widget<CodeDots>(find.byType(CodeDots));

Finder _glyph(PixelGlyph glyph) =>
    find.byWidgetPredicate((w) => w is PixelIcon && w.glyph == glyph);

Matcher _key({required bool on}) => isSemantics(
  isButton: true,
  hasEnabledState: true,
  isEnabled: on,
  hasTapAction: on,
);

void main() {
  tearDown(() => AppPasscode.clock = DateTime.now);

  testWidgets('the 4 digits go once to onSubmit; meanwhile the keypad is off', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final codes = <String>[];
    final answer = Completer<PasscodeFeedback?>();
    await tester.pumpWidget(
      _app(
        _entry(
          onSubmit: (code) {
            codes.add(code);
            return answer.future;
          },
        ),
      ),
    );

    await _type(tester, '1234');
    expect(codes, ['1234']);
    // Busy: the dots stay lit, no key answers
    expect(_dots(tester).filled, 4);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: false));
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(codes, ['1234']);

    // Accepted: filled and off, the caller moves on
    answer.complete(null);
    await tester.pump();
    expect(_dots(tester).filled, 4);
    expect(_dots(tester).error, isFalse);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: false));
    handle.dispose();
  });

  testWidgets('a wrong code: red dots for a moment, then empty; the reason '
      'stays in red until the next digit', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        _entry(onSubmit: (_) async => const PasscodeError('Código incorrecto')),
      ),
    );

    await _type(tester, '1234');
    expect(_dots(tester).filled, 4);
    expect(_dots(tester).error, isTrue);
    expect(
      tester.widget<Text>(find.text('Código incorrecto')).style?.color,
      TimbreColors.rojoLed,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Código incorrecto')),
      isSemantics(isLiveRegion: true),
    );
    expect(find.text('Ingresá tu código'), findsNothing);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: false));

    await tester.pump(const Duration(milliseconds: 700));
    expect(_dots(tester).filled, 0);
    expect(_dots(tester).error, isFalse);
    expect(find.text('Código incorrecto'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: true));

    await _type(tester, '5');
    expect(find.text('Código incorrecto'), findsNothing);
    expect(find.text('Ingresá tu código'), findsOneWidget);
    expect(_dots(tester).filled, 1);
    handle.dispose();
  });

  testWidgets('a wait counts down with AppPasscode.clock, digits off and the '
      'quick unlock on, then the message comes back', (tester) async {
    final handle = tester.ensureSemantics();
    var now = DateTime(2026, 10, 29, 12);
    AppPasscode.clock = () => now;
    var quick = 0;
    await tester.pumpWidget(
      _app(
        _entry(
          onSubmit: (_) async => PasscodeWait(now.add(AppPasscode.wait)),
          biometric: PasscodeBiometric(
            kind: BiometricKind.fingerprint,
            onPressed: () => quick++,
          ),
        ),
      ),
    );

    await _type(tester, '1234');
    const wait30 = 'Demasiados intentos. Probá de nuevo en 30 s';
    expect(find.text(wait30), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(wait30)).style?.color,
      TimbreColors.rojoLed,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(wait30)),
      isSemantics(isLiveRegion: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(_dots(tester).filled, 0);
    expect(find.text(wait30), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: false));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Desbloquear con huella')),
      _key(on: true),
    );
    await tester.tap(_glyph(PixelGlyphs.fingerprint));
    expect(quick, 1);

    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    const wait20 = 'Demasiados intentos. Probá de nuevo en 20 s';
    expect(find.text(wait20), findsOneWidget);
    // Said once, when it started: the seconds change without a word
    expect(
      tester.getSemantics(find.bySemanticsLabel(wait20)),
      isSemantics(isLiveRegion: false),
    );

    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Demasiados intentos'), findsNothing);
    expect(find.text('Ingresá tu código'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('5')), _key(on: true));
    await _type(tester, '5');
    expect(_dots(tester).filled, 1);
    handle.dispose();
  });

  testWidgets('opened during a wait: the countdown first', (tester) async {
    var now = DateTime(2026, 10, 29, 12);
    AppPasscode.clock = () => now;
    final codes = <String>[];
    await tester.pumpWidget(
      _app(
        _entry(
          waitUntil: now.add(const Duration(seconds: 5)),
          onSubmit: (code) async {
            codes.add(code);
            return null;
          },
        ),
      ),
    );
    expect(
      find.text('Demasiados intentos. Probá de nuevo en 5 s'),
      findsOneWidget,
    );
    await _type(tester, '1');
    expect(_dots(tester).filled, 0);

    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ingresá tu código'), findsOneWidget);
    await _type(tester, '2580');
    expect(codes, ['2580']);
  });

  testWidgets('Borrar takes back the last digit; off with nothing to erase', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final codes = <String>[];
    await tester.pumpWidget(
      _app(
        _entry(
          onSubmit: (code) async {
            codes.add(code);
            return null;
          },
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Borrar')),
      _key(on: false),
    );

    await _type(tester, '12');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Borrar')),
      _key(on: true),
    );
    await tester.tap(_glyph(PixelGlyphs.erase));
    await tester.pump();
    expect(_dots(tester).filled, 1);
    await _type(tester, '345');
    expect(codes, ['1345']);
    handle.dispose();
  });

  testWidgets(
    'the quick unlock key only when given, with its glyph and label',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_entry()));
      expect(find.bySemanticsLabel(RegExp('^Desbloquear con')), findsNothing);
      expect(_glyph(PixelGlyphs.fingerprint), findsNothing);
      expect(_glyph(PixelGlyphs.face), findsNothing);

      final glyphs = {
        BiometricKind.fingerprint: PixelGlyphs.fingerprint,
        BiometricKind.faceId: PixelGlyphs.face,
        BiometricKind.touchId: PixelGlyphs.fingerprint,
      };
      for (final MapEntry(key: kind, value: glyph) in glyphs.entries) {
        var pressed = 0;
        await tester.pumpWidget(
          _app(
            _entry(
              biometric: PasscodeBiometric(
                kind: kind,
                onPressed: () => pressed++,
              ),
            ),
          ),
        );
        expect(biometricGlyph(kind), glyph);
        expect(_glyph(glyph), findsOneWidget, reason: kind.label);
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('Desbloquear con ${kind.label}'),
          ),
          _key(on: true),
        );
        await tester.tap(_glyph(glyph));
        expect(pressed, 1, reason: kind.label);
      }

      // A system prompt is open: every key off, the quick unlock too
      var pressed = 0;
      await tester.pumpWidget(
        _app(
          _entry(
            enabled: false,
            biometric: PasscodeBiometric(
              kind: BiometricKind.faceId,
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Desbloquear con Face ID')),
        _key(on: false),
      );
      expect(tester.getSemantics(find.bySemanticsLabel('1')), _key(on: false));
      await tester.tap(_glyph(PixelGlyphs.face));
      await _type(tester, '1');
      expect(pressed, 0);
      expect(_dots(tester).filled, 0);
      handle.dispose();
    },
  );

  testWidgets('screen readers: the sign is a header, the dots a count, each '
      'key one button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        _entry(
          biometric: PasscodeBiometric(
            kind: BiometricKind.fingerprint,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Aplicación bloqueada')),
      isSemantics(isHeader: true),
    );
    expect(find.bySemanticsLabel('BLOQUEADA'), findsNothing);
    expect(find.bySemanticsLabel('0 de 4 cifras'), findsOneWidget);
    for (var d = 0; d <= 9; d++) {
      expect(
        tester.getSemantics(find.bySemanticsLabel('$d')),
        _key(on: true),
        reason: '$d',
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Desbloquear con huella')),
      _key(on: true),
    );
    // The dots are paint: the count above is all a screen reader gets
    expect(
      find.descendant(
        of: find.byType(CodeDots),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );

    await _type(tester, '12');
    expect(find.bySemanticsLabel('2 de 4 cifras'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a pressed key lights amber, then fades out; with reduced '
      'motion it goes out at once', (tester) async {
    await tester.pumpWidget(_app(_entry()));
    expect(_ink(tester, '1'), TimbreColors.papel);
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(_ink(tester, '1'), TimbreColors.ambar);
    await tester.pump(const Duration(milliseconds: 110));
    expect(
      _ink(tester, '1'),
      isNot(anyOf(TimbreColors.ambar, TimbreColors.papel)),
    );
    await tester.pumpAndSettle();
    expect(_ink(tester, '1'), TimbreColors.papel);

    await tester.pumpWidget(_app(_entry(), reduceMotion: true));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(_ink(tester, '2'), TimbreColors.ambar);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_ink(tester, '2'), TimbreColors.ambar);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_ink(tester, '2'), TimbreColors.papel);
    await tester.pumpAndSettle();
  });

  group('PasscodeCreate', () {
    testWidgets('the same code twice: onCreated once, with it', (tester) async {
      final handle = tester.ensureSemantics();
      final created = <String>[];
      await tester.pumpWidget(_app(_create(created)));
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);

      await _type(tester, '1234');
      expect(find.text('REPETILO'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Repetí el código')),
        isSemantics(isHeader: true),
      );
      expect(find.text('Ingresá el mismo código otra vez.'), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);
      // The actions belong to the first step
      expect(find.text('Ahora no'), findsNothing);
      expect(_dots(tester).filled, 0);

      await _type(tester, '1234');
      expect(created, ['1234']);
      handle.dispose();
    });

    testWidgets('two different codes: back to the first step, with why', (
      tester,
    ) async {
      final created = <String>[];
      await tester.pumpWidget(_app(_create(created)));
      await _type(tester, '1234');
      await _type(tester, '4321');

      expect(created, isEmpty);
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      const mismatch = 'No coinciden. Elegí el código de nuevo.';
      expect(find.text(mismatch), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(mismatch)).style?.color,
        TimbreColors.rojoLed,
      );
      expect(find.text('Ahora no'), findsOneWidget);

      await _type(tester, '9');
      expect(find.text(mismatch), findsNothing);
      await _type(tester, '876');
      await _type(tester, '9876');
      expect(created, ['9876']);
    });

    testWidgets('«Volver» goes back to the first step, the leading stays', (
      tester,
    ) async {
      final created = <String>[];
      await tester.pumpWidget(
        _app(_create(created, leading: const LedLock(pitch: 6))),
      );
      final lock = tester.state(find.byType(LedLock));

      await _type(tester, '1234');
      expect(find.text('REPETILO'), findsOneWidget);
      // Moved to the second step, not built again: a LedLock does not boot
      // twice
      expect(tester.state(find.byType(LedLock)), same(lock));

      await tester.ensureVisible(find.text('Volver'));
      await tester.tap(find.text('Volver'));
      await tester.pump();
      expect(find.text('TU CÓDIGO'), findsOneWidget);
      expect(find.textContaining('No coinciden'), findsNothing);
      expect(_dots(tester).filled, 0);
      expect(tester.state(find.byType(LedLock)), same(lock));

      await _type(tester, '5678');
      await _type(tester, '5678');
      expect(created, ['5678']);
    });
  });

  test('the lock glyphs are 12 × 12 cells, lit or unlit', () {
    for (final glyph in [
      PixelGlyphs.fingerprint,
      PixelGlyphs.face,
      PixelGlyphs.erase,
    ]) {
      expect(glyph.rows, hasLength(PixelGlyph.size));
      for (final row in glyph.rows) {
        expect(row, matches(RegExp(r'^[#.]{12}$')));
      }
    }
  });
}
