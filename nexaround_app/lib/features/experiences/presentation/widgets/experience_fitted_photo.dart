import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/story_photo_preview.dart';

/// A gallery photo that fills its frame edge to edge, with no blurred bars.
///
/// The detail header is a 4:3 frame and package photos are stored at 4:3, so
/// a photo fills it exactly. A photo of another shape is cropped to the frame
/// around its centre rather than padded; the full picture is one tap away in
/// the full-screen viewer.
///
/// While it loads it shows [preview], the photo's own colours blurred, like
/// Travel Stories do, and the photo fades in over it. Without a preview (an
/// older server, or a photo kept elsewhere) a small spinner shows instead of
/// an empty frame.
class ExperienceFittedPhoto extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;

  /// Tiny base64 WebP from the package's `image_previews`, or null.
  final String? preview;

  const ExperienceFittedPhoto({
    super.key,
    required this.url,
    this.headers,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    Widget loading() {
      final tiny = preview;
      if (tiny != null && tiny.isNotEmpty) return StoryPhotoPreview(preview: tiny);
      return Container(
        color: AppColors.surface,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brandGreen,
            ),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => loading(),
      errorWidget: (context, url, error) =>
          Container(color: AppColors.surfaceVariant),
    );
  }
}
