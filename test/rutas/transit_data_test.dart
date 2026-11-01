// The timetable format end to end: tool/rutas/build_horarios.py turns the
// tiny fixture of test/fixtures/rutas/ (every case of IM's CSV: hábil trips
// past midnight, Friday tails repeated on sábado, Saturday tails under
// domingo, Sunday-night `*` passes, a stop without coordinates, a variant
// without a line) into horarios_mini.bin, and TransitData reads back every
// field of it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/services/rutas/transit_data.dart';

const _fixtures = 'test/fixtures/rutas';

void main() {
  final bytes = File('$_fixtures/horarios_mini.bin').readAsBytesSync();

  test(
    'the committed binary is what the builder makes of the fixture',
    () {
      final out = Directory.systemTemp.createTempSync('rutas_');
      addTearDown(() => out.deleteSync(recursive: true));
      final result = Process.runSync('python3', [
        '-I',
        'tool/rutas/build_horarios.py',
        '--pasadas', '$_fixtures/pasadas_mini.csv', //
        '--destinos', '$_fixtures/destinos_mini.json',
        '--paradas', '$_fixtures/paradas_mini.json',
        '--out', '${out.path}/horarios.bin',
        '--built-at', '20261101',
        '--source-date', '20261031',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${out.path}/horarios.bin').readAsBytesSync(), bytes);
      // What the builder repaired or dropped, as it reports it
      expect(
        result.stderr,
        contains(
          'scheduled stops without coordinates, '
          'dropped: 1',
        ),
      );
      expect(result.stderr, contains('minute steps back, clamped: 1'));
      expect(
        result.stderr,
        contains(
          'trips of a variant without a line, '
          'dropped: 1',
        ),
      );
    },
    skip: _python3() ? false : 'python3 is not on PATH',
  );

  test('decodes every field', () {
    final data = TransitData.decode(bytes);

    expect(data.builtAt, DateTime(2026, 11, 1));
    expect(data.sourceDate, DateTime(2026, 10, 31));
    // The Sunday-night `*` trip leaves at 00:10: hábil trips before 00:11
    // do not run on Mondays
    expect(data.mondayCutoff, 11);

    // Only scheduled stops with coordinates, by STM number; 105 has no
    // point, 999 is in no timetable
    expect([for (final s in data.stops) s.id], [101, 102, 103, 104]);
    expect(
      [for (final s in data.stops) s.name],
      [
        'BV ESPAÑA y LIBERTAD',
        'SAN JOSE y ANDES',
        'RAMBLA', // no esquina
        'CIUDADELA y RINCON',
      ],
    );
    expect(
      [for (final s in data.stops) s.lat],
      [-34.9118, -34.907394, -34.907, -34.9067],
    );
    expect(
      [for (final s in data.stops) s.lon],
      [-56.153, -56.198255, -56.203, -56.2037],
    );
    expect(data.indexOfStop(103), 2);
    expect(data.indexOfStop(105), isNull);

    // Variant 40 has no line: dropped; line 999 runs no trip
    expect(data.lines, ['121', 'CA1', 'D10']);
    expect(data.variantLines, {10: 0, 20: 2, 30: 1});

    List<Object> route(TransitRoute r) => [
      r.variant,
      data.lines[r.line],
      r.stops.toList(),
      r.offsets.toList(),
      [for (final d in r.departures) d.toList()],
    ];
    expect(
      [for (final r in data.routes) route(r)],
      [
        // 08:00 and 09:00 share the profile; 10:00 lost stop 105; 17:00 is
        // slower
        [
          10,
          '121',
          [0, 1, 2],
          [0, 5, 12],
          [
            [480, 540],
            [],
            [],
          ],
        ],
        [
          10,
          '121',
          [0, 1, 2],
          [0, 6, 13],
          [
            [600],
            [],
            [],
          ],
        ],
        [
          10,
          '121',
          [0, 1, 2],
          [0, 8, 18],
          [
            [1020],
            [],
            [],
          ],
        ],
        // 12:00 → 11:59 is a glitch, kept at 12:00
        [
          30,
          'CA1',
          [1, 2],
          [0, 0],
          [
            [],
            [720],
            [],
          ],
        ],
        // 00:10 on Sunday, and on Monday as Sunday night service (`*`)
        [
          30,
          'CA1',
          [1, 2],
          [0, 10],
          [
            [],
            [],
            [10, 1450],
          ],
        ],
        // Past midnight: hábil wraps (its sábado S repeat is dropped),
        // sábado goes on in domingo's S rows, domingo in its `*` rows
        [
          20,
          'D10',
          [2, 3, 0],
          [0, 8, 15],
          [
            [1430],
            [],
            [],
          ],
        ],
        [
          20,
          'D10',
          [2, 3, 0],
          [0, 15, 30],
          [
            [],
            [1420],
            [],
          ],
        ],
        [
          20,
          'D10',
          [2, 3, 0],
          [0, 20, 33],
          [
            [],
            [],
            [1410],
          ],
        ],
      ],
    );
    // Routes of one pattern share its stop list
    expect(identical(data.routes[0].stops, data.routes[2].stops), isTrue);
    expect(data.lastMinute(DayType.habil), 1445);
    expect(data.lastMinute(DayType.sabado), 1450);
    expect(data.lastMinute(DayType.domingo), 1460);
  });

  test('stops near a point and footpaths use walking metres', () {
    final data = TransitData.decode(bytes);
    // 103 and 104: 72 m apart in a straight line, 94 m walking
    final near = data.stopsNear(-34.907, -56.203, 100);
    expect([for (final n in near) data.stops[n.stop].id], [103, 104]);
    expect(near.first.metres, 0);
    expect(
      near.last.metres,
      TransitData.walkMetres(-34.907, -56.203, -34.9067, -56.2037),
    );
    expect(near.last.metres, inInclusiveRange(93, 95));
    expect(data.stopsNear(-34.907, -56.203, 60), hasLength(1));
  });

  test('rejects what is not a timetable', () {
    expect(
      () => TransitData.decode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final wrongMagic = gzip.encode([...'MVDX'.codeUnits, 1, 0]);
    expect(
      () => TransitData.decode(Uint8List.fromList(wrongMagic)),
      throwsFormatException,
    );
    final raw = gzip.decode(bytes);
    final truncated = gzip.encode(raw.sublist(0, raw.length - 3));
    expect(
      () => TransitData.decode(Uint8List.fromList(truncated)),
      throwsFormatException,
    );
    final newer = [...raw]..[4] = 2;
    expect(
      () => TransitData.decode(Uint8List.fromList(gzip.encode(newer))),
      throwsFormatException,
    );
  });

  test('day types by weekday, no holidays', () {
    expect(DayType.of(DateTime(2026, 11, 2)), DayType.habil); // Monday
    expect(DayType.of(DateTime(2026, 11, 6)), DayType.habil); // Friday
    expect(DayType.of(DateTime(2026, 11, 7)), DayType.sabado);
    expect(DayType.of(DateTime(2026, 11, 8)), DayType.domingo);
  });
}

bool _python3() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
