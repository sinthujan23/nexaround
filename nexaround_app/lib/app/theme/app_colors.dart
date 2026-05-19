import 'package:flutter/material.dart';

class AppColors {
  // Base Colors (Uber White)
  static const Color background = Color(0xFFFFFFFF); 
  static const Color surface = Color(0xFFF6F6F6);
  static const Color surfaceElevated = Color(0xFFEEEEEE);
  static const Color surfaceVariant = Color(0xFFE8E8E8);
  
  // Primary / Highlights (Uber Black)
  static const Color primary = Color(0xFF000000);
  static const Color secondary = Color(0xFF262626);
  static const Color accent = Color(0xFF545454);
  
  // Vitality Colors (Premium Accents)
  static const Color ratingGold = Color(0xFFFFB800);
  static const Color actionTeal = Color(0xFF007A7C);
  static const Color categoryFood = Color(0xFFFFF1F1);
  static const Color categoryArch = Color(0xFFF1F7FF);
  static const Color categoryNature = Color(0xFFF1FFF4);
  
  // Tones
  static const Color border = Color(0xFFE2E2E2);
  static const Color glassBorder = Color(0x33000000);
  static const Color glassWhite = Color(0xCCFFFFFF);
  
  // Text Colors
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF545454);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFFBDBDBD);

  // Status Colors (Professional & Vibrant)
  static const Color error = Color(0xFFE53935); // Deep Red
  static const Color success = Color(0xFF43A047); // Professional Green
  static const Color warning = Color(0xFFFFB300); // Amber
  static const Color neonGreen = Color(0xFF00E676); // High-vis Neon Green

  // Gradients (White to Light Gray / Silver)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF000000),
      Color(0xFF262626),
    ],
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF6F6F6),
      Color(0xFFE8E8E8),
    ],
  );

  static const LinearGradient achievementGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFB300), // Amber
      Color(0xFFFFD54F), // Light Gold
    ],
  );

  static const LinearGradient silverGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFBDBDBD),
      Color(0xFFE0E0E0),
    ],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFFF6F6F6),
    ],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xF2FFFFFF),
      Color(0xE6F6F6F6),
    ],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xCCFFFFFF),
      Color(0x99F6F6F6),
    ],
  );
}
