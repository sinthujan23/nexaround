import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

/// Central utility to handle place images with category-specific fallback assets.
class PlaceImageHelper {
  /// Builds an image widget for a place. If [imagePath] is empty or fails, 
  /// it uses a category-specific asset as a fallback.
  static Widget buildPlaceImage({
    required String? imagePath,
    required String category,
    required String name,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    Widget imageWidget;

    String? resolvedUrl = imagePath;
    if (resolvedUrl != null && resolvedUrl.isNotEmpty && resolvedUrl != 'null') {
      if (resolvedUrl.startsWith('/')) {
        resolvedUrl = '${ApiConstants.baseUrl}$resolvedUrl';
      }
    }

    if (resolvedUrl != null && resolvedUrl.isNotEmpty && resolvedUrl != 'null' && resolvedUrl.startsWith('http')) {
      imageWidget = CachedNetworkImage(
        imageUrl: resolvedUrl,
        fit: fit,
        width: width,
        height: height,
        placeholder: (context, url) => Container(
          color: Colors.grey.shade900,
          child: const Center(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildFallbackAsset(category, name, fit, width, height),
      );
    } else {
      imageWidget = _buildFallbackAsset(category, name, fit, width, height);
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// Gets an [ImageProvider] for a place. Useful for Map markers or decorations.
  static ImageProvider getImageProvider(String? imagePath, String category, String name) {
    String? resolvedUrl = imagePath;
    if (resolvedUrl != null && resolvedUrl.isNotEmpty && resolvedUrl != 'null') {
      if (resolvedUrl.startsWith('/')) {
        resolvedUrl = '${ApiConstants.baseUrl}$resolvedUrl';
      }
    }
    if (resolvedUrl != null && resolvedUrl.isNotEmpty && resolvedUrl != 'null' && resolvedUrl.startsWith('http')) {
      return CachedNetworkImageProvider(resolvedUrl);
    }
    return AssetImage(getAssetPath(category, name));
  }

  /// Returns the category-specific asset path for a place.
  static String getAssetPath(String category, String name) {
    final cat = category.toUpperCase();
    final hash = name.hashCode;
    
    String prefix = 'art';
    int count = 4;

    if (cat.contains('FOOD') || cat.contains('RESTAURANT') || cat.contains('CAFE') || cat.contains('MEAL')) {
      prefix = 'cafe';
      count = 3;
    } else if (cat.contains('STAY') || cat.contains('HOTEL') || cat.contains('RESORT') || cat.contains('LODGING')) {
      prefix = 'stays';
      count = 3;
    } else if (cat.contains('CULTURE') || cat.contains('MUSEUM') || cat.contains('HISTORY') || cat.contains('ART') || cat.contains('TEMPLE') || cat.contains('ATTRACTION')) {
      prefix = 'art';
      count = 4;
    } else if (cat.contains('NATURE') || cat.contains('PARK') || cat.contains('BEACH') || cat.contains('FOREST')) {
      prefix = 'park';
      count = 3;
    }

    final index = (hash.abs() % count) + 1;
    return 'assets/images/$prefix$index.jpeg';
  }

  static Widget _buildFallbackAsset(String category, String name, BoxFit fit, double? width, double? height) {
    return Image.asset(
      getAssetPath(category, name), 
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (c, e, s) => Container(
        color: Colors.black, 
        width: width,
        height: height,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.white10, size: 20),
        ),
      ),
    );
  }
}
