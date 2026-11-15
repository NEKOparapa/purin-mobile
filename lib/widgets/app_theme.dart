import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const lightColors = ColorScheme.light(
  primary: Color(0xFF4959BD),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFEEF0F7),
  onPrimaryContainer: Color(0xFF20222A),
  secondary: Color(0xFF4354BA),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFEEF0F7),
  onSecondaryContainer: Color(0xFF20222A),
  surface: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFF6F7F9),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceContainerHigh: Color(0xFFFFFFFF),
  surfaceContainerHighest: Color(0xFFDEE1E9),
  onSurface: Color(0xFF20222A),
  onSurfaceVariant: Color(0xFF5E6473),
  outline: Color(0xFF858B9A),
  outlineVariant: Color(0xFFDEE1E9),
  surfaceTint: Colors.transparent,
  error: Color(0xFFA02F40),
  onError: Color(0xFFFCE8EB),
  errorContainer: Color(0xFFFCE8EB),
  onErrorContainer: Color(0xFFA02F40),
);

const darkColors = ColorScheme.dark(
  primary: Color(0xFFA8B1FF),
  onPrimary: Color(0xFF171A30),
  primaryContainer: Color(0xFF292C39),
  onPrimaryContainer: Color(0xFFF1F2F5),
  secondary: Color(0xFFB0B8FF),
  onSecondary: Color(0xFF171A30),
  secondaryContainer: Color(0xFF292C39),
  onSecondaryContainer: Color(0xFFF1F2F5),
  surface: Color(0xFF16171B),
  surfaceContainerLowest: Color(0xFF101115),
  surfaceContainerLow: Color(0xFF16171B),
  surfaceContainer: Color(0xFF202126),
  surfaceContainerHigh: Color(0xFF202126),
  surfaceContainerHighest: Color(0xFF343640),
  onSurface: Color(0xFFF1F2F5),
  onSurfaceVariant: Color(0xFFA5A8B4),
  outline: Color(0xFF6A6D7A),
  outlineVariant: Color(0xFF343640),
  surfaceTint: Colors.transparent,
  error: Color(0xFFFFACB1),
  onError: Color(0xFF382429),
  errorContainer: Color(0xFF382429),
  onErrorContainer: Color(0xFFFFACB1),
);

SystemUiOverlayStyle barsFor(ColorScheme colors) {
  final dark = colors.brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: colors.surface,
      );
}

ThemeData terminalTheme(ColorScheme colors) {
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    scaffoldBackgroundColor: colors.surface,
    colorScheme: colors,
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surfaceContainerLowest,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: barsFor(colors),
      titleSpacing: 4,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        disabledBackgroundColor: colors.outlineVariant,
        disabledForegroundColor: colors.onSurfaceVariant,
        minimumSize: Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colors.secondary),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.secondary,
      selectionColor: colors.primary.withValues(alpha: .3),
      selectionHandleColor: colors.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainer,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: TextStyle(color: colors.onSurfaceVariant),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.secondary, width: 1.5),
      ),
    ),
  );
}
