import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const lightColors = ColorScheme.light(
  primary: Color(0xFF4F7EB5),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE7EFF8),
  onPrimaryContainer: Color(0xFF1C1C1E),
  secondary: Color(0xFF7EAAD8),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE3EBF4),
  onSecondaryContainer: Color(0xFF1C1C1E),
  surface: Color(0xFFF6F7FA),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF9FAFC),
  surfaceContainer: Color(0xFFFFFFFF),
  surfaceContainerHigh: Color(0xFFF1F3F7),
  surfaceContainerHighest: Color(0xFFE4E7EE),
  onSurface: Color(0xFF1C1C1E),
  onSurfaceVariant: Color(0xFF6E7480),
  outline: Color(0xFFBFC6D2),
  outlineVariant: Color(0xFFE3E6EE),
  surfaceTint: Colors.transparent,
  error: Color(0xFFD13B4B),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCE9EC),
  onErrorContainer: Color(0xFFB52B3A),
);

const darkColors = ColorScheme.dark(
  primary: Color(0xFF84B2E5),
  onPrimary: Color(0xFF0E1A2A),
  primaryContainer: Color(0xFF233042),
  onPrimaryContainer: Color(0xFFF2F4F8),
  secondary: Color(0xFF6F9FD4),
  onSecondary: Color(0xFF0E1A2A),
  secondaryContainer: Color(0xFF242B38),
  onSecondaryContainer: Color(0xFFF2F4F8),
  surface: Color(0xFF14171F),
  surfaceContainerLowest: Color(0xFF0F1218),
  surfaceContainerLow: Color(0xFF181C25),
  surfaceContainer: Color(0xFF1E222D),
  surfaceContainerHigh: Color(0xFF252A37),
  surfaceContainerHighest: Color(0xFF323847),
  onSurface: Color(0xFFF2F4F8),
  onSurfaceVariant: Color(0xFF969CA8),
  outline: Color(0xFF4B5263),
  outlineVariant: Color(0xFF2C313F),
  surfaceTint: Colors.transparent,
  error: Color(0xFFFF8690),
  onError: Color(0xFF36181D),
  errorContainer: Color(0xFF3A1E24),
  onErrorContainer: Color(0xFFFFB2B8),
);

@immutable
class AppAtmosphere extends ThemeExtension<AppAtmosphere> {
  const AppAtmosphere({
    required this.canvasGradient,
    required this.topFadeColor,
    required this.cardFill,
    required this.cardBorder,
    required this.dockFill,
    required this.dockBorder,
    required this.floatingFill,
    required this.assistantBubbleFill,
    required this.userBubbleFill,
    required this.userBubbleBorder,
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

  final List<Color> canvasGradient;
  final Color topFadeColor;
  final Color cardFill;
  final Color cardBorder;
  final Color dockFill;
  final Color dockBorder;
  final Color floatingFill;
  final Color assistantBubbleFill;
  final Color userBubbleFill;
  final Color userBubbleBorder;
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
    canvasGradient: [
      Color(0xFFB8CDE8),
      Color(0xFFD2E0F2),
      Color(0xFFE7EAEF),
      Color(0xFFF3E8DA),
    ],
    topFadeColor: Color(0xFFB8CDE8),
    cardFill: Color(0xC7FFFFFF),
    cardBorder: Color(0xD9FFFFFF),
    dockFill: Color(0xEBFFFFFF),
    dockBorder: Color(0xE6FFFFFF),
    floatingFill: Color(0xCCFFFFFF),
    assistantBubbleFill: Color(0xEBFFFFFF),
    userBubbleFill: Color(0x4A8BA1BC),
    userBubbleBorder: Color(0x45FFFFFF),
    inputFill: Color(0x0B1C1C1E),
    segmentTrack: Color(0x111C1C1E),
    segmentThumb: Color(0xF5FFFFFF),
    activeTabPill: Color(0x121C1C1E),
    switchActiveTrack: Color(0xFF84AED9),
    switchInactiveTrack: Color(0x2E787880),
    sectionHeader: Color(0xFF6B7382),
    hairline: Color(0x121C1C1E),
    shadowColor: Color(0x111B283C),
  );

  static const dark = AppAtmosphere(
    canvasGradient: [
      Color(0xFF151E2E),
      Color(0xFF151923),
      Color(0xFF17181E),
      Color(0xFF1E1B18),
    ],
    topFadeColor: Color(0xFF151E2E),
    cardFill: Color(0xBA202531),
    cardBorder: Color(0x1AFFFFFF),
    dockFill: Color(0xDF1D222D),
    dockBorder: Color(0x1EFFFFFF),
    floatingFill: Color(0xC7252B38),
    assistantBubbleFill: Color(0xD9222733),
    userBubbleFill: Color(0x525B7EA6),
    userBubbleBorder: Color(0x24FFFFFF),
    inputFill: Color(0x14FFFFFF),
    segmentTrack: Color(0x1AFFFFFF),
    segmentThumb: Color(0xFF323949),
    activeTabPill: Color(0x1CFFFFFF),
    switchActiveTrack: Color(0xFF6F9FD4),
    switchInactiveTrack: Color(0x38787880),
    sectionHeader: Color(0xFF8C94A3),
    hairline: Color(0x18FFFFFF),
    shadowColor: Color(0x40000000),
  );

  static AppAtmosphere of(BuildContext context) {
    final ext = Theme.of(context).extension<AppAtmosphere>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  AppAtmosphere copyWith({
    List<Color>? canvasGradient,
    Color? topFadeColor,
    Color? cardFill,
    Color? cardBorder,
    Color? dockFill,
    Color? dockBorder,
    Color? floatingFill,
    Color? assistantBubbleFill,
    Color? userBubbleFill,
    Color? userBubbleBorder,
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
    canvasGradient: canvasGradient ?? this.canvasGradient,
    topFadeColor: topFadeColor ?? this.topFadeColor,
    cardFill: cardFill ?? this.cardFill,
    cardBorder: cardBorder ?? this.cardBorder,
    dockFill: dockFill ?? this.dockFill,
    dockBorder: dockBorder ?? this.dockBorder,
    floatingFill: floatingFill ?? this.floatingFill,
    assistantBubbleFill: assistantBubbleFill ?? this.assistantBubbleFill,
    userBubbleFill: userBubbleFill ?? this.userBubbleFill,
    userBubbleBorder: userBubbleBorder ?? this.userBubbleBorder,
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
      canvasGradient: [
        for (var i = 0; i < canvasGradient.length; i++)
          Color.lerp(canvasGradient[i], other.canvasGradient[i], t)!,
      ],
      topFadeColor: Color.lerp(topFadeColor, other.topFadeColor, t)!,
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      dockFill: Color.lerp(dockFill, other.dockFill, t)!,
      dockBorder: Color.lerp(dockBorder, other.dockBorder, t)!,
      floatingFill: Color.lerp(floatingFill, other.floatingFill, t)!,
      assistantBubbleFill: Color.lerp(
        assistantBubbleFill,
        other.assistantBubbleFill,
        t,
      )!,
      userBubbleFill: Color.lerp(userBubbleFill, other.userBubbleFill, t)!,
      userBubbleBorder: Color.lerp(
        userBubbleBorder,
        other.userBubbleBorder,
        t,
      )!,
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
    scaffoldBackgroundColor: Colors.transparent,
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
      backgroundColor: dark ? const Color(0xFF282E3C) : const Color(0xFF1F242D),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF202531) : const Color(0xFFF8F9FB),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF1E232F) : const Color(0xFFF8F9FB),
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
