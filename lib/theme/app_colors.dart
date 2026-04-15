import 'package:flutter/material.dart';

class AppColors {
  // DARK
  static const darkBackground = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF111827);
  static const darkCard = Color(0xFF1F2937);
  static const darkBorder = Color(0xFF374151);

  // LIGHT
  static const lightBackground = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF1F5F9);
  static const lightBorder = Color(0xFFE2E8F0);

  static const primary = Color(0xFF5865F2);
  static const primaryHover = Color(0xFF4752C4);
  static const primaryPressed = Color(0xFF3C45A5);

  static const background = darkBackground;
  static const surface = darkSurface;
  static const border = darkBorder;

  static const textDarkPrimary = Color(0xFFE5E7EB);
  static const textDarkSecondary = Color(0xFF9CA3AF);
  static const textLightPrimary = Color(0xFF0F172A);
  static const textLightSecondary = Color(0xFF64748B);

  static const textPrimary = textDarkPrimary;
  static const textSecondary = textDarkSecondary;
  static const timeTextLight = Color(0xFF94A3B8);

  // Chat-specific light tokens
  static const chatBackgroundLight = Color(0xFFF8FAFC);
  static const incomingBubbleLight = Color(0xFFFFFFFF);
  static const outgoingBubbleLight = Color(0xFFEEF2FF);
  static const bubbleBorderLight = Color(0xFFE2E8F0);
  static const inputBgLight = Color(0xFFFFFFFF);
  static const inputBorderLight = Color(0xFFE2E8F0);
  static const dividerLight = Color(0xFFE5E7EB);

  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);

  // Backward-compatible semantic aliases used across the existing UI.
  static const card = darkCard;
  static const input = surface;
  static const accent = primary;
  static const burgundy = primaryHover;
  static const highlight = textPrimary;
  static const textTertiary = Color(0xFF6B7280);
  static const textDisabled = Color(0xFF6B7280);
  static const outline = border;
  static const outlineStrong = border;
  static const iconMuted = textSecondary;
  static const iconContainer = Color(0xFF0B1220);

  static const navy = primary;
  static const sinopia = primary;
  static const white = textPrimary;

  static const bgTop = background;
  static const bgBottom = background;
  static const cardTop = surface;
  static const cardBottom = surface;
  static const glass = surface;
}
