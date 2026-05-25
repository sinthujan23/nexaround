import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

/// Service to fetch real place data from Google Maps Places API
/// and reverse-geocode current location via backend proxy.
class GooglePlacesService {
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

  /// Reverse-geocode lat/lng to a human-readable location name
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
        },
      );

      if (response.data['status'] != 'OK' && response.data['status'] != 'ZERO_RESULTS') {
        print('❌ Google Reverse Geocode API Error: ${response.data['error_message'] ?? response.data['status']}');
        print('Full Response Body: ${response.data}');
      } else {
        print('Base API Reverse Geocode Success: ${response.data['status']}');
      }

      final results = response.data['results'] as List;
      if (results.isNotEmpty) {
        // Look for Neighborhood or Sublocality first (high specificity)
        for (var result in results) {
          final components = result['address_components'] as List;
          for (final comp in components) {
            final types = (comp['types'] as List).cast<String>();
            
            if (types.contains('neighborhood') || 
                types.contains('sublocality_level_1') ||
                types.contains('sublocality') ||
                types.contains('premise') ||
                types.contains('point_of_interest')) {
              
              final name = comp['long_name'];
              if (name != null && name.isNotEmpty) {
                print('🚀 SPECIFIC LOCALITY: $name');
                return name;
              }
            }
          }
        }

        // Town/city search
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

  /// Fetch nearby places from backend cached Places API
  static Future<List<AttractionEntity>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String? categoryName,
    int radius = 5000,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '/places/nearby',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'category': categoryName,
          'radius': radius,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> placesList = data['places'] as List? ?? [];
        final models = placesList.map((p) => AttractionModel.fromJson(p)).toList();
        print('✅ Places fetched from backend: ${models.length} items (Source: ${data['source']})');
        return models;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching nearby places from backend: $e');
      return [];
    }
  }
}
