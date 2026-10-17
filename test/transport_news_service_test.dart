import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/models/transport_news.dart';
import 'package:stm_app/services/cache_service.dart';
import 'package:stm_app/services/transport_news_service.dart';

// Live responses of /notificacion/mensajes?idApp=1&fromIdMessage=N,
// captured 2026-10-17 (test/fixtures/mensajes_fromN.json).
NewsPage? _page(int from) {
  final file = File('test/fixtures/mensajes_from$from.json');
  if (!file.existsSync()) return null;
  return TransportNewsService.parsePage(jsonDecode(file.readAsStringSync()));
}

TransportNews _news(int id, DateTime date) => TransportNews(
    id: id, title: 't$id', summary: '', body: '', date: date);

void main() {
  group('parsePage', () {
    test('parses the oldest page', () {
      final page = _page(0)!;
      expect(page.count, 144);
      expect(page.messages, hasLength(10));

      final first = page.messages.first;
      expect(first.id, 28);
      expect(first.title, 'Novedades');
      expect(first.link, 'https://montevideo.gub.uy/node/49764');
      expect(first.body, startsWith('<h1>Novedades</h1>'));
      expect(first.date, DateTime.fromMillisecondsSinceEpoch(1581096904776));
    });

    test('pages are in storage order, not by id', () {
      // Why paging by the highest id received (as Cómo Ir does) loses
      // messages: on 2026-10-17 the page above 148 held 149, 171, 153…160,
      // so the next request started at 171 and 161…170 were never shown.
      final ids = _page(166)!.messages.map((m) => m.id).toList();
      expect(ids.take(3), [171, 168, 167]);
    });

    test('rejects malformed payloads', () {
      expect(TransportNewsService.parsePage([]), isNull);
      expect(TransportNewsService.parsePage({'count': 1}), isNull);
      expect(
          TransportNewsService.parsePage({
            'count': 2,
            'messages': [
              {'titulo': 'sin id', 'fecha': 1},
              'garbage',
            ],
          })!
              .messages,
          isEmpty);
    });
  });

  group('TransportNews.fromJson', () {
    test('accepts a string date and drops empty links', () {
      final n = TransportNews.fromJson({
        'idMensaje': '7',
        'titulo': ' Desvíos ',
        'fecha': '1790948233228',
        'dataLink': '',
      })!;
      expect(n.id, 7);
      expect(n.title, 'Desvíos');
      expect(n.link, isNull);
      expect(n.date.millisecondsSinceEpoch, 1790948233228);
    });

    test('round-trips through the cache format', () {
      final n = _page(170)!.messages.first;
      final copy = TransportNews.fromJson(n.toJson())!;
      expect(copy.id, n.id);
      expect(copy.body, n.body);
      expect(copy.link, n.link);
      expect(copy.date, n.date);
    });
  });

  group('fetchNewest', () {
    test('climbs to the newest full page in 4 requests', () async {
      final requested = <int>[];
      final result = await TransportNewsService.fetchNewest(0, (from) async {
        requested.add(from);
        return _page(from);
      });

      expect(requested, [0, 134, 166, 170]);
      expect(result!.from, 170);
      expect(result.messages.map((m) => m.id).toList()..sort(),
          [171, 172, 173, 174, 175, 176, 177, 178, 179, 180]);
    });

    test('one request when nothing new is above the saved start', () async {
      final requested = <int>[];
      final result = await TransportNewsService.fetchNewest(170, (from) async {
        requested.add(from);
        return _page(from);
      });
      expect(requested, [170]);
      expect(result!.messages, hasLength(10));
    });

    test('null on network error', () async {
      expect(await TransportNewsService.fetchNewest(0, (_) async => null),
          isNull);
    });
  });

  group('merge', () {
    test('dedupes by id, newest first, capped', () {
      final cached = [
        for (var i = 1; i <= 30; i++) _news(i, DateTime(2026, 1, i)),
      ];
      final fresh = [
        _news(31, DateTime(2026, 3, 1)),
        _news(30, DateTime(2026, 1, 30)),
      ];
      final merged = TransportNewsService.merge(cached, fresh);
      expect(merged, hasLength(30));
      expect(merged.first.id, 31);
      expect(merged.where((n) => n.id == 30), hasLength(1));
      expect(merged.last.id, 2); // the oldest one dropped
    });
  });

  group('with storage', () {
    late Directory hiveDir;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('mvd_news_test');
      await CacheService.init(path: hiveDir.path);
    });

    tearDownAll(() async {
      await hiveDir.delete(recursive: true);
    });

    test('unread count follows the last read id', () async {
      final news = _page(170)!.messages;
      expect(TransportNewsService.lastReadId, isNull);
      expect(TransportNewsService.unreadCount(news), 10);

      await TransportNewsService.markRead(news);
      expect(TransportNewsService.lastReadId, 180);
      expect(TransportNewsService.unreadCount(news), 0);

      final newer = [...news, _news(181, DateTime(2026, 10, 17))];
      expect(TransportNewsService.unreadCount(newer), 1);
    });

    test('a recent fetch is served from the cache, without network',
        () async {
      final news = _page(170)!.messages;
      await CacheService.set(CacheService.keyNewsCache,
          jsonEncode(news.map((n) => n.toJson()).toList()));
      await CacheService.set(CacheService.keyNewsFetchedAt,
          DateTime.now().millisecondsSinceEpoch);

      final fetchedAt = CacheService.get<int>(CacheService.keyNewsFetchedAt);

      final result = await TransportNewsService.refresh();
      expect(result!.map((n) => n.id), contains(180));
      expect(await TransportNewsService.refresh(force: true), isNotNull);
      // A real fetch would have moved the timestamp
      expect(
          CacheService.get<int>(CacheService.keyNewsFetchedAt), fetchedAt);
    });
  });
}
