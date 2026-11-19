import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One Curated Hubs tile: photo, dark fade, tag pill at the top, and the
/// title at the bottom with a round arrow at the bottom right. The tall card
/// ([large]) has a bigger title and a feature chip under it; the small
/// stacked ones carry a one-line [subtitle] instead. The whole tile is the
/// button. Used by Curated Hubs and by the Home screen's tiles, so the same
/// card looks the same in both places.
class HubTile extends StatelessWidget {
  final double height;
  final String tag;
  final IconData tagIcon;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final IconData? featureIcon;
  final String? featureLabel;
  final String? imageAsset;
  final Uint8List? imageBytes;
  final Alignment imageAlignment;
  final bool large;
  final VoidCallback onTap;

  const HubTile({
    super.key,
    required this.height,
    required this.tag,
    required this.tagIcon,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.featureIcon,
    this.featureLabel,
    this.imageAsset,
    this.imageBytes,
    this.imageAlignment = Alignment.center,
    this.large = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final asset = imageAsset;
    final feature = featureIcon;
    final featureText = featureLabel;
    final line = subtitle;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null)
                Image.memory(bytes, fit: BoxFit.cover, alignment: imageAlignment)
              else if (asset != null)
                Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  alignment: imageAlignment,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF0F172A).withValues(alpha: 0.9),
                      const Color(0xFF0F172A).withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.08),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(large ? 13 : 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: tag pill
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: accentColor.withValues(alpha: 0.70), width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(tagIcon, size: 10.5, color: accentColor),
                                  const SizedBox(width: 3.5),
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Bottom: title, then the chip (tall) or a short line
                    // (small), with the round arrow at the bottom right, where
                    // the Experiences card has its Explore button.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: large ? (height >= 240 ? 20 : 18) : 15,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                  letterSpacing: -0.2,
                                  color: Colors.white,
                                ),
                              ),
                              if (large && feature != null && featureText != null) ...[
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: _MicroChip(icon: feature, label: featureText, iconColor: accentColor),
                                ),
                              ],
                              if (!large && line != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  line,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: large ? 30 : 26,
                          height: large ? 30 : 26,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: large ? 16 : 14,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small dark chip under the tall tile's title ("Skip the lines").
class _MicroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _MicroChip({required this.icon, required this.label, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x73000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
