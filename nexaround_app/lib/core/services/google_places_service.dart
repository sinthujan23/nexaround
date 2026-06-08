import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:geolocator/geolocator.dart' as geo;

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
    bool useLegacy = false,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/nearby',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'category': categoryName,
          'radius': radius,
          'use_legacy': useLegacy,
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

  /// Fetch nearby places from legacy Google Places API via secure proxy (specifically for homepage)
  static Future<List<AttractionEntity>> fetchNearbyPlacesLegacy({
    required double latitude,
    required double longitude,
    String? categoryName,
    int radius = 5000,
  }) async {
    try {
      final type = categoryTypeMap[categoryName];
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/nearbysearch/json',
        queryParameters: {
          'location': '$latitude,$longitude',
          'radius': radius,
          if (type != null) 'type': type,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> results = data['results'] as List? ?? [];
        final List<AttractionModel> models = [];
        
        for (final place in results) {
          final placeId = place['place_id'] as String? ?? '';
          final name = place['name'] as String? ?? 'Unknown';
          final rating = (place['rating'] as num?)?.toDouble() ?? 4.0;
          final userRatingsTotal = (place['user_ratings_total'] as num?)?.toInt() ?? 0;
          
          final geom = place['geometry'] as Map<String, dynamic>?;
          final loc = geom != null ? geom['location'] as Map<String, dynamic>? : null;
          final plat = loc != null ? (loc['lat'] as num).toDouble() : latitude;
          final plng = loc != null ? (loc['lng'] as num).toDouble() : longitude;
          
          final distanceM = geo.Geolocator.distanceBetween(latitude, longitude, plat, plng);
          
          // Map photo reference to our backend photo proxy URL
          final photos = place['photos'] as List? ?? [];
          final List<String> photoUrls = [];
          if (photos.isNotEmpty) {
            final ref = photos[0]['photo_reference'] as String?;
            if (ref != null && ref.isNotEmpty) {
              photoUrls.add('/api/v1/places/photo?ref=$ref');
            }
          }
          
          final typesList = (place['types'] as List? ?? []).map((t) => t.toString()).toList();
          final resolvedCategory = categoryName ?? _resolveCategoryFromTypes(typesList);
          
          models.add(AttractionModel(
            id: placeId,
            name: name,
            description: place['vicinity'] as String? ?? '',
            latitude: plat,
            longitude: plng,
            categoryId: null,
            categoryName: resolvedCategory,
            address: place['vicinity'] as String? ?? '',
            openingHours: const {},
            entryFee: 0.0,
            currency: 'USD',
            rating: rating,
            reviewCount: userRatingsTotal,
            photoUrls: photoUrls,
            tags: typesList,
            geofenceRadiusM: 100,
            distanceM: distanceM,
            isActive: true,
            createdAt: DateTime.now(),
          ));
        }
        print('✅ Places fetched from Google Maps legacy API (Homepage): ${models.length} items');
        return models;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching nearby places from legacy Google API: $e');
      throw const PlacesFetchException();
    }
  }

  /// Search places by text query biased towards current coordinates (New API)
  static Future<List<AttractionEntity>> searchPlaces({
    required String query,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/search',
        queryParameters: {
          'query': query,
          'lat': latitude,
          'lng': longitude,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> placesList = data['places'] as List? ?? [];
        final models = placesList.map((p) => AttractionModel.fromJson(p)).toList();
        print('✅ Places searched: ${models.length} items (Source: ${data['source']})');
        return models;
      }
      return [];
    } on DioException catch (e) {
      debugPrint(
        '❌ Places search failed: status=${e.response?.statusCode} '
        'query=$query lat=$latitude lng=$longitude '
        'body=${e.response?.data}',
      );
      throw const PlacesFetchException();
    } catch (e) {
      debugPrint('Error searching places from backend: $e');
      throw const PlacesFetchException();
    }
  }

  static String _resolveCategoryFromTypes(List<String> types) {
    final t = types.toSet();
    if (t.intersection({'lodging', 'hotel', 'motel', 'resort_hotel', 'hostel', 'guest_house', 'bed_and_breakfast'}).isNotEmpty) {
      return 'Hotels';
    }
    if (t.intersection({'restaurant', 'food', 'cafe', 'bar', 'coffee_shop', 'bakery', 'fast_food_restaurant', 'food_court', 'pub', 'wine_bar'}).isNotEmpty) {
      return 'Food & Drink';
    }
    if (t.intersection({'park', 'campground', 'natural_feature', 'beach', 'national_park', 'hiking_area', 'garden', 'zoo'}).isNotEmpty) {
      return 'Nature';
    }
    if (t.intersection({'hospital', 'pharmacy', 'medical_clinic', 'dentist'}).isNotEmpty) {
      return 'Medical';
    }
    if (t.intersection({'tourist_attraction', 'museum', 'art_gallery', 'historical_landmark', 'place_of_worship', 'church', 'hindu_temple', 'mosque', 'synagogue', 'buddhist_temple', 'amusement_park', 'aquarium', 'cultural_center'}).isNotEmpty) {
      return 'Attractions';
    }
    if (t.intersection({'shopping_mall', 'store', 'department_store', 'clothing_store', 'supermarket', 'grocery_store', 'convenience_store', 'gift_shop', 'book_store', 'electronics_store', 'jewelry_store', 'shoe_store'}).isNotEmpty) {
      return 'Shopping';
    }
    return 'Attractions';
  }

  /// Get driving directions between two coordinates.
  /// Returns a map with keys: 'polyline' (List<LatLng>), 'duration_seconds' (double), 'distance_meters' (double).
  /// Returns null on failure so callers can fall back gracefully.
  static Future<Map<String, dynamic>?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String profile = 'driving',
  }) async {
    try {
      // Use Google Directions so the distance/route matches what users see in
      // Google Maps (Mapbox was returning longer, less-accurate routes locally).
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/directions/json',
        queryParameters: {
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
          'mode': profile, // driving | walking | bicycling | transit
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes[0] as Map<String, dynamic>;
      final legs = route['legs'] as List?;
      if (legs == null || legs.isEmpty) return null;
      final leg = legs[0] as Map<String, dynamic>;

      final distanceM =
          ((leg['distance'] as Map?)?['value'] as num?)?.toDouble() ?? 0.0;
      final durationSec =
          ((leg['duration'] as Map?)?['value'] as num?)?.toDouble() ?? 0.0;
      final encoded = (route['overview_polyline'] as Map?)?['points'] as String?;
      final points = (encoded != null && encoded.isNotEmpty)
          ? _decodePolyline(encoded)
          : <LatLng>[];

      return {
        'polyline': points,
        'duration_seconds': durationSec,
        'distance_meters': distanceM,
      };
    } catch (e) {
      debugPrint('getDirections error: $e');
      return null;
    }
  }

  /// Decodes a Google "encoded polyline" string into LatLng points so the route
  /// line drawn on the map matches the Google Directions geometry.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Get place suggestions/autocomplete from Google Places API via secure proxy
  static Future<List<Map<String, dynamic>>> getAutocompleteSuggestions({
    required String input,
    required double latitude,
    required double longitude,
  }) async {
    if (input.isEmpty) return [];
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/autocomplete/json',
        queryParameters: {
          'input': input,
          'location': '$latitude,$longitude',
          'radius': 10000, // 10km bias
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> predictions = data['predictions'] as List? ?? [];
        return predictions.map((p) => {
          'description': p['description'] as String? ?? '',
          'place_id': p['place_id'] as String? ?? '',
          'main_text': (p['structured_formatting']?['main_text'] as String?) ?? '',
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Autocomplete error: $e');
      return [];
    }
  }

  /// Get place details (lat/lng/name) by place_id
  static Future<AttractionEntity?> getPlaceDetails(String placeId) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'name,geometry,formatted_address',
        },
      );

      if (response.statusCode == 200) {
        final result = response.data['result'] as Map<String, dynamic>?;
        if (result != null) {
          final name = result['name'] as String? ?? 'Unknown';
          final geom = result['geometry'] as Map<String, dynamic>?;
          final loc = geom != null ? geom['location'] as Map<String, dynamic>? : null;
          final lat = loc != null ? (loc['lat'] as num).toDouble() : 0.0;
          final lng = loc != null ? (loc['lng'] as num).toDouble() : 0.0;
          final address = result['formatted_address'] as String? ?? '';

          return AttractionModel(
            id: placeId,
            name: name,
            description: address,
            latitude: lat,
            longitude: lng,
            categoryId: null,
            categoryName: 'Attractions',
            address: address,
            openingHours: const {},
            entryFee: 0.0,
            currency: 'USD',
            rating: 4.0,
            reviewCount: 0,
            photoUrls: const [],
            tags: const [],
            geofenceRadiusM: 100,
            distanceM: 0,
            isActive: true,
            createdAt: DateTime.now(),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Place Details error: $e');
      return null;
    }
  }
}

