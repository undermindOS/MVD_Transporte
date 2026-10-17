import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/transport_news.dart';
import 'safe_html.dart';

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
    final primary = Theme.of(context).primaryColor;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          if (isLoading && news.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          // Offline must not look like "no news"
          if (failed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('No se pudo actualizar. Deslizá para reintentar',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          if (!isLoading && !failed && news.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Sin novedades',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 14)),
            ),
          ...news.map((n) => _buildItem(context, n, primary)),
          if (news.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Publicadas por la Intendencia de Montevideo (Cómo Ir).',
                style: TextStyle(color: Colors.black38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, TransportNews n, Color primary) {
    final isNew = readBefore == null || n.id > readBefore!;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showNewsDetail(context, n),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (isNew) ...[
                  Icon(Icons.circle, size: 8, color: primary,
                      semanticLabel: 'Nueva'),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(n.title,
                      style: TextStyle(
                          fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15)),
                ),
                const SizedBox(width: 8),
                Text(formatNewsDate(n.date),
                    style:
                        const TextStyle(color: Colors.black38, fontSize: 12)),
              ]),
              if (n.summary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(n.summary,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 13)),
              ],
            ],
          ),
        ),
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
          Text(n.title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(formatNewsDate(n.date),
              style: const TextStyle(color: Colors.black45, fontSize: 13)),
          const SizedBox(height: 12),
          DefaultTextStyle.merge(
            style: const TextStyle(
                fontSize: 15, height: 1.45, color: Colors.black87),
            child: SafeHtml(n.body.trim().isNotEmpty ? n.body : n.summary),
          ),
          if (n.link != null) ...[
            const SizedBox(height: 8),
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
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')));
  }
}

String formatNewsDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
