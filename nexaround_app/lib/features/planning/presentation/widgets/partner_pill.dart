import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// The solid button every paid partner gets (GetTransfer, Airalo, Aviasales):
/// brand teal, the partner's logo on a white tile, white label, and an arrow
/// saying it opens outside the app.
///
/// Partners are drawn to stand out from every other link (user, 2026-09-29:
/// "our partners should be highlighted more than others").
class PartnerPill extends StatelessWidget {
  final String logoAsset;
  final IconData fallbackIcon;
  final String label;
  final VoidCallback onTap;

  /// Full width and taller, for a card's main action; otherwise a compact
  /// chip that sits in a row.
  final bool expand;

  const PartnerPill({
    super.key,
    required this.logoAsset,
    required this.fallbackIcon,
    required this.label,
    required this.onTap,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: expand ? 22 : 18,
          height: expand ? 22 : 18,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              logoAsset,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) =>
                  Icon(fallbackIcon, size: 12, color: AppColors.brandGreen),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: expand ? 13.5 : 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.open_in_new_rounded, size: expand ? 14 : 11, color: Colors.white),
      ],
    );
    return Material(
      color: AppColors.brandGreen,
      borderRadius: BorderRadius.circular(expand ? 12 : 8),
      elevation: 1.5,
      shadowColor: AppColors.brandGreen.withValues(alpha: 0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(expand ? 12 : 8),
        onTap: onTap,
        child: Padding(
          padding: expand
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 11)
              : const EdgeInsets.fromLTRB(5, 4, 9, 4),
          child: content,
        ),
      ),
    );
  }
}
