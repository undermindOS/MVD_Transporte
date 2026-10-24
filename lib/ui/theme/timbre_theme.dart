import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'timbre_text.dart';
import 'timbre_tokens.dart';

/// Material 3 theme for Timbre MVD: white and flag blue, Fira everywhere.
/// The LED amber is not part of the color scheme on purpose: it is used
/// only through the cartel widgets, never as a generic accent.
ThemeData buildTimbreTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: TimbreColors.azul,
    onPrimary: TimbreColors.blanco,
    primaryContainer: TimbreColors.celeste,
    onPrimaryContainer: TimbreColors.azul,
    secondary: TimbreColors.azulNoche,
    onSecondary: TimbreColors.blanco,
    secondaryContainer: TimbreColors.celeste,
    onSecondaryContainer: TimbreColors.tinta,
    tertiary: TimbreColors.tinta,
    onTertiary: TimbreColors.blanco,
    error: Color(0xFFB3261E),
    onError: TimbreColors.blanco,
    surface: TimbreColors.blanco,
    onSurface: TimbreColors.tinta,
    onSurfaceVariant: TimbreColors.grisTexto,
    surfaceContainerLowest: TimbreColors.blanco,
    surfaceContainerLow: TimbreColors.blanco,
    surfaceContainer: TimbreColors.niebla,
    surfaceContainerHigh: TimbreColors.niebla,
    surfaceContainerHighest: TimbreColors.celeste,
    outline: TimbreColors.anillo,
    outlineVariant: TimbreColors.linea,
    inverseSurface: TimbreColors.tinta,
    onInverseSurface: TimbreColors.blanco,
    inversePrimary: TimbreColors.sobreAzul,
    shadow: Color(0x1F0A1A3A),
    scrim: Color(0x8C0A1A3A),
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: TimbreFonts.fira,
    scaffoldBackgroundColor: TimbreColors.niebla,
    splashFactory: InkRipple.splashFactory,
  );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(TimbreRadii.button),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: TimbreFonts.fira,
      bodyColor: TimbreColors.tinta,
      displayColor: TimbreColors.tinta,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TimbreColors.azul,
      foregroundColor: TimbreColors.blanco,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: TimbreSpace.l,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontFamily: TimbreFonts.fira,
        fontWeight: FontWeight.w700,
        fontSize: 19,
        color: TimbreColors.blanco,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TimbreColors.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: TimbreColors.celeste,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: TimbreFonts.fira,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? TimbreColors.azul : TimbreColors.grisTexto,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? TimbreColors.azul
                : TimbreColors.grisTexto,
          )),
    ),
    cardTheme: CardThemeData(
      color: TimbreColors.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.card),
        side: const BorderSide(color: TimbreColors.borde),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TimbreColors.azul,
        foregroundColor: TimbreColors.blanco,
        minimumSize: const Size(TimbreSpace.touch, 56),
        shape: rounded,
        textStyle: const TextStyle(
          fontFamily: TimbreFonts.fira,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: TimbreColors.azul,
        foregroundColor: TimbreColors.blanco,
        elevation: 0,
        minimumSize: const Size(TimbreSpace.touch, 48),
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TimbreColors.azul,
        minimumSize: const Size(TimbreSpace.touch, 48),
        side: const BorderSide(color: TimbreColors.linea),
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TimbreColors.azul,
        minimumSize: const Size(TimbreSpace.touch, TimbreSpace.touch),
        textStyle: const TextStyle(
          fontFamily: TimbreFonts.fira,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(TimbreSpace.touch, 48)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? TimbreColors.azul
                : TimbreColors.niebla),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? TimbreColors.blanco
                : TimbreColors.tinta),
        side: const WidgetStatePropertyAll(BorderSide.none),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontFamily: TimbreFonts.fira,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        )),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(TimbreColors.blanco),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? TimbreColors.azul
              : TimbreColors.anillo),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: TimbreColors.niebla,
      selectedColor: TimbreColors.celeste,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: const TextStyle(
        fontFamily: TimbreFonts.fira,
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: TimbreColors.tinta,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: TimbreColors.separador,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TimbreColors.blanco,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: TimbreColors.linea,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(TimbreRadii.sheet)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TimbreColors.blanco,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.linea),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.linea),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.azul, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TimbreColors.tinta,
      contentTextStyle: TextStyle(
        fontFamily: TimbreFonts.fira,
        fontSize: 15,
        color: TimbreColors.blanco,
      ),
      actionTextColor: TimbreColors.sobreAzul,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TimbreColors.azul,
      linearTrackColor: TimbreColors.celeste,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: TimbreColors.azul,
      textColor: TimbreColors.tinta,
    ),
  );
}
