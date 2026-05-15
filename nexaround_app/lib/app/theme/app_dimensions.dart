import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPaddingCompact =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

class AppRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;

  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
  static const Radius rXl = Radius.circular(xl);

  static const BorderRadius brSm = BorderRadius.all(rSm);
  static const BorderRadius brMd = BorderRadius.all(rMd);
  static const BorderRadius brLg = BorderRadius.all(rLg);
  static const BorderRadius brXl = BorderRadius.all(rXl);
}

class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
}

class AppCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
}

/// Premium layered shadow system. Stacking a tight ambient shadow with a wider
/// diffuse one produces depth without heavy banding on light surfaces.
class AppShadows {
  static const List<BoxShadow> none = [];

  /// Subtle resting elevation for cards and tiles.
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  /// Elevated surface (sheets, prominent cards).
  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 32,
      offset: Offset(0, 16),
      spreadRadius: -12,
    ),
  ];

  /// Floating sheets / modals / hero cards.
  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 16,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 48,
      offset: Offset(0, 24),
      spreadRadius: -16,
    ),
  ];

  /// Soft glow used behind floating action elements.
  static List<BoxShadow> glow(Color color, {double opacity = 0.18}) => [
        BoxShadow(
          color: color.withOpacity(opacity),
          blurRadius: 28,
          spreadRadius: -6,
          offset: const Offset(0, 8),
        ),
      ];

  /// Inset-style highlight for primary buttons.
  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 16,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
  ];
}

class AppBorders {
  static const BorderSide hairline =
      BorderSide(color: AppColors.border, width: 0.6);
  static const BorderSide glass =
      BorderSide(color: AppColors.glassBorder, width: 0.6);
}
