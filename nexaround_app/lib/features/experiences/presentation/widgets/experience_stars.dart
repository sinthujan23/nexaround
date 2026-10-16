import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// Five stars with [value] of them filled (rounded to the nearest whole star).
class ExperienceStars extends StatelessWidget {
  final double value;
  final double size;

  const ExperienceStars({super.key, required this.value, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final filled = value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          Icon(
            n <= filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: n <= filled ? AppColors.ratingGold : AppColors.textMuted,
          ),
      ],
    );
  }
}

/// A compact "★ 4.8 (12)" for a card or a title line.
class ExperienceRatingBadge extends StatelessWidget {
  final double average;
  final int count;
  final double fontSize;

  const ExperienceRatingBadge({
    super.key,
    required this.average,
    required this.count,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: fontSize + 2, color: AppColors.ratingGold),
        const SizedBox(width: 2),
        Text(
          average.toStringAsFixed(1),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '($count)',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Five tappable stars for choosing a rating.
class ExperienceStarPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  const ExperienceStarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var n = 1; n <= 5; n++)
          IconButton(
            onPressed: () => onChanged(n),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: size + 4, minHeight: size + 4),
            tooltip: '$n ${n == 1 ? 'star' : 'stars'}',
            icon: Icon(
              n <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: n <= value ? AppColors.ratingGold : AppColors.textMuted,
            ),
          ),
      ],
    );
  }
}
