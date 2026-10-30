import 'package:flutter/material.dart';
import 'app_colors.dart';

ThemeData buildDarkTheme()  => _buildTheme(Brightness.dark);
ThemeData buildLightTheme() => _buildTheme(Brightness.light);

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  // Colores alineados con app_colors.dart
  final bg       = dark ? Color(0xFF0B1220) : Color(0xFFF0F5FF);
  final surface  = dark ? Color(0xFF0F172A) : Color(0xFFFFFFFF);
  final surfaceAlt = dark ? Color(0xFF16213A) : Color(0xFFF8FAFF);
  final border   = dark ? Color(0xFF1E293B) : Color(0xFFE2E8F0);
  final accent   = dark ? Color(0xFF34D399) : Color(0xFF047857);
  final onAccent = dark ? Color(0xFF04241A) : Color(0xFFFFFFFF);
  final text1    = dark ? Colors.white             : Color(0xFF0B1220);
  final text2    = dark ? Colors.white70           : Color(0xFF475569);
  final hint     = dark ? Colors.white54           : Color(0xFF5B6B82);
  final danger   = dark ? Color(0xFFF87171) : Color(0xFFB91C1C);

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: danger,
      onError: dark ? Color(0xFF2A0A0A) : Colors.white,
      surface: surface,
      onSurface: text1,
    ),
    fontFamily: 'Inter',
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text1,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: text1,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: text2),
    ),
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      hintStyle: TextStyle(color: hint, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}