import 'package:flutter/material.dart';

/// Design tokens extracted from the Stitch "Institutional Utility" system
/// (see design_assets/institutional_utility/DESIGN.md and the screen HTML).
/// Zero gradients, hairline borders, tonal separation — per the design system.
abstract final class AppColors {
  // Surfaces
  static const surface = Color(0xFFF8F9FD);
  static const card = Color(0xFFFFFFFF);
  static const cardLow = Color(0xFFF2F3F8);
  static const cardHigh = Color(0xFFE7E8EC);
  static const cardHighest = Color(0xFFE1E2E6);
  static const hairline = Color(0xFFE5E7EB);

  // Text
  static const textPrimary = Color(0xFF1A1D20);
  static const textSecondary = Color(0xFF5F676E);
  static const textDisabled = Color(0xFF9CA3AF);

  // Primary / verified (institutional forest teal)
  static const primary = Color(0xFF134E4A);
  static const primaryPressed = Color(0xFF0F3F3C);
  static const primaryTint = Color(0xFFB5EDE7); // low-saturation wash
  static const primaryTintText = Color(0xFF00403C);

  // Status accents
  static const successBg = Color(0xFFF0FDF4);
  static const successText = Color(0xFF166534);
  static const pendingBg = Color(0xFFFEF3C7);
  static const pendingText = Color(0xFFB45309);
  static const dangerBg = Color(0xFFFEF2F2);
  static const dangerText = Color(0xFFB91C1C);
  static const error = Color(0xFFBA1A1A);

  // Curfew / roll-call banner
  static const bannerBg = Color(0xFFFFDBCA);
  static const bannerText = Color(0xFF331200);
  static const bannerTextStrong = Color(0xFF763300);

  static const scrim = Color(0x66111827); // 40% #111827
}
