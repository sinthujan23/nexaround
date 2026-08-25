import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/auth_token_cache.dart';

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
        // Without this the backend sees an anonymous request and will only
        // serve a photo it already holds on disk, 404-ing otherwise — so a
        // place nobody had opened before could never load its picture. With
        // the token attached the server fetches it from Google on the spot.
        httpHeaders: AuthTokenCache.headersFor(resolvedUrl),
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
      return CachedNetworkImageProvider(
        resolvedUrl,
        headers: AuthTokenCache.headersFor(resolvedUrl),
      );
    }
    return AssetImage(getAssetPath(category, name));
  }

  /// Icon standing in for a place with no usable photo.
  ///
  /// Reads the name as well as the category because the category is often the
  /// broad section a place was fetched under ("POI", "Others") while the name
  /// says exactly what it is. Mirrors Discovery's own mapping.
  static IconData iconForCategory(String category, String name) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();

    // Food & drink
    if (cat.contains('cafe') || cat.contains('coffee') || nm.contains('cafe') || nm.contains('coffee')) {
      return Icons.local_cafe_rounded;
    }
    if (cat.contains('bakery') || cat.contains('bar') || nm.contains('bakery') || nm.contains('sweet')) {
      return Icons.bakery_dining_rounded;
    }
    if (cat.contains('food') || cat.contains('drink') || cat.contains('restaurant') ||
        nm.contains('restaurant') || nm.contains('kitchen') || nm.contains('bistro')) {
      return Icons.restaurant_rounded;
    }

    // Stays
    if (cat.contains('hotel') || cat.contains('stay') || cat.contains('lodging') ||
        cat.contains('resort') || nm.contains('hotel') || nm.contains('resort') ||
        nm.contains('guest house') || nm.contains('villa')) {
      return Icons.hotel_rounded;
    }

    // Health
    if (cat.contains('hospital') || nm.contains('hospital')) {
      return Icons.local_hospital_rounded;
    }
    if (cat.contains('pharmacy') || nm.contains('pharmacy') || nm.contains('chemist') || nm.contains('drug')) {
      return Icons.medication_rounded;
    }
    if (cat.contains('medical') || cat.contains('clinic') || cat.contains('dental') ||
        nm.contains('clinic') || nm.contains('dental') || nm.contains('doctor')) {
      return Icons.medical_services_rounded;
    }

    // Shopping
    if (cat.contains('clothing') || cat.contains('fashion') || nm.contains('fashion') || nm.contains('boutique')) {
      return Icons.shopping_bag_rounded;
    }
    if (nm.contains('market') || nm.contains('bazaar') || nm.contains('mall')) {
      return Icons.storefront_rounded;
    }
    if (cat.contains('shopping') || cat.contains('store') || nm.contains('store') || nm.contains('shop')) {
      return Icons.shopping_cart_rounded;
    }

    // Outdoors & landmarks
    if (cat.contains('beach') || nm.contains('beach')) return Icons.beach_access_rounded;
    if (cat.contains('museum') || cat.contains('gallery') || nm.contains('museum') || nm.contains('gallery')) {
      return Icons.museum_rounded;
    }
    if (cat.contains('nature') || cat.contains('park') || cat.contains('garden') ||
        nm.contains('park') || nm.contains('garden')) {
      return Icons.park_rounded;
    }
    if (nm.contains('temple') || nm.contains('kovil') || nm.contains('mosque') ||
        nm.contains('church') || nm.contains('vihara')) {
      return Icons.account_balance_rounded;
    }
    if (cat.contains('experience')) return Icons.local_activity_rounded;
    if (cat.contains('attraction') || cat.contains('poi')) return Icons.photo_camera_rounded;

    return Icons.place_rounded;
  }

  /// Returns the category-specific asset path for a place.
  ///
  /// Still used by [getImageProvider], which has to hand back an [ImageProvider]
  /// for map markers and decorations — an icon cannot fill that contract.
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

  /// Shown when a place has no photo, or its photo fails to load.
  ///
  /// Deliberately an icon rather than a stock category photograph. The stock
  /// shots read as the place's own picture — a Day-of-the-Dead parade stood in
  /// for a base hospital — so a missing image looked like wrong data instead of
  /// absent data. An icon is honestly empty. Matches the Discovery cards, which
  /// already fall back this way.
  static Widget _buildFallbackAsset(String category, String name, BoxFit fit, double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: AppColors.secondary.withOpacity(0.08),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Scale to whatever box we were handed — the same helper draws a 90px
          // list thumbnail and a full-bleed detail header.
          final finite = [constraints.maxWidth, constraints.maxHeight]
              .where((d) => d.isFinite);
          final shortest = finite.isEmpty
              ? double.infinity
              : finite.reduce((a, b) => a < b ? a : b);
          final double iconSize = shortest.isFinite
              ? (shortest * 0.34).clamp(18.0, 56.0).toDouble()
              : 28.0;
          return Center(
            child: Icon(
              iconForCategory(category, name),
              color: AppColors.secondary.withOpacity(0.45),
              size: iconSize,
            ),
          );
        },
      ),
    );
  }
}
