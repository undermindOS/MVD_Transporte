import 'package:flutter/painting.dart';

/// Timbre MVD design tokens: the single source for colors, radii and
/// spacing. Mirrors the "Marca" and "El cartel en la interfaz" boards.
///
/// White and flag blue are the app; the LED amber only appears where the
/// bus "speaks" (live arrivals, the brand plate), and only on [tinta] or
/// [azul], never on white.
abstract final class TimbreColors {
  /// Azul MVD, the flag blue. White text on it: 9.8:1.
  static const azul = Color(0xFF0038A8);

  /// Pressed / dark variant of [azul].
  static const azulNoche = Color(0xFF00266F);

  /// Ink: main text (17:1 on white) and the LED display background.
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

  /// Small labels inside the LED display: 7.9:1 on [tinta].
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
