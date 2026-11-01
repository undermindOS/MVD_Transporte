// docs/design/tokens.json mirrors the Timbre tokens
// (lib/ui/theme/timbre_tokens.dart) and the TimbreText styles
// (lib/ui/theme/timbre_text.dart) for the design docs. The code is the
// source of truth: this test fails when a value in the JSON differs from
// its Dart constant, or when a token exists on one side only. Read by
// relative path: run `flutter test` from the repo root.
//
// A new token goes in three places in the same change: the Dart class,
// the maps below and tokens.json. The source scan catches a Dart token
// that is missing from the maps.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stm_app/ui/theme/timbre_text.dart';
import 'package:stm_app/ui/theme/timbre_tokens.dart';

const _tokensPath = 'docs/design/tokens.json';
const _tokensDart = 'lib/ui/theme/timbre_tokens.dart';
const _textDart = 'lib/ui/theme/timbre_text.dart';

const _colors = <String, Color>{
  'noche': TimbreColors.noche,
  'tinta': TimbreColors.tinta,
  'tintaAlta': TimbreColors.tintaAlta,
  'lineaNoche': TimbreColors.lineaNoche,
  'papel': TimbreColors.papel,
  'tenue': TimbreColors.tenue,
  'ambarClaro': TimbreColors.ambarClaro,
  'rojoLed': TimbreColors.rojoLed,
  'avisoNoche': TimbreColors.avisoNoche,
  'etiquetaCartel': TimbreColors.etiquetaCartel,
  'ambar': TimbreColors.ambar,
  'ambarTenue': TimbreColors.ambarTenue,
};

const _radii = <String, double>{
  'chip': TimbreRadii.chip,
  'badge': TimbreRadii.badge,
  'control': TimbreRadii.control,
  'button': TimbreRadii.button,
  'card': TimbreRadii.card,
  'sheet': TimbreRadii.sheet,
};

const _space = <String, double>{
  'xs': TimbreSpace.xs,
  's': TimbreSpace.s,
  'm': TimbreSpace.m,
  'l': TimbreSpace.l,
  'xl': TimbreSpace.xl,
  'touch': TimbreSpace.touch,
};

const _opacity = <String, double>{
  'ledUnlit': TimbreOpacity.ledUnlit,
  'pressSplash': TimbreOpacity.pressSplash,
  'pressHighlight': TimbreOpacity.pressHighlight,
};

const _iconSize = <String, double>{
  'mark': TimbreIconSize.mark,
  'row': TimbreIconSize.row,
  'rowLarge': TimbreIconSize.rowLarge,
  'tile': TimbreIconSize.tile,
};

const _shadows = <String, BoxShadow>{
  'ledGlow': TimbreShadow.ledGlow,
};

const _families = <String, String>{
  'fira': TimbreFonts.fira,
  'firaCondensed': TimbreFonts.firaCondensed,
  'doto': TimbreFonts.doto,
};

/// The constant styles. The two style functions, `liveMinutes` and
/// `cartel`, are checked on their own.
const _styles = <String, TextStyle>{
  'pageTitle': TimbreText.pageTitle,
  'sectionLabel': TimbreText.sectionLabel,
  'stopName': TimbreText.stopName,
  'lineBadge': TimbreText.lineBadge,
  'destination': TimbreText.destination,
  'minuteUnit': TimbreText.minuteUnit,
  'scheduleTime': TimbreText.scheduleTime,
  'cartelLabel': TimbreText.cartelLabel,
  'dialogTitle': TimbreText.dialogTitle,
  'buttonLarge': TimbreText.buttonLarge,
  'body': TimbreText.body,
  'button': TimbreText.button,
  'subtitle': TimbreText.subtitle,
  'tabLabel': TimbreText.tabLabel,
  'caption': TimbreText.caption,
  'navLabel': TimbreText.navLabel,
};

const _styleFunctions = {'liveMinutes', 'cartel'};

Map<String, Object?> _tokens() =>
    jsonDecode(File(_tokensPath).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _group(Map<String, Object?> json, String name) =>
    json[name] as Map<String, Object?>;

/// "#RRGGBB", or "#AARRGGBB" when the color is not opaque.
String _hex(Color c) {
  final argb = c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return argb.startsWith('FF') ? '#${argb.substring(2)}' : '#$argb';
}

double? _num(Object? v) => (v as num?)?.toDouble();

/// The public `static const` members of each class in a Dart file, and its
/// public static methods that return a [TextStyle].
Map<String, Set<String>> _declared(String path) {
  final classRe = RegExp(r'^(?:abstract\s+)?(?:final\s+)?class\s+(\w+)');
  final constRe = RegExp(r'^\s+static\s+const\s+([a-zA-Z]\w*)\s*=');
  final styleFnRe = RegExp(r'^\s+static\s+TextStyle\s+([a-zA-Z]\w*)\s*\(');
  final out = <String, Set<String>>{};
  String? current;
  for (final line in File(path).readAsLinesSync()) {
    final c = classRe.firstMatch(line);
    if (c != null) {
      current = c.group(1);
      out[current!] = {};
      continue;
    }
    final m = constRe.firstMatch(line) ?? styleFnRe.firstMatch(line);
    if (m != null && current != null) out[current]!.add(m.group(1)!);
  }
  return out;
}

void main() {
  final json = _tokens();
  final tokensDart = _declared(_tokensDart);
  final textDart = _declared(_textDart);

  void sameNames(String dartClass, Set<String> declared, Iterable<String> map,
      Map<String, Object?> group) {
    expect(map.toSet(), declared,
        reason: '$dartClass in the code vs the maps of this test');
    expect(group.keys.toSet(), declared,
        reason: '$dartClass in the code vs $_tokensPath');
  }

  void documented(Map<String, Object?> group) {
    for (final e in group.entries) {
      final usage = (e.value as Map<String, Object?>)['usage'];
      expect(usage, isA<String>(), reason: '${e.key} has no usage');
      expect((usage as String).trim(), isNotEmpty, reason: e.key);
    }
  }

  test('every token class of the code is in tokens.json', () {
    expect(tokensDart.keys.toSet(), {
      'TimbreColors',
      'TimbreRadii',
      'TimbreSpace',
      'TimbreOpacity',
      'TimbreIconSize',
      'TimbreShadow',
    });
    expect(textDart.keys.toSet(), {'TimbreFonts', 'TimbreText'});
    expect(json.keys.toSet(), {
      'name',
      'about',
      'dart',
      'color',
      'radius',
      'space',
      'opacity',
      'iconSize',
      'shadow',
      'font',
      'text',
    });
  });

  test('colors', () {
    final group = _group(json, 'color');
    sameNames('TimbreColors', tokensDart['TimbreColors']!, _colors.keys, group);
    documented(group);
    for (final e in _colors.entries) {
      final token = group[e.key] as Map<String, Object?>;
      expect(token['value'], _hex(e.value), reason: e.key);
      expect(token['dart'], 'TimbreColors.${e.key}');
    }
  });

  group('numbers', () {
    void numbers(String jsonName, String dartClass, Map<String, double> map) {
      test(jsonName, () {
        final group = _group(json, jsonName);
        sameNames(dartClass, tokensDart[dartClass]!, map.keys, group);
        documented(group);
        for (final e in map.entries) {
          final token = group[e.key] as Map<String, Object?>;
          expect(_num(token['value']), e.value, reason: e.key);
          expect(token['dart'], '$dartClass.${e.key}');
        }
      });
    }

    numbers('radius', 'TimbreRadii', _radii);
    numbers('space', 'TimbreSpace', _space);
    numbers('opacity', 'TimbreOpacity', _opacity);
    numbers('iconSize', 'TimbreIconSize', _iconSize);
  });

  test('shadow', () {
    final group = _group(json, 'shadow');
    sameNames('TimbreShadow', tokensDart['TimbreShadow']!, _shadows.keys, group);
    documented(group);
    for (final e in _shadows.entries) {
      final token = group[e.key] as Map<String, Object?>;
      final s = e.value;
      expect(token['dart'], 'TimbreShadow.${e.key}');
      expect(token['color'], _hex(s.color), reason: e.key);
      expect(_num(token['offsetX']), s.offset.dx, reason: e.key);
      expect(_num(token['offsetY']), s.offset.dy, reason: e.key);
      expect(_num(token['blurRadius']), s.blurRadius, reason: e.key);
      expect(_num(token['spreadRadius']), s.spreadRadius, reason: e.key);
      expect(s.blurStyle, BlurStyle.normal, reason: e.key);
    }
  });

  test('fonts', () {
    final font = _group(json, 'font');
    expect(font.keys.toSet(), {'families', 'dotoMinSize', 'largeFrom'});
    final families = _group(font, 'families');
    expect(textDart['TimbreFonts'], {..._families.keys, 'dotoMinSize'});
    expect(families.keys.toSet(), _families.keys.toSet());
    documented(families);
    for (final e in _families.entries) {
      final token = families[e.key] as Map<String, Object?>;
      expect(token['value'], e.value, reason: e.key);
      expect(token['dart'], 'TimbreFonts.${e.key}');
    }
    final min = font['dotoMinSize'] as Map<String, Object?>;
    expect(_num(min['value']), TimbreFonts.dotoMinSize);
    expect(min['dart'], 'TimbreFonts.dotoMinSize');
    final large = font['largeFrom'] as Map<String, Object?>;
    expect(_num(large['value']), TimbreText.largeFrom);
    expect(large['dart'], 'TimbreText.largeFrom');
    documented({'dotoMinSize': min, 'largeFrom': large});
  });

  group('text styles', () {
    final group = _group(json, 'text');
    final families = _group(_group(json, 'font'), 'families');

    /// The family, weight, height, letter spacing, color and figures of
    /// [style] are the ones [token] says.
    void sameStyle(String name, TextStyle style, Map<String, Object?> token) {
      final family = families[token['family']] as Map<String, Object?>?;
      expect(family, isNotNull, reason: '$name: unknown family');
      expect(style.fontFamily, family!['value'], reason: name);
      expect(style.fontWeight?.value, token['weight'], reason: name);
      expect(style.height, _num(token['height']), reason: name);
      expect(style.letterSpacing, _num(token['letterSpacing']),
          reason: name);
      final color = token['color'] as String?;
      expect(style.color, color == null ? isNull : _colors[color],
          reason: '$name: color');
      expect(style.fontFeatures ?? const <FontFeature>[],
          token['tabularFigures'] == true
              ? const [FontFeature.tabularFigures()]
              : isEmpty,
          reason: '$name: figures');
    }

    test('the same styles on both sides', () {
      expect(textDart['TimbreText'],
          {..._styles.keys, ..._styleFunctions, 'largeFrom'});
      expect(group.keys.toSet(), {..._styles.keys, ..._styleFunctions});
      documented(group);
      for (final e in group.entries) {
        expect((e.value as Map<String, Object?>)['dart'],
            'TimbreText.${e.key}');
      }
    });

    test('constant styles', () {
      for (final e in _styles.entries) {
        final token = group[e.key] as Map<String, Object?>;
        expect(e.value.fontSize, _num(token['size']), reason: e.key);
        sameStyle(e.key, e.value, token);
      }
    });

    test('liveMinutes: 30 by default, never under the Doto minimum', () {
      final token = group['liveMinutes'] as Map<String, Object?>;
      final style = TimbreText.liveMinutes();
      expect(style.fontSize, _num(token['size']));
      expect(_num(token['minSize']), TimbreFonts.dotoMinSize);
      expect(TimbreText.liveMinutes(10).fontSize, TimbreFonts.dotoMinSize);
      expect(TimbreText.liveMinutes(26).fontSize, 26);
      sameStyle('liveMinutes', style, token);
    });

    test('cartel: the size asked for, never under the Doto minimum', () {
      final token = group['cartel'] as Map<String, Object?>;
      expect(token['size'], isNull);
      expect(_num(token['minSize']), TimbreFonts.dotoMinSize);
      expect(TimbreText.cartel(10).fontSize, TimbreFonts.dotoMinSize);
      expect(TimbreText.cartel(22).fontSize, 22);
      sameStyle('cartel', TimbreText.cartel(22), token);
      expect(
          TimbreText.cartel(22, color: TimbreColors.tinta).color,
          TimbreColors.tinta);
    });
  });
}
