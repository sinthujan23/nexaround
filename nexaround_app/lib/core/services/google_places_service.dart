import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/mapbox_geocoding_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

/// Service to fetch real place data from Google Maps Places API
/// and reverse-geocode current location.
class GooglePlacesService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';
  static const String _apiKey = ApiConstants.googleMapsApiKey;

  /// Stale-while-revalidate window. A cache hit younger than this returns
  /// immediately and does NOT trigger a background refresh — that's what
  /// keeps the bill flat.
  static const Duration _cacheFreshness = Duration(hours: 24);

  // Google Places type mapping for our categories
  static const Map<String, String> categoryTypeMap = {
    'Attractions': 'tourist_attraction',
    'Food & Drink': 'restaurant',
    'Hotels': 'lodging',
    'Shopping': 'shopping_mall',
    'Experiences': 'amusement_park',
    'Transport': 'transit_station',
    'Medical': 'hospital',
  };

  /// Reverse-geocode lat/lng to a human-readable location name.
  /// Delegates to Mapbox (100k/mo free) instead of Google Geocoding ($5/1k)
  /// to keep cost down. Signature preserved so existing callers don't change.
  static Future<String> reverseGeocode(double lat, double lng) {
    return MapboxGeocodingService.reverseGeocode(lat, lng);
  }

  /// Fetch nearby places from Google Places API (Nearby Search)
  /// For Food & Drink: uses intelligent multi-query to capture ALL food spots
  static Future<List<AttractionEntity>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String? categoryName,
    int radius = 5000,
  }) async {
    // Round to 3 decimal places for reasonable cache hits (~110m accuracy)
    final cacheKey = 'places_${latitude.toStringAsFixed(3)}_${longitude.toStringAsFixed(3)}_${categoryName ?? "all"}_rad$radius';
    final tsKey = '${cacheKey}_ts';

    final cachedData = CacheService.getUserData(cacheKey);
    if (cachedData != null) {
      try {
        final List<dynamic> decoded = json.decode(cachedData);
        final cachedModels = decoded.map((p) => AttractionModel.fromJson(p)).toList();

        final tsStr = CacheService.getUserData(tsKey);
        final ts = int.tryParse(tsStr ?? '') ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - ts;
        final isFresh = age < _cacheFreshness.inMilliseconds;

        debugPrint('🚀 [CACHE] Places hit: ${cachedModels.length} items (${isFresh ? "fresh" : "stale"})');

        // Only fire a paid refresh if the cache is past its freshness window.
        // Fresh hits are free — that's the whole point.
        if (!isFresh) {
          _refreshPlacesInBackground(latitude, longitude, categoryName, radius, cacheKey, tsKey);
        }
        return cachedModels;
      } catch (e) {
        debugPrint('[CACHE] Places Error: $e');
      }
    }

    return _performFetchNearby(latitude, longitude, categoryName, radius, cacheKey, tsKey);
  }

  static void _refreshPlacesInBackground(double lat, double lng, String? cat, int rad, String key, String tsKey) async {
    try {
      await _performFetchNearby(lat, lng, cat, rad, key, tsKey);
      debugPrint('♻️ [CACHE] Background Places Refresh Complete');
    } catch (e) {
      debugPrint('[CACHE] Refresh failed: $e');
    }
  }

  static Future<List<AttractionEntity>> _performFetchNearby(
    double latitude,
    double longitude,
    String? categoryName,
    int radius,
    String cacheKey,
    String tsKey,
  ) async {
    // Backend path — shared Redis cache across all users in the same ~500m
    // tile. Direct-Google path below is the rollback fallback.
    if (ApiConstants.useBackendPlaces) {
      try {
        final models = await _fetchFromBackend(
          latitude: latitude,
          longitude: longitude,
          categoryName: categoryName,
          radius: radius,
        );
        CacheService.saveUserData(
          cacheKey,
          json.encode(models.map((m) => (m as AttractionModel).toJson()).toList()),
        );
        CacheService.saveUserData(tsKey, DateTime.now().millisecondsSinceEpoch.toString());
        return models;
      } catch (e) {
        debugPrint('[BACKEND] Places fetch failed, falling back to direct Google: $e');
        // Fall through to direct-Google path.
      }
    }

    try {
      // ═══════════════════════════════════════
      // FOOD DISCOVERY — single Nearby Search.
      // Previously fanned out to restaurant + cafe + meal_takeaway in parallel,
      // which tripled the bill per Food tab open. Google's 'restaurant' type
      // already includes most cafes/takeaways, and the type-whitelist below
      // catches the rest from the broader result set.
      // ═══════════════════════════════════════
      if (categoryName == 'Food & Drink') {
        const int foodRadius = 10000; // 10km strict limit

        final response = await _dio.get(
          '$_baseUrl/place/nearbysearch/json',
          queryParameters: {
            'location': '$latitude,$longitude',
            'radius': foodRadius,
            'type': 'restaurant',
            'key': _apiKey,
          },
        );

        // Strict food types that Google assigns to genuine food places
        const foodTypeWhitelist = {
          'restaurant', 'cafe', 'food', 'bakery', 'bar',
          'meal_takeaway', 'meal_delivery',
        };

        final Map<String, dynamic> uniquePlaces = {};
        if (response.data['status'] == 'OK') {
          final results = response.data['results'] as List;
          for (final place in results) {
            final id = place['place_id'] ?? '';
            if (id.isEmpty || uniquePlaces.containsKey(id)) continue;

            final types = (place['types'] as List?)?.cast<String>() ?? [];
            final isFood = types.any((t) => foodTypeWhitelist.contains(t));

            if (isFood) {
              uniquePlaces[id] = place;
            }
          }
        }

        print('🍽 Food Discovery: ${uniquePlaces.length} verified food spots found');

        final models = uniquePlaces.values.map((place) => _placeToModel(
          place, latitude, longitude, categoryName,
        )).toList();

        models.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

        CacheService.saveUserData(cacheKey, json.encode(models.map((m) => (m as AttractionModel).toJson()).toList()));
        CacheService.saveUserData(tsKey, DateTime.now().millisecondsSinceEpoch.toString());

        return models;
      }

      // ═══════════════════════════════════════
      // INTELLIGENT BEACH DISCOVERY ENGINE
      // Fire query for keyword beach up to 50km
      // ═══════════════════════════════════════
      if (categoryName == 'Beach') {
        final int beachRadius = radius > 20000 ? radius : 50000;
        
        final response = await _dio.get(
          '$_baseUrl/place/nearbysearch/json',
          queryParameters: {
            'location': '$latitude,$longitude',
            'radius': beachRadius,
            'keyword': 'beach',
            'key': _apiKey,
          },
        );
        
        final Map<String, dynamic> uniquePlaces = {};
        if (response.data['status'] == 'OK') {
          final results = response.data['results'] as List;
          for (final place in results) {
            final id = place['place_id'] ?? '';
            if (id.isEmpty) continue;
            uniquePlaces[id] = place;
          }
        }
        
        print('🏖 Intelligent Beach Discovery: ${uniquePlaces.length} beaches found');
        
        final models = uniquePlaces.values.map((place) => _placeToModel(
          place, latitude, longitude, 'Nature',
        )).toList();
        
        models.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
        
        CacheService.saveUserData(cacheKey, json.encode(models.map((m) => (m as AttractionModel).toJson()).toList()));
        CacheService.saveUserData(tsKey, DateTime.now().millisecondsSinceEpoch.toString());
        return models;
      }

      // ═══════════════════════════════════════
      // STANDARD QUERY FOR OTHER CATEGORIES
      // ═══════════════════════════════════════
      String type = 'point_of_interest';
      if (categoryName != null && categoryTypeMap.containsKey(categoryName)) {
        type = categoryTypeMap[categoryName]!;
      }

      final response = await _dio.get(
        '$_baseUrl/place/nearbysearch/json',
        queryParameters: {
          'location': '$latitude,$longitude',
          'radius': radius,
          'type': type,
          'key': _apiKey,
          'rankby': 'prominence',
        },
      );

      if (response.data['status'] != 'OK' && response.data['status'] != 'ZERO_RESULTS') {
        print('❌ Google Places API Error: ${response.data['error_message'] ?? response.data['status']}');
      } else {
        print('✅ Google Places Success: ${response.data['status']} (${(response.data['results'] as List).length} results)');
      }

      final results = response.data['results'] as List;
      final models = results.take(40).map((place) => _placeToModel(
        place, latitude, longitude, categoryName,
      )).toList();

      // Cache the result
      CacheService.saveUserData(cacheKey, json.encode(models.map((m) => m.toJson()).toList()));
      CacheService.saveUserData(tsKey, DateTime.now().millisecondsSinceEpoch.toString());

      return models;
    } catch (e) {
      debugPrint('Google Places API error: $e');
      return [];
    }
  }

  /// Convert a raw Google Places JSON result into an AttractionModel
  static AttractionModel _placeToModel(
    dynamic place, double originLat, double originLng, String? categoryName,
  ) {
    final location = place['geometry']['location'];
    final double placeLat = (location['lat'] as num).toDouble();
    final double placeLng = (location['lng'] as num).toDouble();
    
    final distanceM = _calculateDistance(originLat, originLng, placeLat, placeLng);

    final photos = place['photos'] as List?;
    List<String> photoUrls = [];
    if (photos != null && photos.isNotEmpty) {
      final photoRef = photos[0]['photo_reference'];
      photoUrls = [
        '$_baseUrl/place/photo?maxwidth=800&photo_reference=$photoRef&key=$_apiKey'
      ];
    }

    final types = (place['types'] as List?)?.cast<String>() ?? [];
    String resolvedCategory = categoryName ?? _resolveCategoryFromTypes(types);

    return AttractionModel(
      id: place['place_id'] ?? '',
      name: place['name'] ?? 'Unknown',
      description: place['vicinity'] ?? '',
      latitude: placeLat,
      longitude: placeLng,
      categoryName: resolvedCategory,
      address: place['vicinity'] ?? '',
      rating: (place['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: place['user_ratings_total'] as int? ?? 0,
      photoUrls: photoUrls,
      tags: types,
      distanceM: distanceM,
      isActive: (place['business_status'] ?? 'OPERATIONAL') == 'OPERATIONAL',
      createdAt: DateTime.now(),
    );
  }

  /// Get the human-readable category from Google types
  static String _resolveCategoryFromTypes(List<String> types) {
    if (types.contains('lodging')) return 'Hotels';
    if (types.contains('restaurant') || types.contains('food') || types.contains('cafe') || types.contains('bar')) return 'Food & Drink';
    if (types.contains('park') || types.contains('campground') || types.contains('natural_feature')) return 'Nature';
    if (types.contains('tourist_attraction') || types.contains('museum')) return 'Attractions';
    if (types.contains('shopping_mall') || types.contains('store')) return 'Shopping';
    return 'Attractions';
  }

  /// Haversine distance in meters
  static double _calculateDistance(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;

  /// Hit the backend places endpoint. Backend handles Google calls + Redis
  /// caching, so identical requests from different users in the same tile
  /// share a single Google call for 7 days.
  ///
  /// Photo URLs in the response are backend-proxied (relative paths) — we
  /// expand them to absolute URLs here so CachedNetworkImage can load them.
  static Future<List<AttractionEntity>> _fetchFromBackend({
    required double latitude,
    required double longitude,
    String? categoryName,
    required int radius,
  }) async {
    final response = await _dio.get(
      '${ApiConstants.baseUrl}${ApiConstants.placesNearby}',
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        if (categoryName != null) 'category': categoryName,
        'radius': radius,
      },
    );

    final places = (response.data['places'] as List? ?? []);
    final source = response.data['source'] ?? 'google';
    debugPrint('🛰 [BACKEND] Places ${places.length} from $source');

    return places.map<AttractionEntity>((p) {
      final map = Map<String, dynamic>.from(p as Map);
      // Rewrite relative photo URLs to absolute so the image widget can fetch them.
      final photos = (map['photo_urls'] as List?)?.cast<String>() ?? const [];
      map['photo_urls'] = photos
          .map((u) => u.startsWith('http') ? u : '${ApiConstants.baseUrl}$u')
          .toList();
      return AttractionModel.fromJson(map);
    }).toList();
  }
}
