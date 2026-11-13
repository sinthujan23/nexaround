import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'dart:math' as math;

/// Service to fetch real place data from Mapbox Geocoding API
/// and reverse-geocode current location.
class MapboxGeocodingService {
  static final Dio _dio = Dio();
  static const String _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';
  static String get _accessToken => ApiConstants.mapboxAccessToken;

  /// Reverse-geocode lat/lng to a human-readable location name
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/$lng,$lat.json',
        queryParameters: {
          'access_token': _accessToken,
          'types': 'neighborhood,locality,place,address',
          'limit': 1,
        },
      );

      final features = response.data['features'] as List;
      if (features.isNotEmpty) {
        final feature = features[0];
        // Mapbox usually provides the name in the 'text' field
        return feature['text'] ?? feature['place_name']?.split(',')[0] ?? 'Nearby';
      }
      return 'Nearby';
    } catch (e) {
      debugPrint('Mapbox Reverse Geocode error: $e');
      return 'Nearby';
    }
  }

  /// The town or city at a point: `{name, region?}`, or null when Mapbox has
  /// no answer.
  ///
  /// [reverseGeocode] names the smallest thing it can, a neighbourhood or a
  /// street. This one names the city, for the Home chip after the traveller
  /// has moved the pin away from the place they searched for.
  static Future<Map<String, String>?> reverseCity(double lat, double lng) async {
    if (_accessToken.isEmpty) return null;
    try {
      final response = await _dio.get(
        '$_baseUrl/$lng,$lat.json',
        queryParameters: {
          'access_token': _accessToken,
          'types': 'place,locality,district,region',
          'language': 'en',
        },
      );

      final features = (response.data['features'] as List?) ?? const [];
      if (features.isEmpty) return null;

      // A level is either a feature of its own or a line in the first
      // feature's context ("place.123", "region.45").
      String? textOf(String type) {
        for (final f in features) {
          final types = (f['place_type'] as List?) ?? const [];
          final text = (f['text'] ?? '').toString().trim();
          if (types.contains(type) && text.isNotEmpty) return text;
        }
        final context = (features.first['context'] as List?) ?? const [];
        for (final c in context) {
          final id = (c['id'] ?? '').toString();
          final text = (c['text'] ?? '').toString().trim();
          if (id.startsWith('$type.') && text.isNotEmpty) return text;
        }
        return null;
      }

      final name = textOf('place') ??
          textOf('locality') ??
          textOf('district') ??
          textOf('region');
      if (name == null) return null;

      final region = textOf('region') ?? textOf('district');
      return {
        'name': name,
        if (region != null && region != name) 'region': region,
      };
    } catch (e) {
      debugPrint('Mapbox reverse city error: $e');
      return null;
    }
  }

  /// Fetch nearby places from Mapbox (using Geocoding API as a discovery tool)
  /// Note: Mapbox doesn't have a direct "Nearby Search" like Google, 
  /// so we use category-based geocoding.
  static Future<List<AttractionEntity>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String? categoryName,
    int radius = 5000,
  }) async {
    try {
      String query = 'point of interest';
      if (categoryName != null) {
        query = categoryName;
      }

      final response = await _dio.get(
        '$_baseUrl/$query.json',
        queryParameters: {
          'access_token': _accessToken,
          'proximity': '$longitude,$latitude',
          'types': 'poi',
          'limit': 20,
        },
      );

      final features = response.data['features'] as List;
      
      return features.map((feature) {
        final center = feature['center'] as List;
        final double placeLng = (center[0] as num).toDouble();
        final double placeLat = (center[1] as num).toDouble();
        
        final distanceM = _calculateDistance(
          latitude, longitude, placeLat, placeLng,
        );

        // Mapbox POI categories are in properties['category']
        final props = feature['properties'] as Map<String, dynamic>;
        String resolvedCategory = categoryName ?? props['category']?.split(',')[0] ?? 'Attractions';

        return AttractionModel(
          id: feature['id'] ?? '',
          name: feature['text'] ?? 'Unknown',
          description: feature['place_name'] ?? '',
          latitude: placeLat,
          longitude: placeLng,
          categoryName: resolvedCategory,
          address: feature['place_name'] ?? '',
          rating: 4.5, // Mapbox doesn't provide ratings in basic geocoding
          reviewCount: 120,
          photoUrls: [
             _getPlaceholderImage(resolvedCategory)
          ],
          distanceM: distanceM,
          isActive: true,
          createdAt: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Mapbox Discovery API error: $e');
      return [];
    }
  }

  static String _getPlaceholderImage(String category) {
    final c = category.toLowerCase();
    if (c.contains('food') || c.contains('rest')) return 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800';
    if (c.contains('hotel')) return 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800';
    if (c.contains('shop')) return 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800';
    return 'https://images.unsplash.com/photo-1533105079780-92b9be482077?w=800';
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + 
          math.cos(lat1 * p) * math.cos(lat2 * p) * 
          (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742000 * math.asin(math.sqrt(a));
  }
}
