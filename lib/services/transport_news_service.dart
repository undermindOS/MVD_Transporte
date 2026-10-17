import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transport_news.dart';
import 'cache_service.dart';

/// One response of `GET /notificacion/mensajes`.
class NewsPage {
  /// Number of messages with an id above the requested `fromIdMessage`.
  final int count;
  final List<TransportNews> messages;

  const NewsPage(this.count, this.messages);
}

/// Official transport news — the open endpoint Cómo Ir reads
/// (`api.montevideo.gub.uy/notificacion/mensajes?idApp=1`), no credentials.
///
/// Fetched only while the app is open, at most every [minInterval]
/// (pull-to-refresh: every [forcedMinInterval]), and cached in Hive.
class TransportNewsService {
  static const _url = 'https://api.montevideo.gub.uy/notificacion/mensajes';
  // Cómo Ir's application id on the notification backend
  static const _idApp = 1;

  static const minInterval = Duration(minutes: 10);
  static const forcedMinInterval = Duration(seconds: 30);
  static const _maxCached = 30;
  static const _maxRequests = 8;

  static const _timeout = Duration(seconds: 10);
  static const _headers = {'Accept': 'application/json'};

  /// Cached news, newest first.
  static List<TransportNews> cached() {
    final raw = CacheService.get<String>(CacheService.keyNewsCache);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(TransportNews.fromJson).whereType<TransportNews>().toList();
    } catch (e) {
      debugPrint('⚠️ News cache error: $e');
      return [];
    }
  }

  /// Fetches new messages (if the last fetch is old enough) and returns the
  /// cached list merged with them, newest first.
  /// Returns null on network/server error.
  static Future<List<TransportNews>?> refresh({bool force = false}) async {
    final lastMs = CacheService.get<int>(CacheService.keyNewsFetchedAt);
    if (lastMs != null) {
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
      if (age < (force ? forcedMinInterval : minInterval)) return cached();
    }

    final from = CacheService.get<int>(CacheService.keyNewsFromId) ?? 0;
    final result = await fetchNewest(from, _fetchPage);
    if (result == null) return null;

    final news = merge(cached(), result.messages);
    await CacheService.set(CacheService.keyNewsCache,
        jsonEncode(news.map((n) => n.toJson()).toList()));
    await CacheService.set(CacheService.keyNewsFromId, result.from);
    await CacheService.set(
        CacheService.keyNewsFetchedAt, DateTime.now().millisecondsSinceEpoch);
    return news;
  }

  /// Highest idMensaje the user has seen (null = never opened the news).
  static int? get lastReadId =>
      CacheService.get<int>(CacheService.keyNewsLastReadId);

  static int unreadCount(List<TransportNews> news) {
    final read = lastReadId;
    return news.where((n) => read == null || n.id > read).length;
  }

  static Future<void> markRead(List<TransportNews> news) async {
    if (news.isEmpty) return;
    final newest = news.map((n) => n.id).reduce((a, b) => a > b ? a : b);
    final read = lastReadId;
    if (read == null || newest > read) {
      await CacheService.set(CacheService.keyNewsLastReadId, newest);
    }
  }

  static Future<NewsPage?> _fetchPage(int fromId) async {
    try {
      final uri = Uri.parse('$_url?idApp=$_idApp&fromIdMessage=$fromId');
      final response =
          await http.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('❌ News API ${response.statusCode}: ${response.body}');
        return null;
      }
      return parsePage(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('❌ News API error: $e');
      return null;
    }
  }

  /// Parses `{"count":144,"messages":[{"idMensaje":"28", …}, …]}`.
  @visibleForTesting
  static NewsPage? parsePage(dynamic data) {
    if (data is! Map || data['messages'] is! List) return null;
    final messages = (data['messages'] as List)
        .map(TransportNews.fromJson)
        .whereType<TransportNews>()
        .toList();
    final count = data['count'];
    return NewsPage(count is num ? count.toInt() : messages.length, messages);
  }

  /// Finds the newest messages starting from id [from].
  ///
  /// The endpoint returns at most 10 of the messages with an id above
  /// `fromIdMessage`, in storage order (e.g. 43…50, 134, 51), plus `count`
  /// of all of them. Paging by the highest id received — what Cómo Ir does —
  /// therefore skips messages. Instead `from` moves up until everything
  /// above it fits in one page. Ids are near-sequential (the i-th id above
  /// `from` is at least `from + i`), so the jump never overshoots the
  /// newest full page.
  @visibleForTesting
  static Future<({List<TransportNews> messages, int from})?> fetchNewest(
      int from, Future<NewsPage?> Function(int from) getPage) async {
    for (var i = 0; i < _maxRequests; i++) {
      final page = await getPage(from);
      if (page == null) return null;
      if (page.count <= page.messages.length || i == _maxRequests - 1) {
        return (messages: page.messages, from: from);
      }
      from += page.count - page.messages.length;
    }
    return null;
  }

  /// Union by id, newest first, capped at [_maxCached].
  @visibleForTesting
  static List<TransportNews> merge(
      List<TransportNews> cached, List<TransportNews> fresh) {
    final byId = {for (final n in cached) n.id: n};
    for (final n in fresh) {
      byId[n.id] = n;
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    return list.take(_maxCached).toList();
  }
}
