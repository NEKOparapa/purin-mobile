import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const lightColors = ColorScheme.light(
  primary: Color(0xFF975239),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF3E5DA),
  onPrimaryContainer: Color(0xFF362F29),
  secondary: Color(0xFF975239),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF3E3D5),
  onSecondaryContainer: Color(0xFF362F29),
  surface: Color(0xFFFBF9F5),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF5F1EB),
  surfaceContainer: Color(0xFFFFFEFD),
  surfaceContainerHigh: Color(0xFFF2EEE8),
  surfaceContainerHighest: Color(0xFFE4DDD3),
  onSurface: Color(0xFF362F29),
  onSurfaceVariant: Color(0xFF625B54),
  outline: Color(0xFFC8BEB2),
  outlineVariant: Color(0xFFE4DDD3),
  surfaceTint: Colors.transparent,
  error: Color(0xFFD13B4B),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCE9EC),
  onErrorContainer: Color(0xFFB52B3A),
);

const darkColors = ColorScheme.dark(
  primary: Color(0xFFEAB092),
  onPrimary: Color(0xFF34261F),
  primaryContainer: Color(0xFF45382F),
  onPrimaryContainer: Color(0xFFF3EEE8),
  secondary: Color(0xFFEAB092),
  onSecondary: Color(0xFF34261F),
  secondaryContainer: Color(0xFF4C392D),
  onSecondaryContainer: Color(0xFFF3EEE8),
  surface: Color(0xFF211F1E),
  surfaceContainerLowest: Color(0xFF211F1E),
  surfaceContainerLow: Color(0xFF272422),
  surfaceContainer: Color(0xFF302C29),
  surfaceContainerHigh: Color(0xFF2C2926),
  surfaceContainerHighest: Color(0xFF453E37),
  onSurface: Color(0xFFF3EEE8),
  onSurfaceVariant: Color(0xFFC4BAB0),
  outline: Color(0xFF62594F),
  outlineVariant: Color(0xFF453E37),
  surfaceTint: Colors.transparent,
  error: Color(0xFFFF8690),
  onError: Color(0xFF36181D),
  errorContainer: Color(0xFF3A1E24),
  onErrorContainer: Color(0xFFFFB2B8),
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
    cardFill: Color(0xFFFFFEFD),
    cardBorder: Color(0xFFE4DDD3),
    dockFill: Color(0xFFFFFEFD),
    dockBorder: Color(0xFFC8BEB2),
    assistantBubbleFill: Color(0xFFFFFEFD),
    userBubbleFill: Color(0xFFF3E3D5),
    inputFill: Color(0xFFF5F1EB),
    segmentTrack: Color(0xFFF2EEE8),
    segmentThumb: Color(0xFFFFFEFD),
    activeTabPill: Color(0xFFF3E5DA),
    switchActiveTrack: Color(0xFF975239),
    switchInactiveTrack: Color(0xFFC8BEB2),
    sectionHeader: Color(0xFF625B54),
    hairline: Color(0xFFE4DDD3),
    shadowColor: Color(0x104B3821),
  );

  static const dark = AppAtmosphere(
    cardFill: Color(0xFF302C29),
    cardBorder: Color(0xFF453E37),
    dockFill: Color(0xFF302C29),
    dockBorder: Color(0xFF62594F),
    assistantBubbleFill: Color(0xFF302C29),
    userBubbleFill: Color(0xFF4C392D),
    inputFill: Color(0xFF272422),
    segmentTrack: Color(0xFF2C2926),
    segmentThumb: Color(0xFF302C29),
    activeTabPill: Color(0xFF45382F),
    switchActiveTrack: Color(0xFFEAB092),
    switchInactiveTrack: Color(0xFF62594F),
    sectionHeader: Color(0xFFC4BAB0),
    hairline: Color(0xFF453E37),
    shadowColor: Color(0x30000000),
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
      backgroundColor: const Color(0xFF443A33),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
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
