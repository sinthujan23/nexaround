import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
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

/// Result of a banded-places fetch: the bands themselves, plus whether a
/// farther band came up short and is still being filled in the background.
/// `pending: true` tells the caller this is the fast, near-band-only answer —
/// worth asking again shortly to pick up what the background fill adds.
class BandedFetchResult {
  final List<List<AttractionEntity>> bands;
  final bool pending;
  const BandedFetchResult({required this.bands, required this.pending});
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

  /// Last fetch error for a section, or '' if its last fetch was fine.
  ///
  /// Saves every empty-state widget from knowing which of the six fields backs
  /// which section — an if-chain that quietly stopped covering half of them.
  static String lastErrorFor(String category) {
    switch (category) {
      case 'Food':
      case 'Food & Drink':
        return lastFoodError;
      case 'POI':
      case 'Attractions':
        return lastAttractionsError;
      case 'Nature':
      case 'Beach':
        return lastNatureError;
      case 'Shopping':
        return lastShoppingError;
      case 'Medical':
        return lastMedicalError;
      case 'Hospital':
        return lastHospitalError;
      default:
        return '';
    }
  }

  static const Map<String, String> categoryTypeMap = {
    'POI': 'tourist_attraction',
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
      final country = response.data['country'] as String? ?? 'Nearby';
      return {
        'location_name': name,
        'district': district,
        'country': country,
      };
    } catch (e) {
      debugPrint('Reverse geocode detailed error: $e');
      return {
        'location_name': 'Nearby',
        'district': 'Nearby',
        'country': 'Nearby',
      };
    }
  }

  static final Map<String, List<AttractionEntity>> _clientCache = {};
  static final Map<String, DateTime> _clientCacheExpiry = {};

  static String _buildClientCacheKey(double lat, double lng, String? categoryName, int radius) {
    // Snap coordinates to 3 decimal places (~100m grid) for client-side debouncing
    final sLat = lat.toStringAsFixed(3);
    final sLng = lng.toStringAsFixed(3);
    final cat = (categoryName ?? 'all').toLowerCase();
    return '$sLat:$sLng:$cat:$radius';
  }

  /// Fetch one Around You / Discovery section, already split into distance
  /// bands by the backend.
  ///
  /// Returns one list per band, nearest band first, backfilled when a band is
  /// genuinely empty. [perBand] sets how deep each band goes; omitted, the
  /// backend applies its own quotas.
  ///
  /// Prefer this over [fetchNearbyPlaces] for the category sections: a plain
  /// radius query returns whatever is closest, and the outer bands stay empty
  /// however large the radius, because Google ranks its twenty results by
  /// prominence around the centre.
  static Future<BandedFetchResult> fetchBandedPlaces({
    required double latitude,
    required double longitude,
    required String categoryName,
    bool forceRefresh = false,
    int? perBand,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/nearby/banded',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'category': categoryName,
          if (forceRefresh) 'force_refresh': true,
          if (perBand != null) 'per_band': perBand,
        },
      );

      if (response.statusCode != 200) {
        return const BandedFetchResult(bands: [], pending: false);
      }

      final data = response.data;
      final bands = (data['bands'] as List? ?? [])
          .map((b) => ((b as Map)['places'] as List? ?? [])
              .map((p) => AttractionModel.fromJson(p) as AttractionEntity)
              .toList())
          .toList();
      final pending = data['pending'] as bool? ?? false;

      final total = bands.fold<int>(0, (sum, b) => sum + b.length);
      debugPrint(
        '✅ Banded places for $categoryName: $total across ${bands.length} bands '
        '(${bands.map((b) => b.length).join('/')}) source=${data['source']} '
        'pending=$pending',
      );
      return BandedFetchResult(bands: bands, pending: pending);
    } on DioException catch (e) {
      final msg = 'status=${e.response?.statusCode} body=${e.response?.data}';
      debugPrint('❌ Banded places fetch failed for $categoryName: $msg');
      _recordCategoryError(categoryName, 'Could not load $categoryName nearby.');
      return const BandedFetchResult(bands: [], pending: false);
    } catch (e) {
      debugPrint('❌ Banded places fetch error for $categoryName: $e');
      return const BandedFetchResult(bands: [], pending: false);
    }
  }

  static void _recordCategoryError(String categoryName, String message) {
    switch (categoryName) {
      case 'Medical':
        lastMedicalError = message;
        break;
      case 'Hospital':
        lastHospitalError = message;
        break;
      case 'Food & Drink':
        lastFoodError = message;
        break;
      case 'Shopping':
        lastShoppingError = message;
        break;
      case 'Nature':
        lastNatureError = message;
        break;
      case 'POI':
        lastAttractionsError = message;
        break;
    }
  }

  static Future<List<AttractionEntity>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    String? categoryName,
    int radius = 5000,
    // Which screen asks: 'ar' for the AR view, whose range the plan sets
    // separately (Explorer: 2 km in AR, 25 km elsewhere).
    String? ctx,
  }) async {
    final cacheKey = _buildClientCacheKey(latitude, longitude, categoryName, radius);
    final now = DateTime.now();
    if (_clientCache.containsKey(cacheKey) && _clientCacheExpiry.containsKey(cacheKey)) {
      if (now.isBefore(_clientCacheExpiry[cacheKey]!)) {
        debugPrint('⚡ Returning client-cached places for $cacheKey (${_clientCache[cacheKey]!.length} items)');
        return _clientCache[cacheKey]!;
      }
    }

    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/nearby',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'category': categoryName,
          'radius': radius,
          if (ctx != null) 'ctx': ctx,
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
        _clientCache[cacheKey] = models;
        _clientCacheExpiry[cacheKey] = now.add(const Duration(minutes: 10));
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

  /// Search places strictly within a 1-2 km radius (default 2000m)
  static Future<List<AttractionEntity>> getPlacesNearMe({
    required double latitude,
    required double longitude,
    String? category,
    double radiusM = 2000.0,
    String? ctx,
  }) async {
    try {
      final List<AttractionEntity> places = await fetchNearbyPlaces(
        latitude: latitude,
        longitude: longitude,
        radius: radiusM.toInt(),
        categoryName: category,
        ctx: ctx,
      );

      // Strictly filter within radius and sort ascending by distance
      final filtered = places.where((p) {
        final dist = p.distanceM ?? geo.Geolocator.distanceBetween(latitude, longitude, p.latitude, p.longitude);
        return dist <= radiusM;
      }).toList();

      filtered.sort((a, b) {
        final distA = a.distanceM ?? geo.Geolocator.distanceBetween(latitude, longitude, a.latitude, a.longitude);
        final distB = b.distanceM ?? geo.Geolocator.distanceBetween(latitude, longitude, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      return filtered;
    } catch (e) {
      debugPrint('Error getting places near me (1-2 km): $e');
      return [];
    }
  }

  /// Search places by text query biased towards current coordinates (New API)
  ///
  /// [radiusM] tightens the location bias (default 50km) — pass a small value
  /// (2000-5000) for a "near me"-triggered search. [nearMe] must be set
  /// alongside it: it tells the backend `query` is already a locality-stripped
  /// subject ("atm", not "atm near me"), so it can resolve specific POI types
  /// (atm, bakery, gym, ...) directly instead of treating it as a proper name.
  /// [latitude]/[longitude] bias results towards the user and are optional:
  /// pass null when the real position is unknown. They used to be required,
  /// which forced callers to invent a coordinate — every one of them picked
  /// Colombo, so a search for a Paris restaurant was ranked by distance from
  /// Sri Lanka. A query that already names its destination needs no bias at
  /// all; an unbiased search is the honest answer when we have no position.
  static Future<List<AttractionEntity>> searchPlaces({
    required String query,
    double? latitude,
    double? longitude,
    double? radiusM,
    bool nearMe = false,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/search',
        queryParameters: {
          'query': query,
          if (latitude != null) 'lat': latitude,
          if (longitude != null) 'lng': longitude,
          if (radiusM != null) 'radius_m': radiusM,
          if (nearMe) 'near_me': true,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> placesList = data['places'] as List? ?? [];
        final rawModels = placesList
            .map((p) => AttractionModel.fromJson(p))
            .toList();

        // Deduplicate search results
        final Set<String> seenKeys = {};
        final models = <AttractionModel>[];
        for (final m in rawModels) {
          final idKey = m.id.trim().toLowerCase();
          final nameKey = m.name.trim().toLowerCase();
          final key = idKey.isNotEmpty ? idKey : nameKey;
          if (key.isNotEmpty && seenKeys.add(key)) {
            models.add(m);
          }
        }

        // Sort by distance ascending when we have somewhere to measure from.
        // Without a reference point the backend's own ordering stands, which
        // beats ranking by distance from a coordinate we made up.
        final double? refLat = latitude;
        final double? refLng = longitude;
        if (refLat != null && refLng != null) {
          models.sort((a, b) {
            final distA = a.distanceM ?? geo.Geolocator.distanceBetween(refLat, refLng, a.latitude, a.longitude);
            final distB = b.distanceM ?? geo.Geolocator.distanceBetween(refLat, refLng, b.latitude, b.longitude);
            return distA.compareTo(distB);
          });
        }

        print(
          '✅ Places searched: ${models.length} items',
        );
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
    // A route from this very spot, not one cached from nearby: for fixed
    // places, whose route should start at the place.
    bool exactOrigin = false,
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
          if (exactOrigin) 'exact_origin': '1',
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

      // Turn-by-turn steps (Google sends them with every route; no extra
      // cost). Each step's instruction is the action at its start.
      final steps = <Map<String, dynamic>>[];
      for (final st in (leg['steps'] as List? ?? const [])) {
        if (st is! Map) continue;
        steps.add({
          'instruction': _plainInstruction((st['html_instructions'] ?? '').toString()),
          'maneuver': (st['maneuver'] ?? '').toString(),
          'distance_m': ((st['distance'] as Map?)?['value'] as num?)?.toDouble() ?? 0.0,
        });
      }

      return {
        'polyline': points,
        'duration_seconds': durationSec,
        'distance_meters': distanceM,
        'steps': steps,
      };
    } catch (e) {
      debugPrint('getDirections error: $e');
      return null;
    }
  }

  /// Google's step text without its HTML: "Turn <b>left</b> onto <b>X</b>
  /// <div>Destination will be on the right</div>" → "Turn left onto X ·
  /// Destination will be on the right".
  static String _plainInstruction(String html) {
    var t = html.replaceAll(RegExp(r'<div[^>]*>'), ' · ');
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  // ── Autocomplete in-memory LRU cache & cancellation infrastructure ──────
  static final Map<String, List<Map<String, dynamic>>> _autocompleteMemoryCache = {};
  static const int _maxCacheEntries = 120;
  static CancelToken? _autocompleteCancelToken;

  /// Verified city lists already fetched this session, by country code. The
  /// server caches these for 30 days; this stops a second trip to it when the
  /// traveller changes their mind about the country and back again.
  static final Map<String, List<Map<String, dynamic>>> _countryCityCache = {};

  /// The cities a trip through [country] can start or finish in.
  ///
  /// Proposed by Gemini and confirmed by Google on the server — see
  /// `country_cities_service` — so every entry carries Google's own name,
  /// coordinates and place_id, and a city the model invented is never among
  /// them. An empty list is a valid answer: the search box still works, so a
  /// country the server could not build a list for is not a dead end.
  static Future<List<Map<String, dynamic>>> getCountryCities({
    required String country,
    required String countryCode,
  }) async {
    final cc = countryCode.trim().toUpperCase();
    if (cc.length != 2 || country.trim().isEmpty) return [];
    final cached = _countryCityCache[cc];
    if (cached != null) return List<Map<String, dynamic>>.from(cached);

    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/country-cities',
        queryParameters: {'country': country.trim(), 'country_code': cc},
      );
      if (response.statusCode != 200) return [];
      final raw = (response.data is Map ? response.data['cities'] : null) as List? ?? [];
      final cities = raw
          .whereType<Map>()
          .map<Map<String, dynamic>>((c) => <String, dynamic>{
                'name': c['name']?.toString() ?? '',
                'place_id': c['place_id']?.toString() ?? '',
                'latitude': (c['latitude'] as num?)?.toDouble(),
                'longitude': (c['longitude'] as num?)?.toDouble(),
              })
          .where((c) => (c['name'] as String).isNotEmpty)
          .toList();
      _countryCityCache[cc] = cities;
      return List<Map<String, dynamic>>.from(cities);
    } catch (_) {
      // A dropdown is a convenience; the box below it still accepts a typed
      // city, so a failure here must not block the planner.
      return [];
    }
  }

  /// High-speed place suggestions/autocomplete powered by Google Places API proxy + in-memory LRU cache.
  /// Delivers Google Maps-grade performance (< 100ms response, 0ms on cache hits).
  /// [latitude]/[longitude] bias the results towards the user and are
  /// optional: pass null when the real position is unknown. They used to be
  /// required, which pushed every caller into inventing a coordinate — all of
  /// them defaulted to Colombo, quietly reordering suggestions around the
  /// wrong continent. An unbiased query is the honest answer instead.
  /// [countryCode] is an ISO 3166-1 alpha-2 code that RESTRICTS the answer to
  /// one country, rather than merely biasing it towards somewhere. Only the
  /// Odyssey planner's entry and exit boxes pass it, and only once a country
  /// has been chosen: everywhere else must keep finding places worldwide.
  /// [placeKinds] narrows the answer to a family of places instead of every
  /// kind. Two are useful here, and the difference matters — measured against
  /// the live API:
  ///
  ///   `(cities)`  towns and cities, no countries. "Japan" returns Japana in
  ///               Georgia; "Sri Lan" returns Panama, Sri Lanka.
  ///   `(regions)` countries as well as cities. "Japan" returns Japan,
  ///               "Sri Lan" returns Sri Lanka, and "Kinkaku-ji" and
  ///               "Hilton Tokyo" return nothing at all.
  ///
  /// So Entry, which has to accept the country a traveller names, asks for
  /// `(regions)`; Exit, which is only ever a city inside a country already
  /// chosen, asks for `(cities)`. Unfiltered, both would offer temples and
  /// hotels.
  static Future<List<Map<String, dynamic>>> getAutocompleteSuggestions({
    required String input,
    double? latitude,
    double? longitude,
    String? countryCode,
    String? placeKinds,
  }) async {
    final cleanedInput = input.trim();
    if (cleanedInput.isEmpty) return [];

    final String? region =
        (countryCode != null && countryCode.trim().length == 2)
            ? countryCode.trim().toUpperCase()
            : null;
    final String? components = region == null ? null : 'country:${region.toLowerCase()}';

    final bool hasBias = latitude != null && longitude != null;
    final String biasKey = hasBias
        ? '${latitude!.toStringAsFixed(2)},${longitude!.toStringAsFixed(2)}'
        : 'nobias';
    // The proxy translates this to the Places API (New) spelling. Sent only
    // when asked for, so every other caller's cached answers stay valid.
    final String? types =
        (placeKinds != null && placeKinds.trim().isNotEmpty) ? placeKinds.trim() : null;
    // The restriction is part of the question: a search held to Italy and one
    // searched worldwide must never share a cached answer. So is the kind of
    // place wanted — a cities-only search and an open one are different
    // questions about the same text.
    final cacheKey =
        '${cleanedInput.toLowerCase()}|$biasKey|${region ?? 'any'}|${types ?? 'all'}';

    // 1. Instant Cache Hit (0ms)
    if (_autocompleteMemoryCache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_autocompleteMemoryCache[cacheKey]!);
    }

    // Cancel any previous in-flight autocomplete request
    _autocompleteCancelToken?.cancel('superseded');
    _autocompleteCancelToken = CancelToken();
    final cancelToken = _autocompleteCancelToken!;

    try {
      // 2. Direct high-speed Google Places Autocomplete query
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/autocomplete/json',
        queryParameters: {
          'input': cleanedInput,
          if (hasBias) 'location': '$latitude,$longitude',
          if (hasBias) 'radius': 50000,
          if (hasBias) 'origin': '$latitude,$longitude',
          if (components != null) 'components': components,
          if (types != null) 'types': types,
          'language': 'en',
        },
        cancelToken: cancelToken,
      );

      List<Map<String, dynamic>> results = [];

      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> predictions = data['predictions'] as List? ?? [];
        results = predictions.map((p) {
          final structured = p['structured_formatting'] as Map<String, dynamic>?;
          return {
            'description': p['description'] as String? ?? '',
            'place_id': p['place_id'] as String? ?? '',
            'main_text': (structured?['main_text'] as String?) ?? p['description'] ?? '',
            'secondary_text': (structured?['secondary_text'] as String?) ?? '',
            'distance_meters': p['distance_meters'] as num?,
          };
        }).toList();
      }

      // If no local predictions returned (e.g. searching for a foreign/global
      // destination), search without the location bias. The country
      // restriction is carried through: dropping it here would widen a search
      // the caller deliberately narrowed, which is the whole point of it.
      if (results.isEmpty && cleanedInput.length >= 2) {
        try {
          final globalResp = await ApiClient.instance.get(
            '${ApiConstants.googleMapsProxy}/place/autocomplete/json',
            queryParameters: {
              'input': cleanedInput,
              if (components != null) 'components': components,
              if (types != null) 'types': types,
              'language': 'en',
            },
            cancelToken: cancelToken,
          );
          if (globalResp.statusCode == 200) {
            final data = globalResp.data;
            final List<dynamic> predictions = data['predictions'] as List? ?? [];
            results = predictions.map((p) {
              final structured = p['structured_formatting'] as Map<String, dynamic>?;
              return {
                'description': p['description'] as String? ?? '',
                'place_id': p['place_id'] as String? ?? '',
                'main_text': (structured?['main_text'] as String?) ?? p['description'] ?? '',
                'secondary_text': (structured?['secondary_text'] as String?) ?? '',
                'distance_meters': null,
              };
            }).toList();
          }
        } catch (_) {}
      }

      // Deduplicate results
      final Set<String> seenAutoKeys = {};
      final List<Map<String, dynamic>> uniqueResults = [];
      for (final item in results) {
        final placeId = (item['place_id'] ?? '').toString().trim().toLowerCase();
        final mainText = (item['main_text'] ?? item['name'] ?? item['description'] ?? '').toString().trim().toLowerCase();
        final key = placeId.isNotEmpty ? placeId : mainText;
        if (key.isNotEmpty && seenAutoKeys.add(key)) {
          uniqueResults.add(item);
        }
      }
      results = uniqueResults;

      // Store in memory cache
      if (results.isNotEmpty) {
        if (_autocompleteMemoryCache.length >= _maxCacheEntries) {
          _autocompleteMemoryCache.remove(_autocompleteMemoryCache.keys.first);
        }
        _autocompleteMemoryCache[cacheKey] = results;
      }

      return results;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return [];
      }
      debugPrint('Autocomplete error: $e');
      return [];
    } catch (e) {
      debugPrint('Autocomplete error: $e');
      return [];
    }
  }

  // ── Place Details in-memory LRU cache (0ms lookup) ─────────────────────
  static final Map<String, AttractionEntity> _placeDetailsCache = {};

  /// Get place details (lat/lng/name) by place_id using Google Places API + 14-day Redis caching.
  static Future<AttractionEntity?> getPlaceDetails(String placeId) async {
    try {
      final cleanId = placeId.replaceFirst('places/', '').trim();
      if (cleanId.isEmpty) return null;

      // 1. Instant Cache Hit (0ms)
      if (_placeDetailsCache.containsKey(cleanId)) {
        return _placeDetailsCache[cleanId];
      }

      double lat = 0.0;
      double lng = 0.0;
      String name = 'Unknown';
      String address = '';
      double rating = 4.0;
      int userRatingsTotal = 0;
      List<String> photoUrls = [];

      // 2. Direct high-speed call to Google Place Details proxy (returns name + geometry.location in < 100ms)
      try {
        final proxyResp = await ApiClient.instance.get(
          '${ApiConstants.googleMapsProxy}/place/details/json',
          queryParameters: {
            'place_id': cleanId,
            'fields': 'place_id,name,geometry,rating,user_ratings_total,photos,formatted_address',
          },
        );
        if (proxyResp.statusCode == 200 && proxyResp.data != null) {
          final result = proxyResp.data['result'] as Map<String, dynamic>?;
          if (result != null) {
            final geomLoc = result['geometry']?['location'] as Map<String, dynamic>?;
            if (geomLoc != null) {
              lat = (geomLoc['lat'] as num?)?.toDouble() ?? 0.0;
              lng = (geomLoc['lng'] as num?)?.toDouble() ?? 0.0;
            }
            if (result['name'] != null) {
              name = result['name'] as String;
            }
            if (result['formatted_address'] != null) {
              address = result['formatted_address'] as String;
            }
            if (result['rating'] != null) {
              rating = (result['rating'] as num).toDouble();
            }
            if (result['user_ratings_total'] != null) {
              userRatingsTotal = (result['user_ratings_total'] as num).toInt();
            }
            final photos = result['photos'] as List?;
            if (photos != null && photos.isNotEmpty) {
              for (final ph in photos.take(3)) {
                final ref = ph['photo_reference'] as String?;
                if (ref != null && ref.isNotEmpty) {
                  photoUrls.add('/api/v1/places/photo?ref=$ref');
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Google Place Details proxy error: $e');
      }

      // 3. Fallback to backend /places/{id}/details if proxy didn't resolve coordinates
      if (lat == 0.0 || lng == 0.0) {
        try {
          final response = await ApiClient.instance.get(
            '${ApiConstants.apiVersion}/places/$cleanId/details',
          );
          if (response.statusCode == 200) {
            final data = response.data as Map<String, dynamic>?;
            if (data != null) {
              if (name == 'Unknown') name = data['name'] as String? ?? 'Unknown';
              if (address.isEmpty) address = data['address'] as String? ?? '';
              rating = (data['rating'] as num?)?.toDouble() ?? rating;
              userRatingsTotal = (data['user_ratings_total'] as num?)?.toInt() ?? userRatingsTotal;
              if (photoUrls.isEmpty) photoUrls = (data['photo_urls'] as List?)?.cast<String>() ?? [];
              lat = (data['latitude'] as num?)?.toDouble() ?? lat;
              lng = (data['longitude'] as num?)?.toDouble() ?? lng;
            }
          }
        } catch (_) {}
      }

      if (lat != 0.0 && lng != 0.0) {
        final entity = AttractionModel(
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
          rating: rating,
          reviewCount: userRatingsTotal,
          photoUrls: photoUrls,
          tags: const [],
          geofenceRadiusM: 100,
          distanceM: 0,
          isActive: true,
          createdAt: DateTime.now(),
        );

        if (_placeDetailsCache.length >= 100) {
          _placeDetailsCache.remove(_placeDetailsCache.keys.first);
        }
        _placeDetailsCache[cleanId] = entity;

        return entity;
      }
      return null;
    } catch (e) {
      debugPrint('Place Details error: $e');
      return null;
    }
  }
}
