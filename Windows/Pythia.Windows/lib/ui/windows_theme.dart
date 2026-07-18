import 'package:flutter/material.dart';

ThemeData pythiaWindowsTheme(
  Brightness brightness, {
  Color accentColor = const Color(0xFF5C9A37),
}) {
  final colors = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
  );
  const controlRadius = BorderRadius.all(Radius.circular(8));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: const ['Segoe UI', 'Arial'],
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: const OutlineInputBorder(
        borderRadius: controlRadius,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: const RoundedRectangleBorder(borderRadius: controlRadius),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: controlRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: controlRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: controlRadius),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return colors.primary.withValues(alpha: 0.18);
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.primary.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      indicatorColor: colors.primaryContainer,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: controlRadius,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      indicatorColor: colors.primaryContainer,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: controlRadius,
      ),
    ),
  );
}
