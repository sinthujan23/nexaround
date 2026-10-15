import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// A gallery photo shown whole, never cropped.
///
/// Vendors upload whatever they have - collages, portrait shots, panoramas -
/// and a fixed-height banner with `BoxFit.cover` cuts off whichever edges do
/// not fit. This shows the full picture instead, and fills the space left over
/// with a blurred copy of the same photo (the way product pages do) so it does
/// not sit in a plain bar. Both layers use the same URL, so it is downloaded
/// once.
class ExperienceFittedPhoto extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;

  /// Space kept clear at the top, so the status bar does not sit over the
  /// photo's upper edge.
  final double topInset;

  const ExperienceFittedPhoto({
    super.key,
    required this.url,
    this.headers,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    Widget blank() => Container(color: AppColors.surfaceVariant);

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers,
            fit: BoxFit.cover,
            placeholder: (_, __) => blank(),
            errorWidget: (_, __, ___) => blank(),
          ),
        ),
        ColoredBox(color: Colors.black.withOpacity(0.25)),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
