import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/ui/safe_html.dart';

void main() {
  group('htmlToBlocks', () {
    test('real message: heading and paragraph', () {
      // mensajeCompleto of idMensaje 28 (test/fixtures/mensajes_from0.json)
      const html = '<h1>Novedades</h1>\n<p>La nueva versión de la aplicación '
          'tiene un menú con nuevas funcionalidades.</p>';
      expect(htmlToBlocks(html).map((b) => '$b'), [
        'heading: Novedades',
        'paragraph: La nueva versión de la aplicación tiene un menú con '
            'nuevas funcionalidades.',
      ]);
    });

    test('drops scripts, styles and embedded content', () {
      const html = '<p onclick="steal()">Desvíos<script>alert(1)</script></p>'
          '<style>p{color:red}</style><iframe src="https://evil"></iframe>'
          '<img src="x" onerror="alert(2)">';
      expect(htmlToBlocks(html).map((b) => '$b'), ['paragraph: Desvíos']);
    });

    test('decodes entities, keeps <br> and list items', () {
      const html = '<p>L&iacute;nea 121<br>desv&iacute;a</p>'
          '<ul><li>Uno</li><li><b>Dos</b></li></ul>';
      expect(htmlToBlocks(html).map((b) => '$b'), [
        'paragraph: Línea 121\ndesvía',
        'listItem: Uno',
        'listItem: Dos',
      ]);
    });

    test('plain text keeps its paragraphs', () {
      expect(htmlToBlocks('Primero\n\nSegundo\n').map((b) => '$b'),
          ['paragraph: Primero', 'paragraph: Segundo']);
    });
  });

  testWidgets('SafeHtml shows text only', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SafeHtml('<h1>Desvíos</h1><script>alert(1)</script><p>Hoy</p>'),
      ),
    ));
    expect(find.text('Desvíos'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.textContaining('alert'), findsNothing);
  });
}
