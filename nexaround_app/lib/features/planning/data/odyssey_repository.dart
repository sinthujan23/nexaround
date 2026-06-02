import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Persists Odysseys on the backend by reusing the `/itineraries` endpoints.
/// An Odyssey is just an Itinerary whose JSON `items` start with an
/// `odyssey_meta` block (see [Odyssey.toItineraryItems]).
class OdysseyRepository {
  final Dio _dio = ApiClient.instance;

  /// Bumped whenever the saved set changes so list screens can refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Save a freshly generated Odyssey. Returns it with the backend id attached.
  Future<Odyssey> save(Odyssey odyssey) async {
    final response = await _dio.post(
      ApiConstants.itineraries,
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

  /// All saved Odysseys for the current user, newest first.
  Future<List<Odyssey>> getMyOdysseys() async {
    final response = await _dio.get(ApiConstants.itineraries);
    final list = (response.data as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where(Odyssey.isOdyssey)
        .map(Odyssey.fromItinerary)
        .toList();
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
