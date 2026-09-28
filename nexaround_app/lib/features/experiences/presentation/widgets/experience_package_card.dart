import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_category.dart';

/// Compact horizontal experience package card:
/// An exact 104x104 square thumbnail on the left, with essential metadata
/// (category, distance, title, vendor, duration, price) on the right.
/// Shows only essential details; tap opens the full detail page.
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

  static const double _radius = 18;
  static const double _thumbSize = 116;

  @override
  Widget build(BuildContext context) {
    final category = experienceCategoryFor(package.category);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(
                children: [
                  _buildThumbnail(category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: _thumbSize,
                      child: _buildBody(category),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 320.ms,
          delay: (50 * math.min(index, 5)).ms,
        )
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildThumbnail(ExperienceCategory category) {
    final url = PlaceImageHelper.resolveUrl(package.coverPhotoUrl);

    return SizedBox(
      width: _thumbSize,
      height: _thumbSize,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                httpHeaders: PlaceImageHelper.headersFor(url),
                fit: BoxFit.cover,
                memCacheWidth: 350,
                placeholder: (_, _) => _placeholder(category),
                errorWidget: (_, _, _) => _placeholder(category),
              )
            else
              _placeholder(category),

            if (package.photoCount > 1)
              Positioned(
                bottom: 6,
                right: 6,
                child: _Pill(
                  child: _iconText(Icons.photo_library_rounded, '${package.photoCount}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ExperienceCategory category) {
    final cleanDuration = package.formattedDuration
        .replaceAll(RegExp(r'\s+duration', caseSensitive: false), '')
        .trim();

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Top row: Category tag (left) + Distance (right corner)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: category.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, size: 11.5, color: category.accent),
                    const SizedBox(width: 4),
                    Text(
                      category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: category.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (package.distanceM != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded, size: 11, color: AppColors.textTertiary),
                    const SizedBox(width: 3),
                    Text(
                      formatDistance(package.distanceM),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. Middle section: Title + Vendor name (essential details)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                package.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.22,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3.5),
              Row(
                children: [
                  const Icon(Icons.storefront_rounded, size: 12, color: AppColors.brandGreen),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      package.vendorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 3. Footer row: Duration tag (left) + Price & Per-person (right corner)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (cleanDuration.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 10.5, color: AppColors.textSecondary),
                      const SizedBox(width: 3.5),
                      Text(
                        cleanDuration,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              _buildPrice(),
            ],
          ),
        ],
      ),
    );
  }

  /// Price display: amount and per-unit text.
  Widget _buildPrice() {
    final label = package.priceLabel.trim();
    if (label.isEmpty) return const SizedBox.shrink();

    final parts = label.split(' / ');
    final amount = parts.first;
    final rawUnit = parts.length > 1 ? parts.sublist(1).join(' / ').trim() : null;
    final unit = rawUnit != null
        ? (rawUnit.toLowerCase().startsWith('per ') ? rawUnit : 'per $rawUnit')
        : null;
    final onRequest =
        package.priceAmount == null || package.priceBasis == 'on_request';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          amount,
          style: TextStyle(
            fontSize: onRequest ? 11.5 : 14.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: onRequest ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        if (unit != null)
          Text(
            unit,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
              height: 1.15,
            ),
          ),
      ],
    );
  }

  static Widget _iconText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 9.5, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ExperienceCategory category) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: category.tint,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -15,
            bottom: -20,
            child: _ring(80),
          ),
          Positioned(
            left: -12,
            top: -15,
            child: _ring(50),
          ),
          Center(
            child: Icon(
              category.icon,
              size: 38,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _ring(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 8),
      ),
    );
  }
}

/// A small rounded label laid over the thumbnail.
class _Pill extends StatelessWidget {
  final Widget child;

  const _Pill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
