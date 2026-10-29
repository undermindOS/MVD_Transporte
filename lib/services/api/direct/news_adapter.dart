import '../contract_rules.dart';

/// What [NewsAdapter.fetchNewest] needs to know of a page.
abstract interface class NewsPaging {
  /// Number of messages with an id above the requested `fromIdMessage`.
  int get count;

  /// Messages in this page.
  int get size;
}

/// One response of `GET /notificacion/mensajes`, its messages as /v1 news
/// items.
class NewsPageV1 implements NewsPaging {
  @override
  final int count;
  final List<Map<String, Object?>> news;

  const NewsPageV1(this.count, this.news);

  @override
  int get size => news.length;
}

/// Official transport news — the open endpoint Cómo Ir reads
/// (`api.montevideo.gub.uy/notificacion/mensajes?idApp=1`), no credentials —
/// turned into /v1 JSON for the direct mode. The proxy pages the same way
/// (`proxy/src/notificacion.js`).
abstract final class NewsAdapter {
  static const _url = 'https://api.montevideo.gub.uy/notificacion/mensajes';
  // Cómo Ir's application id on the notification backend
  static const _idApp = 1;

  /// Requests of one [fetchNewest] at most.
  static const maxRequests = 8;

  /// Messages in one /v1 answer at most: one page.
  static const maxNews = 10;

  static String pageUrl(int fromId) =>
      '$_url?idApp=$_idApp&fromIdMessage=$fromId';

  /// Finds the newest messages starting from id [from].
  ///
  /// The endpoint returns at most 10 of the messages with an id above
  /// `fromIdMessage`, in storage order (e.g. 43…50, 134, 51), plus `count`
  /// of all of them. Paging by the highest id received — what Cómo Ir does —
  /// therefore skips messages. Instead `from` moves up until everything
  /// above it fits in one page. Ids are near-sequential (the i-th id above
  /// `from` is at least `from + i`), so the jump never overshoots the
  /// newest full page. At most [maxRequests]; null when a page fails.
  static Future<({P page, int from})?> fetchNewest<P extends NewsPaging>(
      int from, Future<P?> Function(int from) getPage) async {
    for (var i = 0; i < maxRequests; i++) {
      final page = await getPage(from);
      if (page == null) return null;
      if (page.count <= page.size || i == maxRequests - 1) {
        return (page: page, from: from);
      }
      from += page.count - page.size;
    }
    return null;
  }

  /// `{"count":144,"messages":[{"idMensaje":"28", …}, …]}`; null when the
  /// answer has no message list.
  static NewsPageV1? pageToV1(Object? raw) {
    if (raw is! Map || raw['messages'] is! List) return null;
    final news =
        (raw['messages'] as List).map(messageToV1).nonNulls.toList();
    final count = raw['count'];
    return NewsPageV1(count is num ? count.toInt() : news.length, news);
  }

  /// One message as a /v1 news item:
  /// `{"idMensaje":"180","titulo":"…","mensajeCorto":"…",
  ///   "mensajeCompleto":"<p>…</p>","dataLink":"https://…","fecha":1790948233228}`
  /// Null without a usable id or date. `idUsuario` and `topicId` are dropped.
  static Map<String, Object?>? messageToV1(Object? raw) {
    if (raw is! Map) return null;
    final id = ContractRules.toIntLoose(raw['idMensaje']);
    final ms = ContractRules.toIntLoose(raw['fecha']);
    // Like the proxy's Date check: a date DateTime cannot hold is no date
    if (id == null || ms == null || ms.abs() > ContractRules.maxDateMs) {
      return null;
    }
    String trimmed(Object? value) =>
        ContractRules.trimText(ContractRules.text(value));
    return {
      'id': id,
      'title': trimmed(raw['titulo']),
      'summary': trimmed(raw['mensajeCorto']),
      'body': trimmed(raw['mensajeCompleto']),
      'link': ContractRules.newsLink(raw['dataLink']),
      'publishedAt':
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String(),
    };
  }

  /// The messages of the last page reached, newest first, as /v1 `news`.
  static Map<String, Object?> messagesToV1(NewsPageV1 page,
      {required DateTime fetchedAt}) {
    final sorted = [...page.news]..sort((a, b) {
        final byDate =
            (b['publishedAt'] as String).compareTo(a['publishedAt'] as String);
        return byDate != 0 ? byDate : (b['id'] as int).compareTo(a['id'] as int);
      });
    return {
      'fetchedAt': ContractRules.isoUtc(fetchedAt),
      'news': sorted.take(maxNews).toList(),
    };
  }
}
