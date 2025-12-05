import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color sinopia = Color(0xFF00AFFF); // electric blue accent
  static const Color navy = Color(0xFF0A1A3A);
  static const Color background = Colors.white;
  static const Color surface = Color(0xFFF7F7F7);
  static const Color white = Colors.white;
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      primaryColor: AppColors.navy,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        secondary: AppColors.sinopia,
        surface: AppColors.white,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: GoogleFonts.interTextTheme(
        base.textTheme,
      ).apply(bodyColor: AppColors.navy, displayColor: AppColors.navy),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white70,
        labelStyle: const TextStyle(color: AppColors.navy, fontSize: 14),
        hintStyle: TextStyle(
          color: AppColors.navy.withValues(alpha: 0.4),
          fontSize: 14,
        ),
        prefixIconColor: AppColors.navy,
        border: _inputBorder,
        enabledBorder: _inputBorder,
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.sinopia, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(const Size.fromHeight(50)),
          foregroundColor: MaterialStateProperty.all(AppColors.white),
          backgroundColor: MaterialStateProperty.all(AppColors.navy),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          overlayColor: MaterialStateProperty.resolveWith(
            (s) => AppColors.sinopia.withValues(
              alpha: s.contains(MaterialState.pressed) ? 0.25 : 0.12,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(AppColors.sinopia),
          textStyle: MaterialStateProperty.resolveWith(
            (s) => TextStyle(
              decoration: s.contains(MaterialState.hovered)
                  ? TextDecoration.underline
                  : TextDecoration.none,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          overlayColor: MaterialStateProperty.all(
            AppColors.sinopia.withValues(alpha: 0.08),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.sinopia,
        foregroundColor: AppColors.white,
      ),
    );
  }

  static OutlineInputBorder get _inputBorder => OutlineInputBorder(
    borderSide: const BorderSide(color: AppColors.sinopia, width: 1.5),
    borderRadius: BorderRadius.circular(14),
  );

  static BoxDecoration glassDecoration({
    double radius = 16,
    bool glow = true,
  }) => BoxDecoration(
    color: Colors.white.withValues(alpha: 0.2),
    borderRadius: BorderRadius.circular(radius),
    border: const Border(top: BorderSide(color: AppColors.sinopia, width: 3)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: AppColors.navy,
              blurRadius: 20,
              offset: Offset(0, 6),
              spreadRadius: 0.0,
            ),
            BoxShadow(
              color: AppColors.sinopia,
              blurRadius: 24,
              spreadRadius: 1.0,
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
