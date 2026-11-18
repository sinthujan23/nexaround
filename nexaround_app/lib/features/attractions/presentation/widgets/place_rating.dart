import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

/// The stars on a place card. The server says which ones (`ratingSource`):
/// Google's (gold), our travellers' once at least 3 rated it (green), or none,
/// when the free-map-data "Famous" / "Popular with travellers" chip shows
/// instead, if there is one. Never prints "0.0".
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

  Widget _stars(double value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(value.toStringAsFixed(1), style: textStyle),
        ],
      );

  Widget _chip() {
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

  @override
  Widget build(BuildContext context) {
    switch (place.ratingSource) {
      case 'google':
        return _stars(place.rating, AppColors.ratingGold);
      case 'nexaround':
        final double ours = place.ourRating ?? 0.0;
        return ours > 0 ? _stars(ours, AppColors.brandGreen) : _chip();
      case 'none':
        return _chip();
    }
    // An answer from before the server said which stars to show.
    if (place.isFreeData) return _chip();
    if (place.rating <= 0) return const SizedBox.shrink();
    return _stars(place.rating, AppColors.ratingGold);
  }
}
