// The LED "cartel" widgets and the bus glyph: live minutes, "LLEGANDO",
// amenities only when the API says so, and readable semantics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/ui/theme/timbre_theme.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';
import 'package:stm_app/ui/widgets/cartel.dart';
import 'package:stm_app/ui/widgets/timbre_bus.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildTimbreTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 358, child: child))),
    );

void main() {
  group('CartelParada', () {
    testWidgets('shows line, destination and live minutes', (tester) async {
      await tester.pumpWidget(_wrap(CartelParada(
        line: '121',
        destination: 'PUNTA CARRETAS',
        etaMinutes: 7,
        updatedAt: DateTime(2026, 10, 24, 20, 3),
        accessible: true,
      )));

      expect(find.text('121'), findsOneWidget);
      expect(find.text('PUNTA CARRETAS'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      expect(find.text('Actualizado 20:03'), findsOneWidget);
      expect(find.text('LLEGANDO'), findsNothing);
    });

    testWidgets('etaMinutes <= 0 shows LLEGANDO instead of minutes',
        (tester) async {
      await tester.pumpWidget(_wrap(const CartelParada(
        line: '121',
        destination: 'PUNTA CARRETAS',
        etaMinutes: 0,
      )));

      expect(find.text('LLEGANDO'), findsOneWidget);
      expect(find.text('min'), findsNothing);
    });

    testWidgets('amenities only when true', (tester) async {
      await tester.pumpWidget(_wrap(const CartelParada(
        line: '116',
        destination: 'POCITOS',
        etaMinutes: 6,
        airConditioning: true,
      )));

      expect(find.text('Aire acondicionado'), findsOneWidget);
      expect(find.text('Accesible'), findsNothing);
      expect(find.text('Cero emisiones'), findsNothing);
    });

    testWidgets('screen readers get one sentence, not dot-matrix glyphs',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(CartelParada(
        line: '121',
        destination: 'PUNTA CARRETAS',
        etaMinutes: 1,
        accessible: true,
        zeroEmission: true,
        onTap: () {},
      )));

      expect(
        find.bySemanticsLabel(
            'Próximo: 121 a Punta Carretas, llega en 1 minuto, con GPS, '
            'accesible, cero emisiones'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('long destinations stay on one line', (tester) async {
      await tester.pumpWidget(_wrap(const CartelParada(
        line: '144',
        destination: 'CEMENTERIO DEL NORTE POR GARZON Y COLON',
        etaMinutes: 12,
      )));

      final text = tester.widget<Text>(
          find.text('CEMENTERIO DEL NORTE POR GARZON Y COLON'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });

  group('MinutosEnVivo', () {
    testWidgets('live minutes with a readable label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const MinutosEnVivo(minutes: 3)));

      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('en 3 minutos, con GPS'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('0 minutes becomes the LLEGANDO chip', (tester) async {
      await tester.pumpWidget(_wrap(const MinutosEnVivo(minutes: 0)));

      expect(find.byType(LlegandoChip), findsOneWidget);
      expect(find.text('LLEGANDO'), findsOneWidget);
    });
  });

  group('CartelTira', () {
    testWidgets('one line for the bus being followed', (tester) async {
      await tester.pumpWidget(_wrap(const CartelTira(
        line: '116',
        destination: 'POCITOS',
        etaMinutes: 6,
      )));

      expect(find.text('116'), findsOneWidget);
      expect(find.text('POCITOS'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('CartelCompacto', () {
    testWidgets('reads as the app name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(const CartelCompacto()));

      expect(find.bySemanticsLabel('Timbre MVD'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('never renders the dots below 19 px', (tester) async {
      await tester.pumpWidget(_wrap(const CartelCompacto(fontSize: 12)));

      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.style!.fontSize, greaterThanOrEqualTo(19));
    });
  });

  group('TimbreBus', () {
    test('detail ladder follows the brand board', () {
      expect(TimbreBusDetail.forHeight(80), TimbreBusDetail.full);
      expect(TimbreBusDetail.forHeight(48), TimbreBusDetail.medium);
      expect(TimbreBusDetail.forHeight(32), TimbreBusDetail.small);
      expect(TimbreBusDetail.forHeight(24), TimbreBusDetail.tiny);
      expect(TimbreBusDetail.forIconSize(87), TimbreBusDetail.full);
      expect(TimbreBusDetail.forIconSize(60), TimbreBusDetail.medium);
      expect(TimbreBusDetail.forIconSize(40), TimbreBusDetail.small);
      expect(TimbreBusDetail.forIconSize(29), TimbreBusDetail.tiny);
    });

    testWidgets('paints at every size without errors', (tester) async {
      for (final h in [20.0, 32.0, 48.0, 100.0]) {
        await tester.pumpWidget(_wrap(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TimbreBus(height: h),
            TimbreBus(height: h, palette: TimbreBusPalette.led),
            TimbreAppIcon(size: h),
          ],
        )));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(TimbreBus).first).width,
            closeTo(h * TimbreBus.aspectRatio, 0.01));
      }
    });
  });

  test('theme: flag blue, Fira, mist background, no amber in the scheme', () {
    final theme = buildTimbreTheme();
    expect(theme.colorScheme.primary, TimbreColors.azul);
    expect(theme.scaffoldBackgroundColor, TimbreColors.niebla);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'FiraSans');
    final schemeColors = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      theme.colorScheme.surface,
    ];
    expect(schemeColors, isNot(contains(TimbreColors.ambar)));
  });
}
