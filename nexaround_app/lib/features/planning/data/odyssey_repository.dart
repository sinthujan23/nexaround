import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Persists Odysseys on the backend by reusing the `/itineraries` endpoints.
/// An Odyssey is just an Itinerary whose JSON `items` start with an
/// `odyssey_meta` block (see [Odyssey.toItineraryItems]).
class OdysseyRepository {
  final Dio _dio = ApiClient.instance;

  /// The collection endpoint MUST keep its trailing slash. The backend route is
  /// `/itineraries/`; calling it without the slash triggers a 307→301 redirect
  /// (which even bounces via http://), and HTTP clients drop the Authorization
  /// header across redirects — surfacing as a 401 "Not authenticated".
  static final String _collection = '${ApiConstants.itineraries}/';

  /// Bumped whenever the saved set changes so list screens can refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Kick off server-side AI generation. Returns immediately with a
  /// `status: "generating"` Odyssey; the backend fills in the plan in the
  /// background and the status flips to `active` (or `failed`).
  Future<Odyssey> requestGeneration({
    required String destination,
    required String mood,
    required double budget,
    required int days,
    String currency = 'USD',
    int travelers = 1,
    bool includeFlights = false,
    String departureCity = '',
    String departureCountry = '',
    String nationality = '',
    bool hasVisa = false,
    String? flightStartDate,
    String? flightEndDate,
    bool includeHotels = false,
    String? hotelCheckInDate,
    String? hotelCheckOutDate,
    String? startDate,
    String? endDate,
    // What the place picker resolved. All optional — the backend resolves the
    // destination itself, so omitting these only costs it a lookup.
    String destinationPlaceId = '',
    double? destinationLatitude,
    double? destinationLongitude,
    String destinationAddress = '',
    // Where the traveller is flying from. The name is derived from these and
    // is not always usable, so the point itself travels alongside it.
    double? departureLatitude,
    double? departureLongitude,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/odyssey/generate',
      data: {
        'destination': destination,
        'mood': mood,
        'budget': budget,
        'days': days,
        'currency': currency,
        'travelers': travelers,
        'include_flights': includeFlights,
        'departure_city': departureCity,
        'departure_country': departureCountry,
        'nationality': nationality,
        'has_visa': hasVisa,
        'flight_start_date': flightStartDate,
        'flight_end_date': flightEndDate,
        'include_hotels': includeHotels,
        'hotel_check_in_date': hotelCheckInDate,
        'hotel_check_out_date': hotelCheckOutDate,
        'start_date': startDate,
        'end_date': endDate,
        'destination_place_id': destinationPlaceId,
        'destination_latitude': destinationLatitude,
        'destination_longitude': destinationLongitude,
        'destination_address': destinationAddress,
        'departure_latitude': departureLatitude,
        'departure_longitude': departureLongitude,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Re-trigger generation for a failed Odyssey.
  Future<Odyssey> retryGeneration(String id) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/$id/odyssey/retry',
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Persist edits to an existing Odyssey (e.g. per-place check-off marking
  /// activities visited, or flipping status to `completed`). Sends the whole
  /// plan back via PUT so the nested `visited` flags and status are saved.
  Future<Odyssey> updateOdyssey(Odyssey odyssey) async {
    final id = odyssey.id;
    if (id == null) {
      throw ArgumentError('Cannot update an Odyssey without an id');
    }
    final response = await _dio.put(
      '${ApiConstants.itineraries}/$id',
      data: {
        'title': odyssey.title,
        'items': odyssey.toItineraryItems(),
        'status': odyssey.status,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Save an already-built Odyssey directly (used if a plan is generated
  /// client-side). Returns it with the backend id attached.
  Future<Odyssey> save(Odyssey odyssey) async {
    final response = await _dio.post(
      _collection,
      data: {
        'title': odyssey.title,
        'trip_date': null,
        'items': odyssey.toItineraryItems(),
        'status': odyssey.status,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Request the AI to replace a single booking partner. Returns the updated Odyssey.
  Future<Odyssey> swapPartner({
    required String itineraryId,
    required String partnerName,
    String reason = '',
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/$itineraryId/odyssey/swap-partner',
      data: {
        'partner_name': partnerName,
        'reason': reason,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// All saved Odysseys for the current user, newest first. Caches the raw
  /// result locally so [getCachedOdysseys] can render it instantly next time.
  Future<List<Odyssey>> getMyOdysseys() async {
    final response = await _dio.get(_collection);
    final raw = (response.data as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where(Odyssey.isOdyssey)
        .toList();
    await CacheService.cacheOdysseys(raw);
    return _sorted(raw.map(Odyssey.fromItinerary).toList());
  }

  /// The last cached Odyssey list (from the previous successful fetch). Returns
  /// an empty list if nothing is cached yet. Synchronous — no network.
  List<Odyssey> getCachedOdysseys() =>
      _sorted(CacheService.getCachedOdysseysRaw().map(Odyssey.fromItinerary).toList());

  List<Odyssey> _sorted(List<Odyssey> list) {
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  /// Fetch a single Odyssey by its itinerary ID (network first, cached fallback).
  Future<Odyssey?> getOdysseyById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.itineraries}/$id');
      final json = (response.data as Map).cast<String, dynamic>();
      final odyssey = Odyssey.fromItinerary(json);

      // Cache the full fresh Odyssey immediately so lists and details have full data
      final cachedRaw = CacheService.getCachedOdysseysRaw();
      final idx = cachedRaw.indexWhere((item) => item['id']?.toString() == id);
      if (idx != -1) {
        cachedRaw[idx] = json;
      } else {
        cachedRaw.insert(0, json);
      }
      await CacheService.cacheOdysseys(cachedRaw);
      revision.value++;

      return odyssey;
    } catch (_) {
      final cached = getCachedOdysseys();
      return cached.where((o) => o.id == id).firstOrNull;
    }
  }

  Future<void> delete(String id) async {
    await _dio.delete('${ApiConstants.itineraries}/$id');
    final cachedRaw = CacheService.getCachedOdysseysRaw();
    cachedRaw.removeWhere((item) => item['id']?.toString() == id);
    await CacheService.cacheOdysseys(cachedRaw);
    revision.value++;
  }
}
