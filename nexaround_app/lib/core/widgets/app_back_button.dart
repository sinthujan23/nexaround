import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// The app's round back button, as on Museums, Experiences and Curated Hubs:
/// a circle holding the iOS-style arrow. Put it in an AppBar's `leading`.
///
/// [onImage] is for a photo or dark header: a dark see-through circle with a
/// white arrow, readable on any picture. Otherwise it is for a light bar: a
/// light grey circle with a dark arrow.
class AppBackButton extends StatelessWidget {
  final bool onImage;

  /// Defaults to going back one screen.
  final VoidCallback? onPressed;

  const AppBackButton({super.key, this.onImage = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: onImage ? Colors.black.withValues(alpha: 0.4) : AppColors.surface,
          shape: BoxShape.circle,
          border: onImage ? null : Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: onImage ? Colors.white : AppColors.textPrimary,
          ),
          onPressed: onPressed ?? () => Navigator.maybePop(context),
        ),
      ),
    );
  }
}
