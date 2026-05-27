import 'package:flutter/material.dart';

class ExodusTheme {
  // Core palette
  static const Color obsidian      = Color(0xFF0A0E1A);  // app background
  static const Color midnight      = Color(0xFF111726);  // surface
  static const Color slate         = Color(0xFF1A2235);  // raised surface
  static const Color steel         = Color(0xFF2A3349);  // borders / dividers
  static const Color ironMist      = Color(0xFF8A95B0);  // secondary text
  static const Color porcelain     = Color(0xFFE6ECF5);  // primary text

  // Accents
  static const Color covenantBlue  = Color(0xFF3B6FE3);  // primary accent
  static const Color covenantGlow  = Color(0xFF5A8DFF);  // hover / highlight
  static const Color brass         = Color(0xFFC9A961);  // shield / divine
  static const Color brassGlow     = Color(0xFFE5C880);  // shield highlight
  static const Color crimson       = Color(0xFFB94545);  // danger / sin

  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: obsidian,
      primaryColor: covenantBlue,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: covenantBlue,
        secondary: brass,
        surface: midnight,
        onPrimary: porcelain,
        onSecondary: obsidian,
        onSurface: porcelain,
        error: crimson,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: obsidian,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: porcelain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 3.0,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: porcelain, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: porcelain, fontSize: 14, height: 1.5),
        bodySmall:  TextStyle(color: ironMist, fontSize: 12),
        titleLarge: TextStyle(color: porcelain, fontSize: 20, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: porcelain, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slate,
        hintStyle: const TextStyle(color: ironMist),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: steel),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: steel),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: covenantBlue, width: 1.5),
        ),
      ),
    );
  }
}
