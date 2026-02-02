import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Ocean-blue palette
  static const Color background = Color(0xFF011C40); // primary app background
  static const Color surface =
      Colors.white; // secondary surfaces, receiver bubbles
  static const Color glass = Color(0xFF011C40); // glass panels (55-70% opacity)
  static const Color navy = Color(
    0xFF011C40,
  ); // primary accent (sender, active icons, buttons)
  static const Color highlight = Colors.white; // main text, glow
  static const Color sinopia = Colors.white; // align legacy uses with accent
  static const Color white = Colors.white;
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
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.white,
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
        labelStyle: const TextStyle(color: Colors.black, fontSize: 14),
        hintStyle: const TextStyle(color: Colors.black, fontSize: 14),
        prefixIconColor: AppColors.navy,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
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
            (s) => AppColors.white.withOpacity(
              s.contains(MaterialState.pressed) ? 0.16 : 0.08,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(AppColors.navy),
          textStyle: MaterialStateProperty.resolveWith(
            (s) => const TextStyle(
              decoration: TextDecoration.none,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          overlayColor: MaterialStateProperty.all(
            AppColors.navy.withOpacity(0.08),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.white,
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
