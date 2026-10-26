import 'package:flutter/painting.dart';

/// Timbre MVD design tokens: the single source for colors, radii and
/// spacing.
///
/// The app is a night LED board: [noche] behind everything, [tinta] panels,
/// text in [papel], the amber LEDs lit where something matters. Dot-matrix
/// digits are reserved for live (GPS) data; amber stays on the dark, never
/// on white. The flag blue and white remain for the launcher icon and the
/// splash.
abstract final class TimbreColors {
  // --- Night board (the app) ---

  /// Screen background: the board.
  static const noche = Color(0xFF070F22);

  /// Raised panels: pressed rows, sheets, inputs, the selected tab.
  static const tintaAlta = Color(0xFF13284F);

  /// Borders and dividers on the board.
  static const lineaNoche = Color(0xFF22396A);

  /// Main text on the board: 16:1 on [noche], 15:1 on [tinta].
  static const papel = Color(0xFFF1ECE2);

  /// Tertiary text and dim icons: 5.3:1 on [tinta]. Not on [tintaAlta].
  static const tenue = Color(0xFF7F8FB3);

  /// Highlight of a lit row (scan line, focus): pale amber.
  static const ambarClaro = Color(0xFFFFE2A3);

  /// Errors and deletions, a red LED: 6.2:1 on [tinta].
  static const rojoLed = Color(0xFFFF6B57);

  /// Background of warnings on the board (amber text on it: 8.7:1).
  static const avisoNoche = Color(0xFF2A2210);

  // --- Brand blue and white (launcher icon, splash, notifications) ---

  /// Azul MVD, the flag blue. White text on it: 9.8:1.
  static const azul = Color(0xFF0038A8);

  /// Pressed / dark variant of [azul].
  static const azulNoche = Color(0xFF00266F);

  /// Ink: the panels and the LED plate. Was the main text on white.
  static const tinta = Color(0xFF0A1A3A);

  /// Secondary text, 6.9:1 on white.
  static const grisTexto = Color(0xFF4B5A78);

  /// App background behind cards.
  static const niebla = Color(0xFFEEF2F9);

  /// Selection, active indicators, line chips.
  static const celeste = Color(0xFFDDE6F6);

  /// Dividers and control borders.
  static const linea = Color(0xFFCBD5E6);

  /// Card borders, lighter than [linea].
  static const borde = Color(0xFFDCE3EF);

  /// Row separators inside cards.
  static const separador = Color(0xFFE4E9F3);

  /// Non-text UI on white (switch track off, chevrons): 3.7:1.
  static const anillo = Color(0xFF7385A8);

  /// Secondary text on [azul] and [tinta].
  static const sobreAzul = Color(0xFFCCD7EE);

  /// Body text on [azul].
  static const sobreAzulSuave = Color(0xFFD9E1F2);

  /// Secondary text and labels on the board: 7.9:1 on [tinta], 8.6:1 on
  /// [noche].
  static const etiquetaCartel = Color(0xFF9FB0D0);

  /// LED amber: 9.5:1 on [tinta], 5.5:1 on [azul], 1.8:1 on white (never).
  static const ambar = Color(0xFFFFB21E);

  /// Dimmed LED amber for secondary text on the plate: 5.8:1 on [tinta].
  static const ambarTenue = Color(0xFFC68B1E);

  /// Warning text on [avisoFondo]: 6.6:1.
  static const aviso = Color(0xFF7A4B00);
  static const avisoFondo = Color(0xFFFFF1D6);

  static const blanco = Color(0xFFFFFFFF);
}

abstract final class TimbreRadii {
  static const chip = 6.0;
  static const badge = 8.0;
  static const control = 12.0;
  static const button = 14.0;
  static const card = 16.0;
  static const sheet = 24.0;
}

abstract final class TimbreSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;

  /// Minimum touch target.
  static const touch = 44.0;
}
