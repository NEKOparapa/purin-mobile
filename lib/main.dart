import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

const accent = Color(0xFFB8D9C5);
const muted = Color(0xFF9AAA9F);
const surface = Color(0xFF19221F);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF141B18),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const WintermuteApp());
}

class WintermuteApp extends StatelessWidget {
  const WintermuteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wintermute',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101614),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ).copyWith(
            primary: accent,
            onPrimary: const Color(0xFF19382A),
            surface: surface,
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF101614),
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: const Color(0xFF303E34),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF141B18),
        indicatorColor: const Color(0xFF2B4133),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF202D25),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const HomeScreen(),
  );
}
