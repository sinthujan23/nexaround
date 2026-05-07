import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

/// Service to fetch real place data from Google Maps Places API
/// and reverse-geocode current location.
class GooglePlacesService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';
  static const String _apiKey = ApiConstants.googleMapsApiKey;

  // Google Places type mapping for our categories
  static const Map<String, String> categoryTypeMap = {
    'Attractions': 'tourist_attraction',
    'Food & Drink': 'restaurant',
    'Hotels': 'lodging',
    'Shopping': 'shopping_mall',
    'Experiences': 'amusement_park',
    'Transport': 'transit_station',
  };

  /// Reverse-geocode lat/lng to a human-readable location name
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': _apiKey,
          // Removed result_type to get EVERYTHING including specific premises/neighborhoods
        },
      );

      if (response.data['status'] != 'OK' && response.data['status'] != 'ZERO_RESULTS') {
        print('❌ Google Reverse Geocode API Error: ${response.data['error_message'] ?? response.data['status']}');
        print('Full Response Body: ${response.data}');
      } else {
        print('✅ Google Reverse Geocode Success: ${response.data['status']}');
      }

      final results = response.data['results'] as List;
      if (results.isNotEmpty) {
        String? sublocality;
        String? neighborhood;
        String? locality;
        String? city;

        // 1. UBER/PICKME STYLE SEARCH: Look for Neighborhood or Sublocality first
        for (var result in results) {
          final components = result['address_components'] as List;
          for (final comp in components) {
            final types = (comp['types'] as List).cast<String>();
            
            // Priority Types for high-specificity (Like Uber/PickMe)
            if (types.contains('neighborhood') || 
                types.contains('sublocality_level_1') ||
                types.contains('sublocality') ||
                types.contains('premise') ||
                types.contains('point_of_interest')) {
              
              final name = comp['long_name'];
              if (name != null && name.isNotEmpty) {
                print('🚀 PICKME STYLE LOCATION: $name');
                return name;
              }
            }
          }
        }

        // 2. TOWN/CITY SEARCH: If neighborhood is missing, look for Locality
        for (var result in results) {
          final components = result['address_components'] as List;
          for (final comp in components) {
            final types = (comp['types'] as List).cast<String>();
            if (types.contains('locality') || types.contains('administrative_area_level_3')) {
              final name = comp['long_name'];
              if (name != null && name.isNotEmpty) {
                print('📍 TOWN FOUND: $name');
                return name;
              }
            }
          }
        }

        // 3. FINAL FALLBACK: Street Name or District
        final fallback = results[0]['formatted_address']?.split(',')[0];
        if (fallback != null && fallback.isNotEmpty) return fallback;
        
        return 'Nearby';
      }
      return 'Nearby';
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      return 'Nearby';
    }
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
    
    // Check Cache
    final cachedData = CacheService.getUserData(cacheKey);
    if (cachedData != null) {
      try {
        final List<dynamic> decoded = json.decode(cachedData);
        final cachedModels = decoded.map((p) => AttractionModel.fromJson(p)).toList();
        debugPrint('🚀 [CACHE] Instant Places Load: ${cachedModels.length} items');
        
        // Return cache but still fire background refresh to keep it fresh
        _refreshPlacesInBackground(latitude, longitude, categoryName, radius, cacheKey);
        return cachedModels;
      } catch (e) {
        debugPrint('[CACHE] Places Error: $e');
      }
    }

    return _performFetchNearby(latitude, longitude, categoryName, radius, cacheKey);
  }

  static void _refreshPlacesInBackground(double lat, double lng, String? cat, int rad, String key) async {
    try {
      final fresh = await _performFetchNearby(lat, lng, cat, rad, key);
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
  ) async {
    try {
      // ═══════════════════════════════════════
      // INTELLIGENT FOOD DISCOVERY ENGINE
      // Fire multiple parallel queries to capture every food spot
      // ═══════════════════════════════════════
      if (categoryName == 'Food & Drink') {
        const int foodRadius = 10000; // 10km strict limit
        final foodTypes = ['restaurant', 'cafe', 'meal_takeaway'];
        
        // Fire all 3 queries in parallel for speed
        final futures = foodTypes.map((type) => _dio.get(
          '$_baseUrl/place/nearbysearch/json',
          queryParameters: {
            'location': '$latitude,$longitude',
            'radius': foodRadius,
            'type': type,
            'key': _apiKey,
          },
        ));
        
        final responses = await Future.wait(futures);
        
        // Merge all results and deduplicate by place_id
        final Map<String, dynamic> uniquePlaces = {};
        
        // Strict food types that Google assigns to genuine food places
        const foodTypeWhitelist = {
          'restaurant', 'cafe', 'food', 'bakery', 'bar',
          'meal_takeaway', 'meal_delivery',
        };
        
        for (final response in responses) {
          if (response.data['status'] == 'OK') {
            final results = response.data['results'] as List;
            for (final place in results) {
              final id = place['place_id'] ?? '';
              if (id.isEmpty || uniquePlaces.containsKey(id)) continue;
              
              // STRICT VALIDATION: Only accept if Google types contain a food type
              final types = (place['types'] as List?)?.cast<String>() ?? [];
              final isFood = types.any((t) => foodTypeWhitelist.contains(t));
              
              if (isFood) {
                uniquePlaces[id] = place;
              }
            }
          }
        }
        
        print('🍽 Intelligent Food Discovery: ${uniquePlaces.length} verified food spots found');
        
        // Convert to models, calculate distance, sort by proximity
        final models = uniquePlaces.values.map((place) => _placeToModel(
          place, latitude, longitude, categoryName,
        )).toList();
        
        // Sort by distance (nearest first)
        models.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
        
        // Cache the result (as JSON strings of models)
        CacheService.saveUserData(cacheKey, json.encode(models.map((m) => (m as AttractionModel).toJson()).toList()));
        
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
      distanceM: distanceM,
      isActive: (place['business_status'] ?? 'OPERATIONAL') == 'OPERATIONAL',
      createdAt: DateTime.now(),
    );
  }

  /// Get the human-readable category from Google types
  static String _resolveCategoryFromTypes(List<String> types) {
    if (types.contains('lodging')) return 'Hotels';
    if (types.contains('restaurant') || types.contains('food') || types.contains('cafe') || types.contains('bar')) return 'Food & Drink';
    if (types.contains('tourist_attraction') || types.contains('museum') || types.contains('park')) return 'Attractions';
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
}
