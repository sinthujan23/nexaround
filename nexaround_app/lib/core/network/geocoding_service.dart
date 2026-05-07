import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

class GeocodingService {
  final Dio _dio = Dio();

  Future<String?> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final response = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': ApiConstants.googleMapsApiKey,
        },
      );

      if (response.data['status'] == 'OK') {
        final results = response.data['results'] as List;
        if (results.isNotEmpty) {
          return results[0]['formatted_address'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getPlaceNameFromCoordinates(double lat, double lng) async {
    try {
      final response = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
        queryParameters: {
          'location': '$lat,$lng',
          'radius': '50',
          'key': ApiConstants.googleMapsApiKey,
        },
      );

      if (response.data['status'] == 'OK') {
        final results = response.data['results'] as List;
        if (results.isNotEmpty) {
          return results[0]['name'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
