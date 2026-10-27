// The privacy policy screen: docs/privacy-policy.md, bundled as an asset,
// read with the small Markdown renderer of lib/ui/policy_markdown.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stm_app/ui/policy_markdown.dart';
import 'package:stm_app/ui/privacy_policy_page.dart';
import 'package:stm_app/ui/theme/timbre_theme.dart';

import 'support/layout.dart';

/// [textScale] 2.0 is the largest Android font size ("Largest", Android 14+).
Widget _app({double textScale = 1}) => MaterialApp(
      theme: buildTimbreTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const PrivacyPolicyPage(),
    );

void main() {
  group('policyToBlocks', () {
    test('title, headings and paragraphs joined across lines', () {
      const md = '# Política de privacidad\n'
          '\n'
          'Timbre MVD es una aplicación\n'
          'no oficial.\n'
          '\n'
          '## Resumen\n'
          'Primer párrafo.\n'
          '\n'
          'Segundo párrafo.\n';
      expect(policyToBlocks(md).map((b) => '$b'), [
        'title: Política de privacidad',
        'paragraph: Timbre MVD es una aplicación no oficial.',
        'heading: Resumen',
        'paragraph: Primer párrafo.',
        'paragraph: Segundo párrafo.',
      ]);
    });

    test('list items, each continued on indented lines', () {
      const md = 'Antes.\n'
          '- No tenés que crear una cuenta.\n'
          '- Lo que guardás en la app queda\n'
          '  en tu teléfono.\n'
          '\n'
          'Después.\n';
      expect(policyToBlocks(md).map((b) => '$b'), [
        'paragraph: Antes.',
        'bullet: No tenés que crear una cuenta.',
        'bullet: Lo que guardás en la app queda en tu teléfono.',
        'paragraph: Después.',
      ]);
    });

    test('bold and code spans', () {
      final blocks = policyToBlocks('**Ubicación.** Solo si usás la app: '
          'consulta `api.montevideo.gub.uy` y nada más.');
      expect(blocks, hasLength(1));
      expect(blocks.single.spans.map((s) => (s.text, s.bold, s.code)), [
        ('Ubicación.', true, false),
        (' Solo si usás la app: consulta ', false, false),
        ('api.montevideo.gub.uy', false, true),
        (' y nada más.', false, false),
      ]);
      expect(blocks.single.text,
          'Ubicación. Solo si usás la app: consulta api.montevideo.gub.uy '
          'y nada más.');
    });

    test('quoted lines are notes for the maintainer: skipped', () {
      const md = '# Política\n'
          '\n'
          '> Borrador. Revisarlo antes de\n'
          '> publicarlo.\n'
          '>\n'
          '> Otra nota con `MVD_PROXY_URL`.\n'
          '\n'
          '**Última actualización:** 27 de octubre de 2026\n';
      expect(policyToBlocks(md).map((b) => '$b'), [
        'title: Política',
        'paragraph: **Última actualización:** 27 de octubre de 2026',
      ]);
    });

    test('the real policy: no maintainer notes, no placeholders', () {
      final blocks =
          policyToBlocks(File(PrivacyPolicyPage.asset).readAsStringSync());
      expect(blocks.first.kind, PolicyBlockKind.title);
      final text = blocks.map((b) => b.text).join('\n');
      for (final hidden in ['Borrador', '>', '[fecha]', '**', '`']) {
        expect(text, isNot(contains(hidden)), reason: hidden);
      }
    });
  });

  group('Privacidad', () {
    setUpAll(loadBundledFonts);

    testWidgets('shows the bundled policy, without the maintainer note',
        (tester) async {
      usePhoneScreen(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('PRIVACIDAD'), findsOneWidget); // the page title
      expect(
          find.text('Política de privacidad — Timbre MVD'), findsOneWidget);
      expect(find.text('Última actualización: 27 de octubre de 2026'),
          findsOneWidget);
      expect(find.text('RESUMEN'), findsOneWidget);
      expect(find.textContaining('Borrador'), findsNothing);
      expect(find.textContaining('[fecha]'), findsNothing);
      expect(find.textContaining('>'), findsNothing);
      // Headings are headings for screen readers, in words, not capitals
      expect(tester.getSemantics(find.bySemanticsLabel('Resumen')),
          isSemantics(isHeader: true));
      expect(
          tester.getSemantics(
              find.bySemanticsLabel('Política de privacidad — Timbre MVD')),
          isSemantics(isHeader: true));

      await tester.scrollUntilVisible(find.text('TUS DERECHOS'), 300);
      expect(tester.getSemantics(find.bySemanticsLabel('Tus derechos')),
          isSemantics(isHeader: true));
      expect(find.textContaining('Ley N° 18.331'), findsOneWidget);
      expect(find.textContaining('>'), findsNothing);
      handle.dispose();
    });

    // Older riders use big fonts: nothing may overflow (an overflow fails
    // the test) down to the last line of the policy
    testWidgets('Text at 2x: nothing overflows', (tester) async {
      usePhoneScreen(tester);
      await tester.pumpWidget(_app(textScale: 2));
      await tester.pumpAndSettle();

      // The longest address is not split in two lines
      const address = 'geoserver.montevideo.gub.uy';
      for (final paragraph in ['Tiempos de arribo', 'Ubicación.']) {
        final finder = find.textContaining(paragraph);
        await tester.scrollUntilVisible(finder, 400);
        final render = tester.renderObject<RenderParagraph>(finder);
        final start = render.text.toPlainText().indexOf(address);
        final boxes = render.getBoxesForSelection(TextSelection(
            baseOffset: start, extentOffset: start + address.length));
        expect(boxes.map((box) => box.top).toSet(), hasLength(1),
            reason: paragraph);
      }

      await tester.scrollUntilVisible(
          find.textContaining('la fecha de arriba'), 400);
      expect(tester.getRect(find.text('CAMBIOS')).right,
          lessThanOrEqualTo(390 - 16));
    });
  });
}
