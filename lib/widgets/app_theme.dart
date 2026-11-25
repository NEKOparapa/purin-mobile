import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const lightColors = ColorScheme.light(
  primary: Color(0xFF3983DF),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE1EFFD),
  onPrimaryContainer: Color(0xFF1C62BD),
  secondary: Color(0xFF3983DF),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFDEECFA),
  onSecondaryContainer: Color(0xFF1E2936),
  surface: Color(0xFFF5F6F8),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xEBFFFFFF),
  surfaceContainerHigh: Color(0xFFE5EEF8),
  surfaceContainerHighest: Color(0xFFD9E5F2),
  onSurface: Color(0xFF1E2936),
  onSurfaceVariant: Color(0xFF58697D),
  outline: Color(0xFFC7D5E4),
  outlineVariant: Color(0xFFE0E8F2),
  surfaceTint: Colors.transparent,
  error: Color(0xFFD93848),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFDECEE),
  onErrorContainer: Color(0xFFA61B2B),
);

const darkColors = ColorScheme.dark(
  primary: Color(0xFF6BB0FF),
  onPrimary: Color(0xFF081728),
  primaryContainer: Color(0x2E5CA4F8),
  onPrimaryContainer: Color(0xFFE0EEFF),
  secondary: Color(0xFF6BB0FF),
  onSecondary: Color(0xFF081728),
  secondaryContainer: Color(0xFF203652),
  onSecondaryContainer: Color(0xFFEEF3F9),
  surface: Color(0xFF121720),
  surfaceContainerLowest: Color(0xFF18202C),
  surfaceContainerLow: Color(0xFF1A2330),
  surfaceContainer: Color(0xE01E2938),
  surfaceContainerHigh: Color(0xFF243143),
  surfaceContainerHighest: Color(0xFF2D3D53),
  onSurface: Color(0xFFEEF3F9),
  onSurfaceVariant: Color(0xFFA0B3C8),
  outline: Color(0x33C8DEF8),
  outlineVariant: Color(0x1CC8DEF8),
  surfaceTint: Colors.transparent,
  error: Color(0xFFFF7078),
  onError: Color(0xFF361216),
  errorContainer: Color(0xAD3A1B22),
  onErrorContainer: Color(0xFFFFBAC0),
);

@immutable
class AppAtmosphere extends ThemeExtension<AppAtmosphere> {
  const AppAtmosphere({
    required this.cardFill,
    required this.cardBorder,
    required this.dockFill,
    required this.dockBorder,
    required this.assistantBubbleFill,
    required this.userBubbleFill,
    required this.inputFill,
    required this.segmentTrack,
    required this.segmentThumb,
    required this.activeTabPill,
    required this.switchActiveTrack,
    required this.switchInactiveTrack,
    required this.sectionHeader,
    required this.hairline,
    required this.shadowColor,
  });

  final Color cardFill;
  final Color cardBorder;
  final Color dockFill;
  final Color dockBorder;
  final Color assistantBubbleFill;
  final Color userBubbleFill;
  final Color inputFill;
  final Color segmentTrack;
  final Color segmentThumb;
  final Color activeTabPill;
  final Color switchActiveTrack;
  final Color switchInactiveTrack;
  final Color sectionHeader;
  final Color hairline;
  final Color shadowColor;

  static const light = AppAtmosphere(
    cardFill: Color(0xE0FFFFFF),
    cardBorder: Color(0xFFDEE7F2),
    dockFill: Color(0xEDFFFFFF),
    dockBorder: Color(0xFFD9E4F0),
    assistantBubbleFill: Color(0xF0FFFFFF),
    userBubbleFill: Color(0xFFDEECFA),
    inputFill: Color(0xCCFFFFFF),
    segmentTrack: Color(0xFFE4ECF6),
    segmentThumb: Color(0xFFFFFFFF),
    activeTabPill: Color(0xFFE1EFFD),
    switchActiveTrack: Color(0xFF3983DF),
    switchInactiveTrack: Color(0xFFC7D5E4),
    sectionHeader: Color(0xFF58697D),
    hairline: Color(0xFFE0E8F2),
    shadowColor: Color(0x0A183458),
  );

  static const dark = AppAtmosphere(
    cardFill: Color(0xDC1C2634),
    cardBorder: Color(0x1FC8DEF8),
    dockFill: Color(0xE61E2938),
    dockBorder: Color(0x26C8DEF8),
    assistantBubbleFill: Color(0xE61E2938),
    userBubbleFill: Color(0xFF203652),
    inputFill: Color(0xB8151E2B),
    segmentTrack: Color(0xFF161F2C),
    segmentThumb: Color(0xFF28374C),
    activeTabPill: Color(0x2E5CA4F8),
    switchActiveTrack: Color(0xFF6BB0FF),
    switchInactiveTrack: Color(0x38C8DEF8),
    sectionHeader: Color(0xFFA0B3C8),
    hairline: Color(0x1CC8DEF8),
    shadowColor: Color(0x38000000),
  );

  static AppAtmosphere of(BuildContext context) {
    final ext = Theme.of(context).extension<AppAtmosphere>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  AppAtmosphere copyWith({
    Color? cardFill,
    Color? cardBorder,
    Color? dockFill,
    Color? dockBorder,
    Color? assistantBubbleFill,
    Color? userBubbleFill,
    Color? inputFill,
    Color? segmentTrack,
    Color? segmentThumb,
    Color? activeTabPill,
    Color? switchActiveTrack,
    Color? switchInactiveTrack,
    Color? sectionHeader,
    Color? hairline,
    Color? shadowColor,
  }) => AppAtmosphere(
    cardFill: cardFill ?? this.cardFill,
    cardBorder: cardBorder ?? this.cardBorder,
    dockFill: dockFill ?? this.dockFill,
    dockBorder: dockBorder ?? this.dockBorder,
    assistantBubbleFill: assistantBubbleFill ?? this.assistantBubbleFill,
    userBubbleFill: userBubbleFill ?? this.userBubbleFill,
    inputFill: inputFill ?? this.inputFill,
    segmentTrack: segmentTrack ?? this.segmentTrack,
    segmentThumb: segmentThumb ?? this.segmentThumb,
    activeTabPill: activeTabPill ?? this.activeTabPill,
    switchActiveTrack: switchActiveTrack ?? this.switchActiveTrack,
    switchInactiveTrack: switchInactiveTrack ?? this.switchInactiveTrack,
    sectionHeader: sectionHeader ?? this.sectionHeader,
    hairline: hairline ?? this.hairline,
    shadowColor: shadowColor ?? this.shadowColor,
  );

  @override
  AppAtmosphere lerp(ThemeExtension<AppAtmosphere>? other, double t) {
    if (other is! AppAtmosphere) return this;
    return AppAtmosphere(
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      dockFill: Color.lerp(dockFill, other.dockFill, t)!,
      dockBorder: Color.lerp(dockBorder, other.dockBorder, t)!,
      assistantBubbleFill: Color.lerp(
        assistantBubbleFill,
        other.assistantBubbleFill,
        t,
      )!,
      userBubbleFill: Color.lerp(userBubbleFill, other.userBubbleFill, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      segmentTrack: Color.lerp(segmentTrack, other.segmentTrack, t)!,
      segmentThumb: Color.lerp(segmentThumb, other.segmentThumb, t)!,
      activeTabPill: Color.lerp(activeTabPill, other.activeTabPill, t)!,
      switchActiveTrack: Color.lerp(
        switchActiveTrack,
        other.switchActiveTrack,
        t,
      )!,
      switchInactiveTrack: Color.lerp(
        switchInactiveTrack,
        other.switchInactiveTrack,
        t,
      )!,
      sectionHeader: Color.lerp(sectionHeader, other.sectionHeader, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
    );
  }
}

SystemUiOverlayStyle barsFor(ColorScheme colors) {
  final dark = colors.brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      );
}

ThemeData terminalTheme(ColorScheme colors) {
  final dark = colors.brightness == Brightness.dark;
  final atmo = dark ? AppAtmosphere.dark : AppAtmosphere.light;
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    scaffoldBackgroundColor: colors.surface,
    colorScheme: colors,
    extensions: [atmo],
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(
      color: atmo.hairline,
      space: 0.6,
      thickness: 0.6,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: barsFor(colors),
      titleSpacing: 4,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: colors.onSurfaceVariant.withValues(alpha: 0.6),
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary,
      selectionColor: colors.primary.withValues(alpha: 0.22),
      selectionHandleColor: colors.primary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xEB1E2938) : const Color(0xEB1E2936),
      contentTextStyle: const TextStyle(color: Color(0xFFEEF3F9), fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: atmo.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      labelStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 14.5),
      hintStyle: TextStyle(
        color: colors.onSurfaceVariant.withValues(alpha: 0.72),
        fontSize: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: colors.primary.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
    ),
  );
}
