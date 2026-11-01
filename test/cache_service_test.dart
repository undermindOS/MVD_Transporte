import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:stm_app/services/cache_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mvd_cache_test');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('the catalog an older version kept in the settings is dropped',
      () async {
    Hive.init(dir.path);
    final old = await Hive.openBox('settings');
    await old.putAll({
      CacheService.keyStopCatalog: '{"stops":[{"id":574,"name":"x"}]}',
      CacheService.keyStopCatalogFetchedAt: 1,
      CacheService.keyNewsLastReadId: 180,
    });
    await Hive.close();

    await CacheService.init(path: dir.path);
    expect(CacheService.get<String>(CacheService.keyStopCatalog), isNull);
    expect(CacheService.get<int>(CacheService.keyStopCatalogFetchedAt), isNull);
    // Downloaded again into its own box; other settings stay
    expect(CacheService.catalogFetchedAtMs, isNull);
    expect(await CacheService.catalogBody(), isNull);
    expect(CacheService.get<int>(CacheService.keyNewsLastReadId), 180);
  });

  test('the catalog copy survives a restart and is removed by either key',
      () async {
    await CacheService.init(path: dir.path);
    await CacheService.saveCatalog('{"stops":[]}', 42);
    await Hive.close();

    await CacheService.init(path: dir.path);
    expect(CacheService.catalogFetchedAtMs, 42);
    expect(await CacheService.catalogBody(), '{"stops":[]}');

    await CacheService.remove(CacheService.keyStopCatalog);
    expect(CacheService.catalogFetchedAtMs, isNull);
    await Hive.close();
    await CacheService.init(path: dir.path);
    expect(CacheService.catalogFetchedAtMs, isNull);
    expect(await CacheService.catalogBody(), isNull);
  });
}
