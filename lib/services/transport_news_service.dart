import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/transport_news.dart';
import 'api/direct/news_adapter.dart';
import 'cache_service.dart';
import 'mvd_api_service.dart';

/// One response of `GET /notificacion/mensajes`.
class NewsPage implements NewsPaging {
  /// Number of messages with an id above the requested `fromIdMessage`.
  @override
  final int count;
  final List<TransportNews> messages;

  const NewsPage(this.count, this.messages);

  @override
  int get size => messages.length;
}

/// Official transport news — through the proxy (`/v1/news`) or, without
/// it, the open endpoint Cómo Ir reads
/// (`api.montevideo.gub.uy/notificacion/mensajes?idApp=1`), no credentials.
///
/// Fetched only while the app is open, at most every [minInterval]
/// (pull-to-refresh: every [forcedMinInterval]), and cached in Hive: each
/// fetch is merged into the cached list.
class TransportNewsService {
  static const minInterval = Duration(minutes: 10);
  static const forcedMinInterval = Duration(seconds: 30);
  static const _maxCached = 30;

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

    if (MvdApiService.usesProxy) {
      // The proxy pages from id 0 itself: no paging start is kept here
      final fresh = (await MvdApiService.getNews()).valueOrNull?.news;
      if (fresh == null) return null;
      final news = merge(cached(), fresh);
      await _saveCache(news);
      await _saveFetchedAt();
      return news;
    }

    final from = CacheService.get<int>(CacheService.keyNewsFromId) ?? 0;
    final result = await fetchNewest(from, _fetchPage);
    if (result == null) return null;

    final news = merge(cached(), result.messages);
    await _saveCache(news);
    await CacheService.set(CacheService.keyNewsFromId, result.from);
    await _saveFetchedAt();
    return news;
  }

  static Future<void> _saveCache(List<TransportNews> news) =>
      CacheService.set(CacheService.keyNewsCache,
          jsonEncode(news.map((n) => n.toJson()).toList()));

  static Future<void> _saveFetchedAt() => CacheService.set(
      CacheService.keyNewsFetchedAt, DateTime.now().millisecondsSinceEpoch);

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
      final uri = Uri.parse(NewsAdapter.pageUrl(fromId));
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

  /// Parses `{"count":144,"messages":[{"idMensaje":"28", …}, …]}` through
  /// the direct-mode adapter and [TransportNews.fromV1].
  @visibleForTesting
  static NewsPage? parsePage(dynamic data) {
    final page = NewsAdapter.pageToV1(data);
    if (page == null) return null;
    return NewsPage(
        page.count, page.news.map(TransportNews.fromV1).nonNulls.toList());
  }

  /// Finds the newest messages starting from id [from]: see
  /// [NewsAdapter.fetchNewest].
  @visibleForTesting
  static Future<({List<TransportNews> messages, int from})?> fetchNewest(
      int from, Future<NewsPage?> Function(int from) getPage) async {
    final result = await NewsAdapter.fetchNewest(from, getPage);
    return result == null
        ? null
        : (messages: result.page.messages, from: result.from);
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
