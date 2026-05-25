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

  /// Reverse-geocode lat/lng to a human-readable location name via Geoapify
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/proxy/geoapify/reverse',
        queryParameters: {
          'lat': lat,
          'lng': lng,
        },
      );
      final name = response.data['location_name'] as String?;
      return (name != null && name.isNotEmpty) ? name : 'Nearby';
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
        '${ApiConstants.apiVersion}/places/nearby',
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
