import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

class AppTypography {
  static const String fontFamily = 'Outfit';

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.8,
    color: AppColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.25,
    color: AppColors.textPrimary,
  );

  static const TextStyle h4 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: -0.05,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
    letterSpacing: 0.1,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0.15,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.2,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.35,
    color: AppColors.textTertiary,
  );

  /// All-caps eyebrow label used above section headers for an editorial feel.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 1.6,
    color: AppColors.textTertiary,
  );
}
