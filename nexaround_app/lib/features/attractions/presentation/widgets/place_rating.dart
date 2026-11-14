import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

/// The star rating on a place card, or — for free-map-data places, which have
/// no Google rating — the small "Famous" / "Popular with travellers" chip, or
/// nothing at all. Never prints "0.0".
class PlaceRating extends StatelessWidget {
  final AttractionEntity place;
  final double iconSize;
  final TextStyle textStyle;

  const PlaceRating({
    super.key,
    required this.place,
    required this.iconSize,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (place.isFreeData) {
      final label = place.popularityLabel;
      if (label == null || label.isEmpty) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'Famous' ? Icons.workspace_premium_rounded : Icons.favorite_rounded,
            size: iconSize,
            color: AppColors.brandGreen,
          ),
          const SizedBox(width: 4),
          Text(label, style: textStyle),
        ],
      );
    }
    // A place nobody has rated yet shows nothing rather than "0.0".
    if (place.rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: iconSize, color: AppColors.ratingGold),
        const SizedBox(width: 4),
        Text('${place.rating}', style: textStyle),
      ],
    );
  }
}
