import 'package:flutter/painting.dart';

/// Timbre MVD design tokens: the single source for colors, radii and
/// spacing.
///
/// The app is a night LED board, and so are its icon, splash, widget and
/// notifications: [noche] behind everything, [tinta] panels, text in
/// [papel], the amber LEDs lit where something matters. Dot-matrix digits
/// are reserved for live (GPS) data; amber stays on the dark, never on
/// white.
abstract final class TimbreColors {
  // --- The night board ---

  /// Screen background: the board.
  static const noche = Color(0xFF070F22);

  /// Ink: panels, the LED plate, the icon tile.
  static const tinta = Color(0xFF0A1A3A);

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

  /// Secondary text and labels on the board: 7.9:1 on [tinta], 8.6:1 on
  /// [noche].
  static const etiquetaCartel = Color(0xFF9FB0D0);

  /// LED amber: 10.6:1 on [noche], 9.5:1 on [tinta]. Light, not paint:
  /// never on white, never flat yellow-and-black blocks.
  static const ambar = Color(0xFFFFB21E);

  /// Dimmed LED amber for secondary text on the plate: 5.8:1 on [tinta].
  static const ambarTenue = Color(0xFFC68B1E);
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

/// How much of the amber light shows: the board texture and the press.
abstract final class TimbreOpacity {
  /// Unlit LEDs of the board ([TimbreColors.ambar] at 10 %): the header
  /// and the icon tile.
  static const ledUnlit = 0.1;

  /// Tap ripple: the pressed surface lights up.
  static const pressSplash = 0.16;

  /// Pressed highlight under the ripple.
  static const pressHighlight = 0.08;
}

/// Pixel icon sizes.
abstract final class TimbreIconSize {
  /// Marks in a row: accessible, air conditioning, zero emission.
  static const mark = 14.0;

  /// Rows, buttons and the navigation.
  static const row = 20.0;
  static const rowLarge = 24.0;

  /// The Servicios tiles.
  static const tile = 48.0;
}

/// The one shadow on the board: the light of a lit LED sign.
abstract final class TimbreShadow {
  /// "LLEGANDO": [TimbreColors.ambar] at 35 %, blurred 12 px.
  static const ledGlow = BoxShadow(color: Color(0x59FFB21E), blurRadius: 12);
}
