import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

/// Thrown when a places fetch fails for a real reason (network down, backend
/// 5xx, Google passthrough error) — as opposed to simply finding no places.
/// Lets the UI show a "couldn't load / retry" prompt instead of "none nearby".
class PlacesFetchException implements Exception {
  const PlacesFetchException();
  @override
  String toString() => 'PlacesFetchException';
}

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
    } on DioException catch (e) {
      // Log the backend's actual reply (status + body) so failures like a 500
      // from the Google Places passthrough (billing / API-not-enabled / key
      // restriction) are diagnosable instead of silently becoming "no places".
      debugPrint(
        '❌ Places fetch failed: status=${e.response?.statusCode} '
        'lat=$latitude lng=$longitude category=$categoryName '
        'body=${e.response?.data}',
      );
      // Re-throw as a typed marker so callers that care (AR) can tell a real
      // failure apart from a genuinely-empty result; callers that don't care
      // already wrap this in try/catch or catchError.
      throw const PlacesFetchException();
    } catch (e) {
      debugPrint('Error fetching nearby places from backend: $e');
      throw const PlacesFetchException();
    }
  }
}
