import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/api_constants.dart';
import '../../data/models/travel_story.dart';

/// What a story photo shows while it loads: the tiny preview the server sends
/// with the story ([TravelStory.imagePreviews]), scaled up and blurred, so the
/// photo's colours are there at once and the photo fades in over them.
class StoryPhotoPreview extends StatelessWidget {
  /// Base64 WebP, about 32 px on its long side.
  final String preview;
  final BoxFit fit;

  const StoryPhotoPreview({
    super.key,
    required this.preview,
    this.fit = BoxFit.cover,
  });

  // The same bytes object for the same preview, so Flutter's image cache
  // finds it decoded on every rebuild instead of blinking while it decodes
  // again. Insertion-ordered: the oldest go once it is full.
  static final Map<String, Uint8List?> _bytes = {};
  static const int _maxCached = 300;

  static Uint8List? _bytesOf(String preview) {
    if (_bytes.containsKey(preview)) return _bytes[preview];
    Uint8List? bytes;
    try {
      bytes = base64Decode(preview);
    } catch (_) {
      bytes = null;
    }
    if (_bytes.length >= _maxCached) _bytes.remove(_bytes.keys.first);
    return _bytes[preview] = bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytesOf(preview);
    if (bytes == null) return const SizedBox.expand();
    return ClipRect(
      child: Transform.scale(
        // The blur thins out at the image's edges; drawn a little larger
        // and clipped, the edges stay as solid as the middle.
        scale: fit == BoxFit.cover ? 1.15 : 1.0,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Image.memory(
            bytes,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// One of [story]'s photos, filling its box, found the way [TravelStoryCard]
/// finds them: a full URL, a server path, or a file on this phone that has
/// not been uploaded yet. Its blurred preview shows while it loads.
class StoryPhoto extends StatelessWidget {
  final TravelStory story;
  final String url;

  /// Decoded no wider than this. Story photos are camera uploads, 3000 px+
  /// wide, and each would otherwise be tens of MB of bitmap.
  final int memCacheWidth;

  const StoryPhoto({
    super.key,
    required this.story,
    required this.url,
    required this.memCacheWidth,
  });

  Widget _loading() {
    final preview = story.imagePreviews[url];
    if (preview != null) return StoryPhotoPreview(preview: preview);
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.brandGreen,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget failed(_, _, _) => Container(color: AppColors.surfaceVariant);
    final remote = url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('/static/');
    if (url.isEmpty) return failed(null, null, null);
    if (!remote) {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover, errorBuilder: failed);
      }
    }
    return CachedNetworkImage(
      imageUrl: url.startsWith('/') ? '${ApiConstants.baseUrl}$url' : url,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      placeholder: (_, _) => _loading(),
      errorWidget: failed,
    );
  }
}
