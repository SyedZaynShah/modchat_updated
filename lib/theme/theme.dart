import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color sinopia = Color(0xFF006CFF); // electric blue accent
  static const Color background = Colors.white;
  static const Color surface = Color(0xFFF7F7F7);
  static const Color white = Colors.white;
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.sinopia,
        secondary: AppColors.sinopia,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: GoogleFonts.interTextTheme(
        base.textTheme,
      ).apply(bodyColor: Colors.black, displayColor: Colors.black),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
        border: _glassBorder,
        enabledBorder: _glassBorder,
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.sinopia, width: 1.4),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.sinopia,
        foregroundColor: AppColors.white,
      ),
    );
  }

  static OutlineInputBorder get _glassBorder => OutlineInputBorder(
    borderSide: BorderSide(
      color: Colors.black.withValues(alpha: 0.12),
      width: 1,
    ),
    borderRadius: BorderRadius.circular(16),
  );

  static BoxDecoration glassDecoration({
    double radius = 16,
    bool glow = true,
  }) => BoxDecoration(
    color: Colors.white.withValues(alpha: 0.65),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: glow
          ? AppColors.sinopia.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.08),
      width: glow ? 1.2 : 1,
    ),
    boxShadow: glow
        ? [
            BoxShadow(
              color: AppColors.sinopia.withValues(alpha: 0.15),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ]
        : [],
  );

  static Widget glass({
    required Widget child,
    double sigma = 20,
    double radius = 16,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
