import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';

/// A gallery photo that fills its frame edge to edge, with no blurred bars.
///
/// The detail header is a 4:3 frame and package photos are stored at 4:3, so
/// a photo fills it exactly. A photo of another shape is cropped to the frame
/// around its centre rather than padded; the full picture is one tap away in
/// the full-screen viewer.
class ExperienceFittedPhoto extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;

  const ExperienceFittedPhoto({
    super.key,
    required this.url,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    Widget blank() => Container(color: AppColors.surfaceVariant);

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => blank(),
      errorWidget: (context, url, error) => blank(),
    );
  }
}
