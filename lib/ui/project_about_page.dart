import 'package:flutter/material.dart';

import '../services/official_sites.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/pixel_icon.dart';
import 'widgets/project_about_link.dart';
import 'widgets/timbre_app_bar.dart';

/// Short, offline introduction. Source URLs stay beside the relevant copy.
class ProjectAboutPage extends StatelessWidget {
  const ProjectAboutPage({super.key});

  Future<void> _visit(BuildContext context, String url) async {
    final opened = await SystemBrowser.open(Uri.parse(url));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el navegador. Revisá que tengas uno activado.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: buildTimbreAppBar(context, title: 'Acerca de'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        const ProjectBrandLogos(),
        const SizedBox(height: 22),
        _section(
          context,
          title: 'Timbre MVD',
          text:
              'Una app gratuita, no oficial y de código abierto para '
              'moverte por Montevideo. Reúne tus paradas, arribos estimados, '
              'mapa, avisos y widgets, y te acerca a los servicios oficiales '
              'del STM.\n\n'
              'Desarrollada por Liberon Tech, de Khrestenkov & Co, '
              'con gratitud hacia Uruguay.',
          link: 'Más sobre el proyecto',
          url: 'https://khrestenkov.com/es/mvd-transporte/',
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'Liberon Tech',
          text:
              'Soluciones de software para empresas: integraciones, '
              'automatización y sistemas de cobros. Liberon Tech forma '
              'parte de Khrestenkov & Co y crea herramientas claras, '
              'documentadas y fáciles de mantener.',
          link: 'Conocé Liberon.tech',
          url: 'https://khrestenkov.com/es/liberon/',
        ),
        const SizedBox(height: 12),
        _section(
          context,
          title: 'Khrestenkov & Co',
          text:
              'Una casa de software independiente con sede en Montevideo. '
              'Crea y mantiene un pequeño grupo de productos propios, '
              'partiendo de los problemas reales de cada operación.',
          link: 'khrestenkov.com',
          url: 'https://khrestenkov.com/es/',
        ),
        const SizedBox(height: 18),
        const Text(
          'Timbre MVD no está afiliada con la Intendencia de Montevideo, '
          'el STM ni ninguna empresa de transporte.',
          textAlign: TextAlign.center,
          style: TimbreText.caption,
        ),
      ],
    ),
  );

  Widget _section(
    BuildContext context, {
    required String title,
    required String text,
    required String link,
    required String url,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: TimbreColors.tinta,
      borderRadius: BorderRadius.circular(TimbreRadii.card),
      border: Border.all(color: TimbreColors.lineaNoche),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TimbreText.dialogTitle.copyWith(color: TimbreColors.papel),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TimbreText.subtitle.copyWith(
              height: 1.45,
              color: TimbreColors.papel,
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            link: true,
            label: '$link, se abre en el navegador',
            onTap: () => _visit(context, url),
            excludeSemantics: true,
            child: TextButton(
              onPressed: () => _visit(context, url),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(link)),
                  const SizedBox(width: 8),
                  const PixelIcon(
                    PixelGlyphs.external,
                    size: 18,
                    color: TimbreColors.ambar,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
