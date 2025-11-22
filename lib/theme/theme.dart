import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color sinopia = Color(0xFFCB410B);
  static const Color background = Colors.black;
  static const Color surface = Color(0xFF111111);
  static const Color white = Colors.white;
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.sinopia,
        secondary: AppColors.sinopia,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.white,
        displayColor: AppColors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
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
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1),
        borderRadius: BorderRadius.circular(16),
      );

  static BoxDecoration glassDecoration({double radius = 16, bool glow = true}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: glow ? AppColors.sinopia.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2),
          width: glow ? 1.2 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.sinopia.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      );

  static Widget glass({required Widget child, double sigma = 20, double radius = 16}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
