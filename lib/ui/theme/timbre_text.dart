import 'package:flutter/painting.dart';

import 'timbre_tokens.dart';

/// Font families bundled in assets/fonts (SIL OFL 1.1, Latin subsets).
abstract final class TimbreFonts {
  /// Interface and reading.
  static const fira = 'FiraSans';

  /// Numbers, line badges, destinations and stop names.
  static const firaCondensed = 'FiraSansExtraCondensed';

  /// Dot-matrix LED face. Live bus data and the brand plate only, never
  /// below [dotoMinSize].
  static const doto = 'Doto';

  /// 19 px = 13 px letter height, the smallest size where the dots still
  /// read as letters.
  static const dotoMinSize = 19.0;
}

/// Text styles shared by the rows, badges and the LED display.
abstract final class TimbreText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Big white page title in the blue header ("Mis paradas").
  static const pageTitle = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 30,
    height: 1.1,
    color: TimbreColors.blanco,
  );

  /// Uppercase section label ("DESPUÉS", "LÍNEAS EN ESTA PARADA").
  static const sectionLabel = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 1.44,
    color: TimbreColors.grisTexto,
  );

  /// Stop name in cards and headers.
  static const stopName = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 21,
    height: 1.1,
    color: TimbreColors.tinta,
  );

  /// Line number inside the badge (filled = GPS, outlined = timetable).
  static const lineBadge = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w800,
    fontSize: 19,
    height: 1.2,
  );

  /// Destination in an arrival row.
  static const destination = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    height: 1.05,
    color: TimbreColors.tinta,
  );

  /// Live (GPS) minutes in white lists: dot-matrix digits in blue.
  static TextStyle liveMinutes([double size = 30]) => TextStyle(
        fontFamily: TimbreFonts.doto,
        fontWeight: FontWeight.w900,
        fontSize: size < TimbreFonts.dotoMinSize ? TimbreFonts.dotoMinSize : size,
        height: 1,
        color: TimbreColors.azul,
      );

  /// "min" next to [liveMinutes].
  static const minuteUnit = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1,
    color: TimbreColors.azul,
  );

  /// Timetable time ("20:17"): never a countdown, never dot-matrix.
  static const scheduleTime = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 1,
    color: TimbreColors.grisTexto,
    fontFeatures: _tabular,
  );

  /// Amber dot-matrix text for the LED display, at [size] (min 19 px).
  static TextStyle cartel(double size, {Color color = TimbreColors.ambar}) =>
      TextStyle(
        fontFamily: TimbreFonts.doto,
        fontWeight: FontWeight.w900,
        fontSize: size < TimbreFonts.dotoMinSize ? TimbreFonts.dotoMinSize : size,
        height: 1,
        color: color,
      );

  /// Small uppercase label inside the LED display ("PRÓXIMO").
  static const cartelLabel = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 1.44,
    color: TimbreColors.etiquetaCartel,
  );
}
