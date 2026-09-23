import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/contact_launcher.dart';

/// Renders social media buttons for a vendor (WhatsApp, Instagram, Facebook, X).
///
/// **Rule**: Only platforms the vendor actually provides are rendered. If the
/// vendor has none, this widget renders [SizedBox.shrink].
class VendorSocialBar extends StatelessWidget {
  final String? whatsapp;
  final String? instagram;
  final String? facebook;
  final String? x;
  final String? packageTitle;
  final double iconSize;
  final double spacing;
  final bool isCompact;

  const VendorSocialBar({
    super.key,
    this.whatsapp,
    this.instagram,
    this.facebook,
    this.x,
    this.packageTitle,
    this.iconSize = 22,
    this.spacing = 6,
    this.isCompact = true,
  });

  bool get hasWhatsapp => (whatsapp ?? '').trim().isNotEmpty;
  bool get hasInstagram => (instagram ?? '').trim().isNotEmpty;
  bool get hasFacebook => (facebook ?? '').trim().isNotEmpty;
  bool get hasX => (x ?? '').trim().isNotEmpty;
  bool get hasAny => hasWhatsapp || hasInstagram || hasFacebook || hasX;

  @override
  Widget build(BuildContext context) {
    if (!hasAny) return const SizedBox.shrink();

    final items = <Widget>[];

    if (hasWhatsapp) {
      items.add(_buildIconButton(
        imageAsset: 'assets/images/social_whatsapp.png',
        tooltip: 'Chat on WhatsApp',
        label: 'WhatsApp',
        onTap: () => ContactLauncher.whatsApp(
          whatsapp,
          message: packageTitle != null && packageTitle!.isNotEmpty
              ? 'Hi, I am interested in "$packageTitle" I found on NexAround.'
              : 'Hi, I found your service on NexAround.',
        ),
      ));
    }

    if (hasInstagram) {
      items.add(_buildIconButton(
        imageAsset: 'assets/images/social_instagram.png',
        tooltip: 'View Instagram',
        label: 'Instagram',
        onTap: () => ContactLauncher.instagram(instagram),
      ));
    }

    if (hasFacebook) {
      items.add(_buildIconButton(
        imageAsset: 'assets/images/social_facebook.png',
        tooltip: 'View Facebook',
        label: 'Facebook',
        onTap: () => ContactLauncher.facebook(facebook),
      ));
    }

    if (hasX) {
      items.add(_buildIconButton(
        imageAsset: 'assets/images/social_x.png',
        tooltip: 'View on X',
        label: 'X (Twitter)',
        onTap: () => ContactLauncher.x(x),
      ));
    }

    if (isCompact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            items[i],
          ],
        ],
      );
    }

    // Detail mode: larger, touch-friendly horizontal chips with label
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items,
    );
  }

  Widget _buildIconButton({
    required String imageAsset,
    required String tooltip,
    required String label,
    required VoidCallback onTap,
  }) {
    if (isCompact) {
      return Material(
        color: Colors.transparent,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(iconSize / 3.2),
            splashColor: AppColors.brandGreen.withOpacity(0.18),
            highlightColor: Colors.black.withOpacity(0.05),
            child: Container(
              width: iconSize + 4,
              height: iconSize + 4,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(iconSize / 3.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(iconSize / 4),
                child: Image.asset(
                  imageAsset,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Detailed / expanded style with label
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withOpacity(0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border.withOpacity(0.8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  imageAsset,
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
