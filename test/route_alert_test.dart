import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:stm_app/models/bus_arrival.dart';
import 'package:stm_app/models/route_alert.dart';

void main() {
  RouteAlert route(List<String> lines,
          {List<String> destinations = const [],
          List<int> variants = const []}) =>
      RouteAlert(
        id: 1,
        originStopId: 3140,
        originName: 'Origen',
        destinationName: 'Centro',
        preferredLines: lines,
        preferredDestinations: destinations,
        preferredVariantIds: variants,
      );

  BusArrival bus(String line, String destination, {int? variantId}) =>
      BusArrival(
        tripId: 'bus-50-139',
        variantId: variantId,
        line: line,
        destination: destination,
        state: ArrivalState.live,
        etaMinutes: 9,
        expectedAt: DateTime.utc(2026, 10, 19, 23, 1),
        clockTime: '20:01',
      );

  test('empty preferred lines accept every line', () {
    expect(route([]).acceptsLine('145'), isTrue);
  });

  test('line match ignores case', () {
    expect(route(['64d']).acceptsLine('64D'), isTrue);
    expect(route(['G8']).acceptsLine('g8'), isTrue);
  });

  test('other lines are rejected', () {
    expect(route(['183']).acceptsLine('185'), isFalse);
  });

  group('direction', () {
    test('a picked variant matches whatever its label reads', () {
      // Picked from the IM label "POCITOS"; transporteRest says otherwise
      final r = route(['116'], destinations: ['POCITOS'], variants: [630]);
      expect(r.accepts(bus('116', 'POCITOS (POR BV ESPAÑA)', variantId: 630)),
          isTrue);
      expect(r.accepts(bus('116', 'CIUDAD VIEJA', variantId: 631)), isFalse);
      // The line still has to match
      expect(r.accepts(bus('117', 'POCITOS', variantId: 630)), isFalse);
    });

    test('routes saved with labels only still match by label', () {
      final r = route(['116'], destinations: ['POCITOS']);
      expect(r.accepts(bus('116', 'POCITOS', variantId: 630)), isTrue);
      expect(r.accepts(bus('116', 'POCITOS')), isTrue);
      expect(r.accepts(bus('116', 'CIUDAD VIEJA', variantId: 631)), isFalse);
    });

    test('no direction picked accepts every direction', () {
      expect(route(['116']).accepts(bus('116', 'CIUDAD VIEJA')), isTrue);
    });
  });

  group('Hive data saved before the variant filter', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mvd_route_alert_test');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('reads with no variants and keeps its labels', () async {
      Hive.registerAdapter(_RouteAlertAdapterV10(), override: true);
      final old = await Hive.openBox<RouteAlert>('routes');
      await old.put(1, route(['116'], destinations: ['POCITOS']));
      await Hive.close();

      Hive.registerAdapter(RouteAlertAdapter(), override: true);
      final box = await Hive.openBox<RouteAlert>('routes');
      final saved = box.get(1)!;
      expect(saved.preferredDestinations, ['POCITOS']);
      expect(saved.preferredVariantIds, isEmpty);
      expect(saved.accepts(bus('116', 'POCITOS', variantId: 630)), isTrue);

      // The new field survives a round trip
      saved.preferredVariantIds = [630, 7884];
      await saved.save();
      await Hive.close();
      final again = (await Hive.openBox<RouteAlert>('routes')).get(1)!;
      expect(again.preferredVariantIds, [630, 7884]);
    });
  });
}

/// The adapter as generated before field 11 (fields 0–10).
class _RouteAlertAdapterV10 extends TypeAdapter<RouteAlert> {
  @override
  final int typeId = 1;

  @override
  RouteAlert read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, RouteAlert obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originStopId)
      ..writeByte(2)
      ..write(obj.originName)
      ..writeByte(3)
      ..write(obj.destinationName)
      ..writeByte(4)
      ..write(obj.preferredLines)
      ..writeByte(5)
      ..write(obj.enabled)
      ..writeByte(6)
      ..write(obj.alertMinutes)
      ..writeByte(7)
      ..write(obj.alertDays)
      ..writeByte(8)
      ..write(obj.alertFromMinute)
      ..writeByte(9)
      ..write(obj.alertToMinute)
      ..writeByte(10)
      ..write(obj.preferredDestinations);
  }
}
