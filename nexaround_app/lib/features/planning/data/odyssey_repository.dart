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
    String currency = 'LKR',
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/odyssey/generate',
      data: {
        'destination': destination,
        'mood': mood,
        'budget': budget,
        'days': days,
        'currency': currency,
      },
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

  /// Ask the AI to replace a single activity (the user already visited it or
  /// isn't interested). Returns the full updated Odyssey with the new place in
  /// place of the old one. [dayIndex]/[activityIndex] are zero-based positions.
  Future<Odyssey> swapActivity({
    required String itineraryId,
    required int dayIndex,
    required int activityIndex,
    String reason = '',
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/$itineraryId/odyssey/swap',
      data: {
        'day_index': dayIndex,
        'activity_index': activityIndex,
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

  Future<void> delete(String id) async {
    await _dio.delete('${ApiConstants.itineraries}/$id');
    revision.value++;
  }
}
