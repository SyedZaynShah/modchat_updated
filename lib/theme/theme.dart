import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Dark charcoal background palette
  static const Color background = Color(0xFF121417); // primary app background
  static const Color surface = Color(
    0xFF181B20,
  ); // secondary surfaces, receiver bubbles
  static const Color glass = Color(0xFF181B20); // glass panels (55-70% opacity)

  // Burgundy accent system (premium, controlled confidence)
  static const Color burgundy = Color(0xFF5A0F1B);
  static const Color burgundySoftGlow = Color(0x8C5A0F1B); // 0.55
  static const Color burgundyFaintGlow = Color(0x405A0F1B); // 0.25

  // Legacy aliases (kept to avoid refactors across the codebase)
  static const Color navy = burgundy; // primary accent
  static const Color highlight = Color(0xFFE6E6E6); // main text, glow
  static const Color sinopia = burgundy; // align legacy uses with accent
  static const Color white = Color(0xFFE6E6E6);

  static const Color bgTop = Color(0xFF181B20);
  static const Color bgBottom = Color(0xFF121417);
  static const Color textSecondary = Color(0xFF9A9A9A);
  static const Color textDisabled = Color(0xFF5F636B);
  static const Color iconMuted = Color(0xFF9A9A9A);
  static const Color outline = Color(0xFF2A2F38);
  static const Color cardTop = Color(0xFF1B1F26);
  static const Color cardBottom = Color(0xFF15181D);
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      primaryColor: AppColors.navy,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        secondary: AppColors.navy,
        surface: AppColors.surface,
        background: AppColors.background,
        onPrimary: AppColors.highlight,
        onSecondary: AppColors.highlight,
        onSurface: AppColors.highlight,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.highlight, // title icons default to light
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.highlight,
        displayColor: AppColors.highlight,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        prefixIconColor: AppColors.iconMuted,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(const Size.fromHeight(50)),
          foregroundColor: MaterialStateProperty.all(AppColors.highlight),
          backgroundColor: MaterialStateProperty.all(AppColors.navy),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          overlayColor: MaterialStateProperty.resolveWith(
            (s) => AppColors.highlight.withOpacity(
              s.contains(MaterialState.pressed) ? 0.08 : 0.04,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(AppColors.highlight),
          textStyle: MaterialStateProperty.resolveWith(
            (s) => const TextStyle(
              decoration: TextDecoration.none,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          overlayColor: MaterialStateProperty.all(
            AppColors.highlight.withOpacity(0.06),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.highlight,
      ),
    );
  }

  static BoxDecoration glassDecoration({
    double radius = 16,
    bool glow = true,
  }) => BoxDecoration(
    color: Colors.black.withOpacity(0.0), // no tinted glass color
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.navy.withOpacity(0.0), width: 0),
    boxShadow: glow ? [] : [],
  );

  static Widget glass({
    required Widget child,
    double sigma = 14,
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
