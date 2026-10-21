import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
