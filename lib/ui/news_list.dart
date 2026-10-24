import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/transport_news.dart';
import 'safe_html.dart';
import 'theme/timbre_text.dart';
import 'theme/timbre_tokens.dart';
import 'widgets/empty_state.dart';
import 'widgets/led_matrix.dart';

/// Official transport news (detours, line changes), newest first.
class NewsList extends StatelessWidget {
  final List<TransportNews> news;

  /// Messages with a higher id were unread when the list was opened.
  /// null = the user never opened the news.
  final int? readBefore;
  final bool isLoading;
  final bool failed;
  final Future<void> Function() onRefresh;

  const NewsList({
    super.key,
    required this.news,
    required this.readBefore,
    required this.isLoading,
    required this.failed,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TimbreColors.blanco,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (isLoading && news.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            // Offline must not look like "no news"
            if (failed) const _FailedBanner(),
            if (!isLoading && !failed && news.isEmpty)
              const TimbreEmptyState(
                'Sin novedades',
                detail: 'Los desvíos y cambios de recorrido aparecen acá.',
              ),
            for (final n in news)
              _NewsRow(
                news: n,
                isNew: readBefore == null || n.id > readBefore!,
              ),
            if (news.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  'Publicadas por la Intendencia de Montevideo (Cómo Ir).',
                  style: TextStyle(color: TimbreColors.grisTexto, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FailedBanner extends StatelessWidget {
  const _FailedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TimbreColors.avisoFondo,
        borderRadius: BorderRadius.circular(TimbreRadii.control),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 20, color: TimbreColors.aviso),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No se pudo actualizar. Deslizá para reintentar',
              style: TextStyle(
                color: TimbreColors.aviso,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.news, required this.isNew});

  final TransportNews news;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final n = news;
    return Material(
      color: isNew ? const Color(0xFFF6F8FC) : TimbreColors.blanco,
      child: InkWell(
        onTap: () => showNewsDetail(context, n),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: TimbreColors.separador)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateTile(date: n.date, filled: isNew),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNew) ...[
                      const Text(
                        'NUEVA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.72,
                          color: TimbreColors.azul,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      n.title,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                        color: TimbreColors.tinta,
                      ),
                    ),
                    if (n.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        n.summary,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: TimbreColors.grisTexto,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day and month in a tile: filled blue while unread, outlined after.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.filled});

  final DateTime date;
  final bool filled;

  static const _months = [
    'ENE',
    'FEB',
    'MAR',
    'ABR',
    'MAY',
    'JUN',
    'JUL',
    'AGO',
    'SET',
    'OCT',
    'NOV',
    'DIC',
  ];
  static const _monthNames = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'setiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final fg = filled ? TimbreColors.blanco : TimbreColors.tinta;
    return Semantics(
      label: '${date.day} de ${_monthNames[date.month - 1]}',
      excludeSemantics: true,
      child: Container(
        width: 52,
        height: 56,
        decoration: BoxDecoration(
          color: filled ? TimbreColors.azul : TimbreColors.blanco,
          borderRadius: BorderRadius.circular(10),
          border:
              filled ? null : Border.all(color: TimbreColors.linea, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(alignment: Alignment.center, children: [
          // Unread: a small board, like the header
          if (filled) const Positioned.fill(child: LedMatrix(opacity: 0.55)),
          // Fixed tile: with the largest system fonts the date scales down
          // inside it (the title next to it does grow)
          Padding(
            padding: const EdgeInsets.all(4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    date.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontFamily: TimbreFonts.firaCondensed,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      height: 1,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _months[date.month - 1],
                    style: TextStyle(
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.96,
                      color: filled ? fg : TimbreColors.grisTexto,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full message in a bottom sheet; the link opens in the system browser.
Future<void> showNewsDetail(BuildContext context, TransportNews n) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            n.title,
            style: const TextStyle(
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: TimbreColors.tinta,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatNewsDate(n.date),
            style: const TextStyle(color: TimbreColors.grisTexto, fontSize: 13),
          ),
          const SizedBox(height: 14),
          DefaultTextStyle.merge(
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: TimbreColors.tinta,
            ),
            child: SafeHtml(n.body.trim().isNotEmpty ? n.body : n.summary),
          ),
          if (n.link != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => openExternalLink(ctx, n.link!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Ver más'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Opens http(s) links in the system browser, never inside the app.
Future<void> openExternalLink(BuildContext context, String link) async {
  final uri = Uri.tryParse(link);
  var ok = false;
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('❌ Open link error: $e');
    }
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace')));
  }
}

String formatNewsDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
