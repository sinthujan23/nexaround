import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_category.dart';

/// One package as a Discovery card: a large photo with the category and
/// distance on it, then the title, the vendor, and the price.
///
/// The vendor's name is the subtitle, which is what keeps a vendor's three
/// boat tours readable as three distinct offers rather than three copies of
/// the same agency. Social links live on the detail page, not here: on a card
/// they competed with the price for attention.
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

  static const double _radius = 20;

  @override
  Widget build(BuildContext context) {
    final category = experienceCategoryFor(package.category);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPhoto(category),
                _buildBody(),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 320.ms,
          // Stagger the first screenful only; later pages appear together.
          delay: (60 * math.min(index, 5)).ms,
        )
        .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildPhoto(ExperienceCategory category) {
    final url = PlaceImageHelper.resolveUrl(package.coverPhotoUrl);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            CachedNetworkImage(
              imageUrl: url,
              httpHeaders: PlaceImageHelper.headersFor(url),
              fit: BoxFit.cover,
              memCacheWidth: 1080, // full-width card at ~3x DPR
              placeholder: (_, __) => _placeholder(category),
              errorWidget: (_, __, ___) => _placeholder(category),
            )
          else
            _placeholder(category),

          // A soft shade at the top so the white pills read on a bright sky.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x40000000), Color(0x00000000)],
                ),
              ),
            ),
          ),

          Positioned(
            top: 10,
            left: 10,
            child: _Pill(
              light: true,
              child: Text(
                '${category.emoji}  ${category.label}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          if (package.distanceM != null)
            Positioned(
              top: 10,
              right: 10,
              child: _Pill(
                child: _iconText(Icons.near_me_rounded, formatDistance(package.distanceM)),
              ),
            ),

          if (package.photoCount > 1)
            Positioned(
              bottom: 10,
              right: 10,
              child: _Pill(
                child: _iconText(Icons.photo_library_rounded, '${package.photoCount}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final summary = (package.summary ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            package.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 13, color: AppColors.brandGreen),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  package.vendorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandGreen,
                  ),
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: package.formattedDuration.isNotEmpty
                    ? _metaChip(Icons.schedule_rounded, package.formattedDuration)
                    : const SizedBox.shrink(),
              ),
              _buildPrice(),
            ],
          ),
        ],
      ),
    );
  }

  /// The server renders "LKR 4,500 / person"; the card sets the amount large
  /// and the unit small beneath it. "From …" and "Price on request" have no
  /// unit and render whole.
  Widget _buildPrice() {
    final label = package.priceLabel.trim();
    if (label.isEmpty) return const SizedBox.shrink();

    final parts = label.split(' / ');
    final amount = parts.first;
    final unit = parts.length > 1 ? 'per ${parts.sublist(1).join(' / ')}' : null;
    final onRequest =
        package.priceAmount == null || package.priceBasis == 'on_request';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          amount,
          style: TextStyle(
            fontSize: onRequest ? 12.5 : 16.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: onRequest ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        if (unit != null)
          Text(
            unit,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
          ),
      ],
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.brandGreenLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.brandGreen),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brandGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _iconText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
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
        children: [
          // Two faint rings, so an empty photo still reads as designed.
          Positioned(
            right: -40,
            bottom: -50,
            child: _ring(180),
          ),
          Positioned(
            left: -30,
            top: -40,
            child: _ring(120),
          ),
          Center(
            child: Text(category.emoji, style: const TextStyle(fontSize: 48)),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 18),
      ),
    );
  }
}

/// A small rounded label laid over the photo.
class _Pill extends StatelessWidget {
  final Widget child;
  final bool light;

  const _Pill({required this.child, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.94) : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
