import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One Curated Hubs tile: photo, dark fade, a tag pill at the top (none when
/// [tag] is null), and the title at the bottom with a round arrow at the
/// bottom right. The tall card
/// ([large]) has a bigger title and a feature chip under it; the small
/// stacked ones carry a one-line [subtitle] instead. The whole tile is the
/// button. Used by Curated Hubs and by the Home screen's tiles, so the same
/// card looks the same in both places.
class HubTile extends StatelessWidget {
  final double height;
  final String? tag;
  final IconData? tagIcon;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final IconData? featureIcon;
  final String? featureLabel;
  final String? imageAsset;
  final Uint8List? imageBytes;
  final Alignment imageAlignment;
  final bool large;

  /// Home's look: the title in heavy capitals, as on Home's Experiences
  /// tile, with a small round arrow ([TitleArrow]) joined to its end in place
  /// of the round arrow at the bottom right.
  final bool arrowOnTitle;

  /// Text at the top left, in place of a tag (Home's Trip Split slogan), on
  /// a soft dark fade from the top so it reads over the photo. The title
  /// stays at the bottom.
  final Widget? topText;
  final VoidCallback onTap;

  const HubTile({
    super.key,
    required this.height,
    this.tag,
    this.tagIcon,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.featureIcon,
    this.featureLabel,
    this.imageAsset,
    this.imageBytes,
    this.imageAlignment = Alignment.center,
    this.large = false,
    this.arrowOnTitle = false,
    this.topText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final asset = imageAsset;
    final feature = featureIcon;
    final featureText = featureLabel;
    final line = subtitle;
    final tagText = tag;
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
              // A soft dark band from the top, behind [topText].
              if (topText != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC0F172A), Color(0x000F172A)],
                      stops: [0.0, 0.55],
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(large ? 13 : 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: tag pill, or [topText]. Without either, an empty
                    // box keeps the title at the bottom.
                    if (tagText == null)
                      topText ?? const SizedBox.shrink()
                    else
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
                                    if (tagIcon != null) ...[
                                      Icon(tagIcon, size: 10.5, color: accentColor),
                                      const SizedBox(width: 3.5),
                                    ],
                                    Text(
                                      tagText,
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
                              if (arrowOnTitle)
                                Text.rich(
                                  TextSpan(
                                    text: title.toUpperCase(),
                                    children: const [
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Padding(padding: EdgeInsets.only(left: 6), child: TitleArrow()),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleCapsStyle,
                                )
                              else
                                // Shrinks a little on narrow phones so the whole
                                // title fits in two lines ("Museum Master Guides"
                                // showed as "Museum / Master Gui…").
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final style = TextStyle(
                                      fontSize: large ? (height >= 240 ? 20 : 18) : 15,
                                      fontWeight: FontWeight.w800,
                                      height: 1.12,
                                      letterSpacing: -0.2,
                                      color: Colors.white,
                                    );
                                    return Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: style.copyWith(
                                        fontSize: _fittedSize(context, title, style, constraints.maxWidth, 2),
                                      ),
                                    );
                                  },
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
                        if (!arrowOnTitle) ...[
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

/// The biggest font size, from [style]'s own down to 13, at which [text]
/// fits in [maxLines] lines of [width] without being cut off. Measured with
/// the screen's font and text scale, as the Text will be drawn.
double _fittedSize(BuildContext context, String text, TextStyle style, double width, int maxLines) {
  final base = DefaultTextStyle.of(context).style.merge(style);
  final scaler = MediaQuery.textScalerOf(context);
  var size = base.fontSize ?? 15;
  const min = 13.0;
  while (size > min) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: base.copyWith(fontSize: size)),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) break;
    size -= 1;
  }
  return size;
}

/// Home tiles' title style: heavy white capitals with a soft dark glow, as
/// "UNFORGETTABLE EXPERIENCES" on Home.
const titleCapsStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w900,
  color: Colors.white,
  letterSpacing: 0.6,
  height: 1.15,
  shadows: [Shadow(color: Color(0xB3000000), blurRadius: 6, offset: Offset(0, 1.5))],
);

/// The small white round arrow joined to the end of a Home tile's title, so
/// the title reads like a link.
class TitleArrow extends StatelessWidget {
  const TitleArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF0F172A)),
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
