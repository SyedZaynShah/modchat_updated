import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Core matte black/white design system
  static const Color background = Color(0xFF000000); // primary background
  static const Color surface = Color(0xFF0C0C0C); // secondary background
  static const Color card = Color(0xFF121212); // surface cards
  static const Color input = Color(0xFF0F0F0F); // input fields

  // Chat colors
  static const Color burgundy = Color(0xFF7A1F3D); // sent bubble
  static const Color accent = Color(0xFFC74B6C); // soft accent (rare)

  // Typography
  static const Color highlight = Color(0xFFFFFFFF); // primary text
  static const Color textSecondary = Color(0xFFA5A5A5);
  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color textDisabled = Color(0xFF5A5A5A);

  // Dividers / outlines
  static const Color outline = Color(0xFF1E1E1E);
  static const Color outlineStrong = Color(0xFF2A2A2A);
  static const Color iconMuted = Color(0xFF9A9A9A);
  static const Color iconContainer = Color(0xFF151515);

  // Legacy aliases (kept to avoid refactors across the codebase)
  static const Color navy = highlight;
  static const Color sinopia = burgundy;
  static const Color white = highlight;

  // Legacy gradient/dual-tone colors (mapped to matte surfaces)
  static const Color bgTop = background;
  static const Color bgBottom = background;
  static const Color cardTop = card;
  static const Color cardBottom = card;
  static const Color glass = card;
}

class AppTheme {
  static ThemeData get theme {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.poppinsTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppColors.highlight, displayColor: AppColors.highlight);
    return base.copyWith(
      primaryColor: AppColors.highlight,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.highlight,
        secondary: AppColors.accent,
        surface: AppColors.card,
        onPrimary: Colors.black,
        onSecondary: AppColors.highlight,
        onSurface: AppColors.highlight,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.highlight,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.highlight,
        size: 18,
        weight: 200,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.highlight,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        minLeadingWidth: 28,
        minVerticalPadding: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: AppColors.highlight,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: const TextStyle(
          color: AppColors.highlight,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.highlight
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.outlineStrong
              : AppColors.outline,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.input,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        prefixIconColor: AppColors.iconMuted,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.outlineStrong,
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 44)),
          foregroundColor: WidgetStateProperty.all(Colors.black),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.pressed)
                ? const Color(0xFFEAEAEA)
                : AppColors.highlight,
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
          overlayColor: WidgetStateProperty.all(Colors.black.withOpacity(0.04)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 44)),
          foregroundColor: WidgetStateProperty.all(AppColors.highlight),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.outlineStrong, width: 1),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => AppColors.highlight.withOpacity(
              s.contains(WidgetState.pressed) ? 0.06 : 0.03,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.all(AppColors.accent),
          textStyle: WidgetStateProperty.resolveWith(
            (s) => const TextStyle(
              decoration: TextDecoration.none,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          overlayColor: WidgetStateProperty.all(
            AppColors.accent.withOpacity(0.10),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.highlight,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
    );
  }

  static BoxDecoration glassDecoration({
    double radius = 16,
    bool glow = true,
  }) => BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.outline, width: 1),
    boxShadow: const [],
  );

  static Widget glass({
    required Widget child,
    double sigma = 14,
    double radius = 16,
  }) {
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}
