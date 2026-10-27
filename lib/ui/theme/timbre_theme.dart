import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/pixel_icon.dart';
import 'timbre_text.dart';
import 'timbre_tokens.dart';

/// Material 3 theme for Timbre MVD: a night LED board. Ink panels on
/// [TimbreColors.noche], text in [TimbreColors.papel], the amber lit where
/// something matters (the main action, the selection, live data). Fira for
/// reading, Doto for signs.
ThemeData buildTimbreTheme() {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: TimbreColors.ambar,
    onPrimary: TimbreColors.tinta,
    primaryContainer: TimbreColors.tintaAlta,
    onPrimaryContainer: TimbreColors.ambar,
    secondary: TimbreColors.etiquetaCartel,
    onSecondary: TimbreColors.noche,
    secondaryContainer: TimbreColors.tintaAlta,
    onSecondaryContainer: TimbreColors.papel,
    tertiary: TimbreColors.ambarTenue,
    onTertiary: TimbreColors.noche,
    error: TimbreColors.rojoLed,
    onError: TimbreColors.noche,
    surface: TimbreColors.tinta,
    onSurface: TimbreColors.papel,
    onSurfaceVariant: TimbreColors.etiquetaCartel,
    surfaceContainerLowest: TimbreColors.noche,
    surfaceContainerLow: TimbreColors.tinta,
    surfaceContainer: TimbreColors.tinta,
    surfaceContainerHigh: TimbreColors.tintaAlta,
    surfaceContainerHighest: TimbreColors.tintaAlta,
    outline: TimbreColors.lineaNoche,
    outlineVariant: TimbreColors.lineaNoche,
    // No white surface anywhere, not even an inverse one
    inverseSurface: TimbreColors.tintaAlta,
    onInverseSurface: TimbreColors.papel,
    inversePrimary: TimbreColors.ambarTenue,
    // Tokens, not black literals: the board casts no shadow
    shadow: TimbreColors.noche,
    scrim: TimbreColors.noche.withValues(alpha: 0.7),
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Legacy widgets read primaryColor: amber, like the scheme
    primaryColor: TimbreColors.ambar,
    fontFamily: TimbreFonts.fira,
    scaffoldBackgroundColor: TimbreColors.noche,
    canvasColor: TimbreColors.noche,
    splashFactory: InkRipple.splashFactory,
    splashColor:
        TimbreColors.ambar.withValues(alpha: TimbreOpacity.pressSplash),
    highlightColor:
        TimbreColors.ambar.withValues(alpha: TimbreOpacity.pressHighlight),
  );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(TimbreRadii.button),
  );
  const boldFira = TextStyle(
    fontFamily: TimbreFonts.fira,
    fontWeight: FontWeight.w700,
    fontSize: 16,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: TimbreFonts.fira,
      bodyColor: TimbreColors.papel,
      displayColor: TimbreColors.papel,
    ),
    iconTheme: const IconThemeData(color: TimbreColors.papel, size: 24),
    // Back and close buttons in pixels, like the rest of the board
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const PixelIcon(PixelGlyphs.back),
      closeButtonIconBuilder: (_) => const PixelIcon(PixelGlyphs.close),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TimbreColors.noche,
      foregroundColor: TimbreColors.papel,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: TimbreSpace.l,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: TimbreColors.tinta,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: TimbreColors.papel, size: 24),
      actionsIconTheme: IconThemeData(color: TimbreColors.papel, size: 24),
      titleTextStyle: TextStyle(
        fontFamily: TimbreFonts.fira,
        fontWeight: FontWeight.w700,
        fontSize: 19,
        color: TimbreColors.papel,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: TimbreColors.tinta,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: TimbreColors.tintaAlta,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TimbreText.navLabel.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? TimbreColors.ambar : TimbreColors.tenue,
        );
      }),
      // The selected tab is lit
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? TimbreColors.ambar
                : TimbreColors.tenue,
          )),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: TimbreColors.ambar,
      unselectedLabelColor: TimbreColors.tenue,
      indicatorColor: TimbreColors.ambar,
      dividerColor: TimbreColors.lineaNoche,
      labelStyle: TimbreText.tabLabel,
      unselectedLabelStyle: TextStyle(
          fontFamily: TimbreFonts.fira,
          fontWeight: FontWeight.w500,
          fontSize: 13,
          height: 1.2),
    ),
    cardTheme: CardThemeData(
      color: TimbreColors.tinta,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.card),
        side: const BorderSide(color: TimbreColors.lineaNoche),
      ),
    ),
    // The main action is lit amber
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TimbreColors.ambar,
        foregroundColor: TimbreColors.tinta,
        disabledBackgroundColor: TimbreColors.tintaAlta,
        disabledForegroundColor: TimbreColors.tenue,
        minimumSize: const Size(TimbreSpace.touch, 52),
        shape: rounded,
        textStyle: TimbreText.buttonLarge,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: TimbreColors.ambar,
        foregroundColor: TimbreColors.tinta,
        elevation: 0,
        minimumSize: const Size(TimbreSpace.touch, 48),
        shape: rounded,
        textStyle: boldFira,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TimbreColors.ambar,
        minimumSize: const Size(TimbreSpace.touch, 48),
        side: const BorderSide(color: TimbreColors.ambarTenue, width: 1.5),
        shape: rounded,
        textStyle: TimbreText.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TimbreColors.ambar,
        minimumSize: const Size(TimbreSpace.touch, TimbreSpace.touch),
        textStyle: TimbreText.button,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: TimbreColors.papel,
        minimumSize: const Size(TimbreSpace.touch, TimbreSpace.touch),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(TimbreSpace.touch, 48)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? TimbreColors.ambar
                : TimbreColors.tinta),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? TimbreColors.tinta
                : TimbreColors.papel),
        side: const WidgetStatePropertyAll(
            BorderSide(color: TimbreColors.lineaNoche)),
        textStyle: const WidgetStatePropertyAll(boldFira),
      ),
    ),
    // On = a lit LED
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? TimbreColors.tinta
              : TimbreColors.tenue),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? TimbreColors.ambar
              : TimbreColors.tintaAlta),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.transparent
              : TimbreColors.lineaNoche),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: TimbreColors.tintaAlta,
      selectedColor: TimbreColors.ambar,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      // Text on the lit amber is the ink, never light (1.5:1)
      labelStyle: TextStyle(
        fontFamily: TimbreFonts.fira,
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? TimbreColors.tinta
                : TimbreColors.papel),
      ),
      checkmarkColor: TimbreColors.tinta,
    ),
    dividerTheme: const DividerThemeData(
      color: TimbreColors.lineaNoche,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TimbreColors.tinta,
      modalBackgroundColor: TimbreColors.tinta,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: TimbreColors.lineaNoche,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(TimbreRadii.sheet)),
        side: BorderSide(color: TimbreColors.lineaNoche),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TimbreColors.tinta,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.sheet),
        side: const BorderSide(color: TimbreColors.lineaNoche),
      ),
      titleTextStyle: TimbreText.dialogTitle,
      contentTextStyle: TimbreText.body,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TimbreColors.noche,
      labelStyle: const TextStyle(color: TimbreColors.etiquetaCartel),
      floatingLabelStyle: const TextStyle(color: TimbreColors.ambar),
      hintStyle: const TextStyle(color: TimbreColors.tenue),
      prefixIconColor: TimbreColors.etiquetaCartel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.lineaNoche),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.lineaNoche),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TimbreRadii.control),
        borderSide: const BorderSide(color: TimbreColors.ambar, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: TimbreColors.ambar,
      selectionColor: TimbreColors.ambar.withValues(alpha: 0.32),
      selectionHandleColor: TimbreColors.ambar,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: TimbreColors.tintaAlta,
      // No shadow on the board: the raised panel is enough
      elevation: 0,
      contentTextStyle: TimbreText.body,
      actionTextColor: TimbreColors.ambar,
      behavior: SnackBarBehavior.floating,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TimbreColors.ambar,
      foregroundColor: TimbreColors.tinta,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    // Counters are tiny lit plates
    badgeTheme: const BadgeThemeData(
      backgroundColor: TimbreColors.ambar,
      textColor: TimbreColors.tinta,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TimbreColors.ambar,
      linearTrackColor: TimbreColors.lineaNoche,
      refreshBackgroundColor: TimbreColors.tinta,
    ),
    // Marks in a list are passive: not lit
    listTileTheme: const ListTileThemeData(
      iconColor: TimbreColors.etiquetaCartel,
      textColor: TimbreColors.papel,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: TimbreColors.tintaAlta,
        borderRadius: BorderRadius.circular(TimbreRadii.chip),
      ),
      textStyle: const TextStyle(
        fontFamily: TimbreFonts.fira,
        fontSize: 13,
        color: TimbreColors.papel,
      ),
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: TimbreColors.tinta,
      dialHandColor: TimbreColors.ambar,
    ),
  );
}
