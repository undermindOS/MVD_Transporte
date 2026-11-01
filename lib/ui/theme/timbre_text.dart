import 'package:flutter/widgets.dart';

import 'timbre_tokens.dart';

/// Font families bundled in assets/fonts (SIL OFL 1.1, Latin subsets).
abstract final class TimbreFonts {
  /// Interface and reading.
  static const fira = 'FiraSans';

  /// Numbers, line badges, destinations and stop names.
  static const firaCondensed = 'FiraSansExtraCondensed';

  /// Dot-matrix LED face: page titles, signs, the brand plate and live bus
  /// data. Never below [dotoMinSize]; timetables never use it.
  static const doto = 'Doto';

  /// 19 px = 13 px letter height, the smallest size where the dots still
  /// read as letters.
  static const dotoMinSize = 19.0;
}

/// Text styles shared by the rows, badges and the LED display.
abstract final class TimbreText {
  /// Text scale from which layouts stack (the time under the destination)
  /// and tab bars scroll: 150 % and up, the largest Android sizes and the
  /// iOS accessibility sizes.
  static const largeFrom = 1.5;

  /// Whether the user reads with [largeFrom] or bigger text.
  static bool isLarge(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(17) >= 17 * largeFrom;

  static const _tabular = [FontFeature.tabularFigures()];

  /// Page title on the header board, lit like a destination sign
  /// ("MIS PARADAS"): uppercase dot-matrix amber.
  static const pageTitle = TextStyle(
    fontFamily: TimbreFonts.doto,
    fontWeight: FontWeight.w900,
    fontSize: 28,
    height: 1.1,
    letterSpacing: 1,
    color: TimbreColors.ambar,
  );

  /// Uppercase section label ("DESPUÉS", "LÍNEAS EN ESTA PARADA").
  static const sectionLabel = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 1.44,
    color: TimbreColors.etiquetaCartel,
  );

  /// Stop name in cards and headers.
  static const stopName = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.1,
    color: TimbreColors.papel,
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
    color: TimbreColors.papel,
  );

  /// Live (GPS) minutes: lit dot-matrix digits.
  static TextStyle liveMinutes([double size = 30]) => TextStyle(
        fontFamily: TimbreFonts.doto,
        fontWeight: FontWeight.w900,
        fontSize: size < TimbreFonts.dotoMinSize ? TimbreFonts.dotoMinSize : size,
        height: 1,
        color: TimbreColors.ambar,
      );

  /// "min" next to [liveMinutes].
  static const minuteUnit = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1,
    color: TimbreColors.ambarTenue,
  );

  /// Timetable time ("20:17"): never a countdown, never dot-matrix.
  static const scheduleTime = TextStyle(
    fontFamily: TimbreFonts.firaCondensed,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 1,
    color: TimbreColors.etiquetaCartel,
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

  // --- Reading: Fira Sans ---

  /// Dialog title ("Agregar parada").
  static const dialogTitle = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.2,
    color: TimbreColors.papel,
  );

  /// The main button ("Avisarme cuando llegue"): ink on amber, the color
  /// comes from the button.
  static const buttonLarge = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.2,
  );

  /// Text of dialogs, snack bars and the lock screen.
  static const body = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.2,
    color: TimbreColors.papel,
  );

  /// Outlined and text buttons ("Ver en Cómo Ir"): amber, from the button.
  static const button = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    height: 1.2,
  );

  /// Line under the page title ("Sitios oficiales, en tu navegador").
  static const subtitle = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.2,
    color: TimbreColors.etiquetaCartel,
  );

  /// Sub-tabs ("Paradas"): lit when selected, the color comes from the
  /// tab bar.
  static const tabLabel = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 13,
    height: 1.2,
  );

  /// Line under a stop in lists ("#5109 · 48 m · 124, 125"); notes take
  /// `height: 1.4`.
  static const caption = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    height: 1.2,
    color: TimbreColors.etiquetaCartel,
  );

  /// Bottom navigation ("Mis paradas"): lit when selected, the color comes
  /// from the navigation bar.
  static const navLabel = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
  );
}
