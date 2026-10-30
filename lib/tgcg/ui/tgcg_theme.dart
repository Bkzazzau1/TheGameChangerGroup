import 'package:flutter/material.dart';

import 'tgcg_design.dart';

/// The app's Material theme, in the TGCG navy and gold.
ThemeData tgcgTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TgcgColors.primary,
    brightness: Brightness.light,
    primary: TgcgColors.primary,
    onPrimary: Colors.white,
    primaryContainer: TgcgColors.primarySoft,
    onPrimaryContainer: TgcgColors.primary,
    secondary: TgcgColors.accent,
    onSecondary: TgcgColors.primaryDark,
    secondaryContainer: TgcgColors.accentSoft,
    onSecondaryContainer: TgcgColors.accentDeep,
    tertiary: TgcgColors.accentDeep,
    surface: TgcgColors.surface,
    onSurface: TgcgColors.ink,
    outline: TgcgColors.border,
    error: TgcgColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: TgcgColors.canvas,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: TgcgColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
      ),
      headlineMedium: TextStyle(
        color: TgcgColors.ink,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
      ),
      titleLarge: TextStyle(color: TgcgColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(color: TgcgColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: TgcgColors.ink, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: TgcgColors.ink, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: TgcgColors.muted, fontSize: 12.5, height: 1.4),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: TgcgColors.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TgcgRadius.lg),
        side: const BorderSide(color: TgcgColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: TgcgColors.border, thickness: 1, space: 24),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TgcgColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      labelStyle: const TextStyle(color: TgcgColors.muted, fontSize: 14),
      hintStyle: const TextStyle(color: Color(0xFF7D8499), fontSize: 13.5),
      helperStyle: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
      errorStyle: const TextStyle(color: TgcgColors.danger, fontSize: 12.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        borderSide: const BorderSide(color: TgcgColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        borderSide: const BorderSide(color: TgcgColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        borderSide: const BorderSide(color: TgcgColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TgcgRadius.md),
        borderSide: const BorderSide(color: TgcgColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TgcgColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TgcgColors.primary,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: const BorderSide(color: Color(0xFFC6CEE0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TgcgColors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TgcgColors.primaryDark,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: TgcgColors.accentBright,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TgcgColors.primaryDark,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: TgcgColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: TgcgColors.accentSoft,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? TgcgColors.primary : TgcgColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? TgcgColors.primary : TgcgColors.muted,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: TgcgColors.primary,
      titleTextStyle: TextStyle(color: TgcgColors.ink, fontSize: 14.5, fontWeight: FontWeight.w600),
      subtitleTextStyle: TextStyle(color: TgcgColors.muted, fontSize: 12.5, height: 1.35),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: TgcgColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(color: TgcgColors.ink, fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TgcgColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(TgcgRadius.lg)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TgcgColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.lg)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: TgcgColors.primaryDark.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TgcgColors.accent,
      linearTrackColor: TgcgColors.primarySoft,
      circularTrackColor: TgcgColors.primarySoft,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? TgcgColors.primary : TgcgColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? TgcgColors.accentBright : TgcgColors.primary,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: TgcgColors.border)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w800)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: TgcgColors.surface,
      selectedColor: TgcgColors.primary,
      secondarySelectedColor: TgcgColors.primary,
      checkmarkColor: TgcgColors.accentBright,
      side: const BorderSide(color: TgcgColors.border),
      labelStyle: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w700),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: TgcgColors.primary,
      unselectedLabelColor: TgcgColors.muted,
      indicatorColor: TgcgColors.accent,
      dividerColor: TgcgColors.border,
      labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? TgcgColors.accentBright : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? TgcgColors.primary : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? TgcgColors.primary : null,
      ),
      checkColor: const WidgetStatePropertyAll(TgcgColors.accentBright),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TgcgColors.accent,
      foregroundColor: TgcgColors.primaryDark,
    ),
  );
}
