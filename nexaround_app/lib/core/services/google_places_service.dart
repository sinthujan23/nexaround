import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
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
  static String lastAttractionsError = '';
  static String lastMedicalError = '';
  static String lastHospitalError = '';
  static String lastFoodError = '';
  static String lastShoppingError = '';
  static String lastNatureError = '';

  static void clearErrors() {
    lastAttractionsError = '';
    lastMedicalError = '';
    lastHospitalError = '';
    lastFoodError = '';
    lastShoppingError = '';
    lastNatureError = '';
  }

  static const Map<String, String> categoryTypeMap = {
    'Attractions': 'tourist_attraction',
    'Food & Drink': 'restaurant',
    'Shopping': 'shopping_mall',
    'Experiences': 'amusement_park',
    'Transport': 'transit_station',
    'Medical': 'hospital',
    'Hospital': 'hospital',
    'Nature': 'park',
  };

  /// Reverse-geocode lat/lng to a human-readable location name via Geoapify
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/proxy/geoapify/reverse',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      final name = response.data['location_name'] as String?;
      return (name != null && name.isNotEmpty) ? name : 'Nearby';
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      return 'Nearby';
    }
  }

  /// Reverse-geocode lat/lng to location name and district via Geoapify
  static Future<Map<String, String>> reverseGeocodeDetailed(
    double lat,
    double lng,
  ) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/proxy/geoapify/reverse',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      final name = response.data['location_name'] as String? ?? 'Nearby';
      final district = response.data['district'] as String? ?? 'Nearby';
      return {'location_name': name, 'district': district};
    } catch (e) {
      debugPrint('Reverse geocode detailed error: $e');
      return {'location_name': 'Nearby', 'district': 'Nearby'};
    }
  }

  /// Generates a Headout search URL for a given location, appending the city/district
  /// name to the query to ensure Headout finds relevant experiences instead of
  /// falling back to defaults like Vietnam/Singapore.
  static Future<Uri> getHeadoutSearchUri(
    double lat,
    double lng,
    String placeName,
  ) async {
    final details = await reverseGeocodeDetailed(lat, lng);
    final district = details['district'] ?? '';

    String query = placeName.trim();
    if (district.isNotEmpty && district != 'Nearby') {
      if (query.isNotEmpty) {
        query = '$query, $district';
      } else {
        query = district;
      }
    } else if (query.isEmpty) {
      query = '$lat,$lng';
    }

    return Uri.https('www.headout.com', '/search', {
      'q': query,
      'latitude': lat.toStringAsFixed(6),
      'longitude': lng.toStringAsFixed(6),
    });
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
        final models = placesList
            .map((p) => AttractionModel.fromJson(p))
            .toList();
        print(
          '✅ Places fetched from backend: ${models.length} items (Source: ${data['source']})',
        );
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
          final userRatingsTotal =
              (place['user_ratings_total'] as num?)?.toInt() ?? 0;

          final geom = place['geometry'] as Map<String, dynamic>?;
          final loc = geom != null
              ? geom['location'] as Map<String, dynamic>?
              : null;
          final plat = loc != null ? (loc['lat'] as num).toDouble() : latitude;
          final plng = loc != null ? (loc['lng'] as num).toDouble() : longitude;

          final distanceM = geo.Geolocator.distanceBetween(
            latitude,
            longitude,
            plat,
            plng,
          );

          // Map photo reference to our backend photo proxy URL
          final photos = place['photos'] as List? ?? [];
          final List<String> photoUrls = [];
          if (photos.isNotEmpty) {
            final ref = photos[0]['photo_reference'] as String?;
            if (ref != null && ref.isNotEmpty) {
              photoUrls.add('/api/v1/places/photo?ref=$ref');
            }
          }

          final typesList = (place['types'] as List? ?? [])
              .map((t) => t.toString())
              .toList();
          final resolvedCategory =
              categoryName ?? _resolveCategoryFromTypes(typesList);

          models.add(
            AttractionModel(
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
            ),
          );
        }
        print(
          '✅ Places fetched from Google Maps legacy API (Homepage): ${models.length} items',
        );
        return models;
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching nearby places from legacy Google API: $e');
      throw const PlacesFetchException();
    }
  }

  /// Helper to clean noise words like "near me", "nearby", or "near" from queries.
  static String _cleanSearchQuery(String query) {
    String cleaned = query.trim();
    final nearMeRegex = RegExp(r'\s+near\s+me\b', caseSensitive: false);
    final nearbyRegex = RegExp(r'\s+nearby\b', caseSensitive: false);
    final nearRegex = RegExp(r'\s+near\b', caseSensitive: false);
    
    cleaned = cleaned
        .replaceAll(nearMeRegex, '')
        .replaceAll(nearbyRegex, '')
        .replaceAll(nearRegex, '')
        .trim();
    return cleaned;
  }

  /// Search places by text query biased towards current coordinates (New API)
  static Future<List<AttractionEntity>> searchPlaces({
    required String query,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final cleanedQuery = _cleanSearchQuery(query);
      if (cleanedQuery.isEmpty) return [];

      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/search',
        queryParameters: {'query': cleanedQuery, 'lat': latitude, 'lng': longitude},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> placesList = data['places'] as List? ?? [];
        final models = placesList
            .map((p) => AttractionModel.fromJson(p))
            .toList();

        final filteredModels = models;

        // Sort by distance ascending
        filteredModels.sort((a, b) {
          final distA = a.distanceM ?? geo.Geolocator.distanceBetween(latitude, longitude, a.latitude, a.longitude);
          final distB = b.distanceM ?? geo.Geolocator.distanceBetween(latitude, longitude, b.latitude, b.longitude);
          return distA.compareTo(distB);
        });

        print(
          '✅ Places searched: ${filteredModels.length} items',
        );
        return filteredModels;
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
    final t = types.map((s) => s.toLowerCase()).join(' ');
    
    if (t.contains('hospital')) return 'Hospital';
    if (t.contains('clinic') || t.contains('pharmacy') || t.contains('doctor') || t.contains('medical')) return 'Medical';
    if (t.contains('mall') || t.contains('market') || t.contains('shop')) return 'Shopping';
    if (t.contains('restaurant') || t.contains('cafe') || t.contains('bakery') || t.contains('hotel') || t.contains('bar') || t.contains('lodging') || t.contains('food')) return 'Food & Drink';
    
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
      final encoded =
          (route['overview_polyline'] as Map?)?['points'] as String?;
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
    final cleanedInput = _cleanSearchQuery(input);
    if (cleanedInput.isEmpty) return [];

    try {
      // 1. Fetch autocomplete suggestions from Google (restricted to 15km)
      List<Map<String, dynamic>> autocompleteResults = [];
      try {
        final response = await ApiClient.instance.get(
          '${ApiConstants.googleMapsProxy}/place/autocomplete/json',
          queryParameters: {
            'input': cleanedInput,
            'location': '$latitude,$longitude',
            'radius': 15000, // 15km strict bound
            'strictbounds': true, // Only return results within the radius
            'origin': '$latitude,$longitude',
          },
        );

        if (response.statusCode == 200) {
          final data = response.data;
          final List<dynamic> predictions = data['predictions'] as List? ?? [];
          autocompleteResults = predictions
              .map(
                (p) => {
                  'description': p['description'] as String? ?? '',
                  'place_id': p['place_id'] as String? ?? '',
                  'main_text': (p['structured_formatting']?['main_text'] as String?) ?? '',
                  'distance_meters': p['distance_meters'] as num?,
                },
              )
              .toList();
        }
      } catch (e) {
        debugPrint('Autocomplete request error: $e');
      }

      // 2. Fetch semantic search results from our backend /places/search
      List<Map<String, dynamic>> searchResults = [];
      try {
        final response = await ApiClient.instance.get(
          '${ApiConstants.apiVersion}/places/search',
          queryParameters: {
            'query': cleanedInput,
            'lat': latitude,
            'lng': longitude,
          },
        );

        if (response.statusCode == 200) {
          final data = response.data;
          final List<dynamic> placesList = data['places'] as List? ?? [];
          for (final p in placesList) {
            final lat = (p['latitude'] as num?)?.toDouble();
            final lng = (p['longitude'] as num?)?.toDouble();
            double? distanceMeters;
            if (lat != null && lng != null) {
              distanceMeters = geo.Geolocator.distanceBetween(
                latitude,
                longitude,
                lat,
                lng,
              );
            }

            // Strictly filter out results further than 15km
            if (distanceMeters != null && distanceMeters > 15000) {
              continue;
            }

            searchResults.add({
              'description': p['address'] as String? ?? p['description'] as String? ?? '',
              'place_id': p['id'] as String? ?? '',
              'main_text': p['name'] as String? ?? '',
              'distance_meters': distanceMeters,
            });
          }
        }
      } catch (e) {
        debugPrint('Semantic text search error in suggestions: $e');
      }

      // 3. Merge results and deduplicate by place_id
      final Map<String, Map<String, dynamic>> merged = {};

      for (final item in autocompleteResults) {
        final id = item['place_id'] as String;
        if (id.isNotEmpty) {
          merged[id] = item;
        }
      }

      for (final item in searchResults) {
        final id = item['place_id'] as String;
        if (id.isNotEmpty) {
          if (!merged.containsKey(id)) {
            merged[id] = item;
          } else {
            // Update distance if semantic search has a more precise one
            if (item['distance_meters'] != null) {
              merged[id]!['distance_meters'] = item['distance_meters'];
            }
          }
        }
      }

      final mergedList = merged.values.toList();

      // 4. Sort by distance (closest first)
      mergedList.sort((a, b) {
        final distA = a['distance_meters'] as num?;
        final distB = b['distance_meters'] as num?;
        if (distA != null && distB != null) return distA.compareTo(distB);
        if (distA != null) return -1;
        if (distB != null) return 1;
        return 0;
      });

      return mergedList;
    } catch (e) {
      debugPrint('Autocomplete main error: $e');
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
          final loc = geom != null
              ? geom['location'] as Map<String, dynamic>?
              : null;
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

  /// Find a place by name, biased towards the user's location, using Google's Find Place API.
  static Future<AttractionEntity?> findPlaceByName({
    required String name,
    required double userLat,
    required double userLng,
    String? categoryName,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/findplacefromtext/json',
        queryParameters: {
          'input': name,
          'inputtype': 'textquery',
          'fields': 'place_id,name,geometry,rating,user_ratings_total,photos,formatted_address,types',
          'locationbias': 'circle:50000@$userLat,$userLng',
        },
      );

      if (response.statusCode == 200) {
        final candidates = response.data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates[0] as Map<String, dynamic>;
          final placeId = candidate['place_id'] as String? ?? '';
          final placeName = candidate['name'] as String? ?? name;
          final rating = (candidate['rating'] as num?)?.toDouble() ?? 4.0;
          final userRatingsTotal = (candidate['user_ratings_total'] as num?)?.toInt() ?? 0;

          final geom = candidate['geometry'] as Map<String, dynamic>?;
          final loc = geom != null ? geom['location'] as Map<String, dynamic>? : null;
          final plat = loc != null ? (loc['lat'] as num).toDouble() : userLat;
          final plng = loc != null ? (loc['lng'] as num).toDouble() : userLng;

          final distanceM = geo.Geolocator.distanceBetween(
            userLat,
            userLng,
            plat,
            plng,
          );

          // Map photo reference to our backend photo proxy URL
          final photos = candidate['photos'] as List? ?? [];
          final List<String> photoUrls = [];
          if (photos.isNotEmpty) {
            final ref = photos[0]['photo_reference'] as String?;
            if (ref != null && ref.isNotEmpty) {
              photoUrls.add('/api/v1/places/photo?ref=$ref');
            }
          }

          final typesList = (candidate['types'] as List? ?? [])
              .map((t) => t.toString())
              .toList();
          final resolvedCategory =
              categoryName ?? _resolveCategoryFromTypes(typesList);

          return AttractionModel(
            id: placeId,
            name: placeName,
            description: candidate['formatted_address'] as String? ?? '',
            latitude: plat,
            longitude: plng,
            categoryId: null,
            categoryName: resolvedCategory,
            address: candidate['formatted_address'] as String? ?? '',
            openingHours: const {},
            entryFee: 0.0,
            currency: 'USD',
            rating: rating,
            reviewCount: userRatingsTotal,
            photoUrls: photoUrls,
            tags: typesList.isNotEmpty
                ? typesList
                : (categoryName != null
                    ? [
                        categoryName.toLowerCase(),
                        if (categoryName.toLowerCase().contains('food')) 'food',
                        if (categoryName.toLowerCase().contains('shop')) 'shopping_mall',
                      ]
                    : const []),
            geofenceRadiusM: 100,
            distanceM: distanceM,
            isActive: true,
            createdAt: DateTime.now(),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error finding place by name "$name": $e');
      return null;
    }
  }

  /// Fetch places using a hybrid Gemini AI + Google Places Find Place approach.
  /// Calls Gemini to get a curated list of prominent places for a category,
  /// then resolves their details using parallel Find Place text queries.
  static Future<List<AttractionEntity>> fetchHybridPlaces({
    required double latitude,
    required double longitude,
    required String categoryName,
    required String locationName,
  }) async {
    try {
      if (categoryName == 'Attractions') lastAttractionsError = '';
      if (categoryName == 'Medical') lastMedicalError = '';
      if (categoryName == 'Hospital') lastHospitalError = '';
      if (categoryName == 'Food & Drink') lastFoodError = '';
      if (categoryName == 'Shopping') lastShoppingError = '';
      if (categoryName == 'Nature') lastNatureError = '';

      final threshold = 15;

      // Check all cached hybrid places for the given category across all locations within the appropriate radius
      final allCached = CacheService.getAllCachedHybridPlacesForCategory(categoryName);
      final List<AttractionModel> nearbyCached = [];
      final double searchRadiusM;
      if (categoryName == 'Attractions' || categoryName == 'Hospital') {
        searchRadiusM = 50000.0;
      } else if (categoryName == 'Food & Drink') {
        searchRadiusM = 5000.0;
      } else {
        searchRadiusM = 15000.0;
      }
      for (final json in allCached) {
        final model = AttractionModel.fromJson(json);
        final distM = geo.Geolocator.distanceBetween(
          latitude,
          longitude,
          model.latitude,
          model.longitude,
        );
        if (distM <= searchRadiusM) {
          nearbyCached.add(model);
        }
      }

      // Check if we have enough places to satisfy the request without calling APIs
      if (nearbyCached.length >= threshold) {
        print('⚡ Found enough (${nearbyCached.length} >= $threshold) cached places within ${searchRadiusM / 1000}km for $categoryName. Skipping API call.');
        
        // Update distances relative to current user coordinates
        return nearbyCached.map((m) {
          final distM = geo.Geolocator.distanceBetween(
            latitude,
            longitude,
            m.latitude,
            m.longitude,
          );
          return AttractionModel(
            id: m.id,
            name: m.name,
            description: m.description,
            history: m.history,
            latitude: m.latitude,
            longitude: m.longitude,
            categoryId: m.categoryId,
            categoryName: m.categoryName,
            address: m.address,
            openingHours: m.openingHours,
            entryFee: m.entryFee,
            currency: m.currency,
            rating: m.rating,
            reviewCount: m.reviewCount,
            photoUrls: m.photoUrls,
            tags: m.tags,
            geofenceRadiusM: m.geofenceRadiusM,
            distanceM: distM,
            isActive: m.isActive,
            createdAt: m.createdAt,
          );
        }).toList();
      }

      final gemini = GeminiService();
      String prompt = '';
      if (categoryName == 'Medical') {
        prompt = '''
Analyse and provide a list of up to 15 real medical locations (pharmacies, dental clinics, health centers, optical clinics, veterinary clinics, or general medical clinics) within a radius of 15 kms from ($latitude, $longitude) near $locationName.
Do NOT include any places that are not related to medical services (do not list landmarks, schools, banks, police stations, or general stores). If there are fewer than 15 medical locations in this area, return only the ones that actually exist.

Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Medical Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else if (categoryName == 'Hospital') {
        prompt = '''
Analyse and provide a list of up to 15 real hospital and multi-speciality hospital locations within a radius of 50 kms from ($latitude, $longitude) near $locationName. 
Do NOT include any places that are not hospitals, clinics, or medical centers (do not list landmarks, police stations, shops, schools, parks, or banks). If there are fewer than 15 hospitals in this area, return only the ones that actually exist.

Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Hospital Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else if (categoryName == 'Attractions') {
        prompt = '''
Analyse and provide a list for the following categories upto 15 most important places within a radius of 50 kms from ($latitude, $longitude) near $locationName with distance and direction. 

tourist_attraction, historical_landmark, beach, museum, park, zoo, aquarium, art_gallery, amusement_park, religious_places, casino, movie_theater, bowling_alley, campground, national_park, botanical_garden



Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Attraction Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else if (categoryName == 'Food & Drink') {
        prompt = '''
Analyse and provide a list for the following categories upto 15 most important places within a radius of 5 kms from ($latitude, $longitude) near $locationName with distance and direction. 

restaurant, cafe, bakery, meal_delivery, hotel, bar, night_club, ice_cream_shop, coffee_shop, diner


Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Food_Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else if (categoryName == 'Shopping') {
        prompt = '''
Analyse and provide a list for the following categories upto 15 most important places within a radius of 15 kms from ($latitude, $longitude) near $locationName with distance and direction. 

shopping_mall, supermarket, market, general_store, department_store, convenience_store, clothing_store, electronics_store, book_store, jewelry_store, shoe_store, furniture_store, pet_store, hardware_store, gift_shop, 


Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Shopping_Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else if (categoryName == 'Nature') {
        prompt = '''
Analyse and provide a list for the following categories upto 15 most important places within a radius of 15 kms from ($latitude, $longitude) near $locationName with distance and direction. 

beach, national_park, hiking_area, nature_reserve, scenic_viewpoint, waterfall, lake, river, botanical_garden


Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {
    "name": "Nature Spot Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }
]
''';
      } else {
        return [];
      }

      print('🤖 Prompting Gemini for category $categoryName near $locationName ($latitude, $longitude)...');
      final rawResponse = await gemini.getResponse(
        prompt,
      );

      // Clean the response from markdown block codes robustly by finding [ and ]
      final firstBracket = rawResponse.indexOf('[');
      final lastBracket = rawResponse.lastIndexOf(']');
      if (firstBracket == -1 || lastBracket == -1 || lastBracket <= firstBracket) {
        final errMsg = 'Format error: Missing JSON array. Response starts with: ${rawResponse.substring(0, math.min(100, rawResponse.length))}';
        if (categoryName == 'Attractions') lastAttractionsError = errMsg;
        if (categoryName == 'Medical') lastMedicalError = errMsg;
        if (categoryName == 'Hospital') lastHospitalError = errMsg;
        if (categoryName == 'Food & Drink') lastFoodError = errMsg;
        if (categoryName == 'Shopping') lastShoppingError = errMsg;
        if (categoryName == 'Nature') lastNatureError = errMsg;
        throw FormatException('Could not find JSON array in Gemini response. Response was: $rawResponse');
      }
      final cleanJson = rawResponse.substring(firstBracket, lastBracket + 1).trim();

      final List<dynamic> decoded = jsonDecode(cleanJson);
      final List<Future<AttractionEntity?>> futures = [];

      // Get detailed geocoded district/city for query input biasing
      String biasRegion = 'Nearby';
      try {
        final detailed = await reverseGeocodeDetailed(latitude, longitude);
        final distStr = detailed['district'];
        if (distStr != null && distStr != 'Nearby' && distStr.trim().isNotEmpty) {
          biasRegion = distStr.trim();
        } else {
          final locStr = detailed['location_name'];
          if (locStr != null && locStr != 'Nearby' && locStr.trim().isNotEmpty) {
            biasRegion = locStr.trim();
          }
        }
      } catch (_) {}

      for (final item in decoded) {
        final name = item['name'] as String?;
        if (name != null && name.isNotEmpty) {
          final queryInput = (biasRegion != 'Nearby' &&
                  !name.toLowerCase().contains(biasRegion.toLowerCase()))
              ? '$name, $biasRegion'
              : name;
          futures.add(
            findPlaceByName(
              name: queryInput,
              userLat: latitude,
              userLng: longitude,
              categoryName: categoryName,
            ),
          );
        }
      }

      print('🔍 Resolving ${futures.length} places in parallel using findplacefromtext...');
      final results = await Future.wait(futures);
      final List<AttractionEntity> resolvedPlaces = results
          .whereType<AttractionEntity>()
          .where((p) => (p as AttractionModel).distanceM! <= searchRadiusM)
          .toList();

      if (resolvedPlaces.isEmpty) {
        final errMsg = 'No places could be geocoded by Google Places API.';
        if (categoryName == 'Attractions') lastAttractionsError = errMsg;
        if (categoryName == 'Medical') lastMedicalError = errMsg;
        if (categoryName == 'Hospital') lastHospitalError = errMsg;
        if (categoryName == 'Food & Drink') lastFoodError = errMsg;
        if (categoryName == 'Shopping') lastShoppingError = errMsg;
        if (categoryName == 'Nature') lastNatureError = errMsg;
      }

      // 2. Cache the resolved places
      if (resolvedPlaces.isNotEmpty) {
        final placesJson = resolvedPlaces.map((e) => (e as AttractionModel).toJson()).toList();
        await CacheService.cacheHybridPlaces(locationName, categoryName, placesJson);
        print('💾 Cached ${resolvedPlaces.length} hybrid places for $locationName - $categoryName');
      }

      return resolvedPlaces;
    } catch (e) {
      print('❌ Exception fetching hybrid places: $e');
      final errMsg = 'Error: $e';
      if (categoryName == 'Attractions') lastAttractionsError = errMsg;
      if (categoryName == 'Medical') lastMedicalError = errMsg;
      if (categoryName == 'Hospital') lastHospitalError = errMsg;
      if (categoryName == 'Food & Drink') lastFoodError = errMsg;
      if (categoryName == 'Shopping') lastShoppingError = errMsg;
      if (categoryName == 'Nature') lastNatureError = errMsg;
      return [];
    }
  }
}
