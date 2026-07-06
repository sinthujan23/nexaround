import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/planning/domain/museum.dart';

/// Fetches museum data from the `/museums` backend endpoints.
class MuseumRepository {
  final Dio _dio = ApiClient.instance;

  static const String _base = '${ApiConstants.apiVersion}/museums';

  /// All museums ordered by visitor rank.
  Future<List<MuseumListItem>> getMuseums() async {
    final response = await _dio.get('$_base/');
    return (response.data as List)
        .map((e) => MuseumListItem.fromJson(
            (e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Curated itinerary filtered by duration: "5h", "1d", "2d".
  Future<MuseumItinerary> getItinerary({
    required String slug,
    String duration = '1d',
  }) async {
    final response = await _dio.get(
      '$_base/$slug/itinerary',
      queryParameters: {'duration': duration},
    );
    return MuseumItinerary.fromJson(
        (response.data as Map).cast<String, dynamic>());
  }
}
