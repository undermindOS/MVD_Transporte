/// Official transport news published by the Intendencia de Montevideo
/// (detours, line changes, holiday timetables) — the messages Cómo Ir shows.
class TransportNews {
  final int id;
  final String title;
  final String summary;

  /// HTML or plain text. Render with `SafeHtml`, never in a WebView.
  final String body;

  /// Details page on montevideo.gub.uy (sometimes another site).
  final String? link;
  final DateTime date;

  const TransportNews({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.date,
    this.link,
  });

  /// One item of `GET /notificacion/mensajes`:
  /// `{"idMensaje":"180","titulo":"…","mensajeCorto":"…",
  ///   "mensajeCompleto":"<p>…</p>","dataLink":"https://…","fecha":1790948233228}`
  /// Returns null without a usable id or date.
  static TransportNews? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = int.tryParse(json['idMensaje']?.toString() ?? '');
    final fecha = json['fecha'];
    final ms = fecha is num ? fecha.toInt() : int.tryParse('$fecha');
    if (id == null || ms == null) return null;

    final link = json['dataLink']?.toString().trim() ?? '';
    return TransportNews(
      id: id,
      title: json['titulo']?.toString().trim() ?? '',
      summary: json['mensajeCorto']?.toString().trim() ?? '',
      body: json['mensajeCompleto']?.toString() ?? '',
      link: link.isEmpty || link == 'null' ? null : link,
      date: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// One item of /v1 `news` — the only reader of the network answers:
  /// `{"id":182,"title":"…","summary":"…","body":"<p>…</p>",
  ///   "link":"https://…","publishedAt":"2026-10-26T18:28:02.591Z"}`
  /// Returns null without a usable id or date. [date] is local time, as
  /// [fromJson] gives it.
  static TransportNews? fromV1(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final published = json['publishedAt'];
    final date = published is String ? DateTime.tryParse(published) : null;
    if (id is! int || date == null) return null;

    String text(Object? value) => value is String ? value : '';
    final link = json['link'];
    return TransportNews(
      id: id,
      title: text(json['title']),
      summary: text(json['summary']),
      body: text(json['body']),
      link: link is String && link.isNotEmpty ? link : null,
      date: date.toLocal(),
    );
  }

  /// Same shape as the API, so the cache reuses [fromJson].
  Map<String, dynamic> toJson() => {
        'idMensaje': '$id',
        'titulo': title,
        'mensajeCorto': summary,
        'mensajeCompleto': body,
        'dataLink': link,
        'fecha': date.millisecondsSinceEpoch,
      };
}
