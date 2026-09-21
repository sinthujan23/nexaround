import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// One package as a Discovery card. The vendor's name is the subtitle, which
/// is what keeps a vendor's three boat tours readable as three distinct
/// offers rather than three copies of the same agency.
class ExperiencePackageCard extends StatelessWidget {
  final ExperiencePackageEntity package;
  final int index;
  final VoidCallback onTap;

  const ExperiencePackageCard({
    super.key,
    required this.package,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumbUrl = PlaceImageHelper.resolveUrl(package.coverPhotoUrl);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          glowColor: index % 2 == 0 ? AppColors.secondary : AppColors.primary,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl,
                        httpHeaders: PlaceImageHelper.headersFor(thumbUrl),
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        memCacheWidth: 270, // 90px thumbnail at 3x DPR
                        placeholder: (_, __) => _placeholder(),
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      package.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      package.vendorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.near_me_rounded,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          formatDistance(package.distanceM),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary),
                        ),
                        if (package.durationLabel.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Text(
                            package.durationLabel,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                    if (package.priceLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        package.priceLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 90,
      height: 90,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.kayaking_rounded,
          size: 26, color: AppColors.textMuted),
    );
  }
}
