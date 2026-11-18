import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// Photos travellers send for places that show only their category icon. A
/// photo waits for our team; once approved it shows for everyone.
class PlacePhotosService {
  PlacePhotosService._();

  static String _base(String placeId) =>
      '${ApiConstants.apiVersion}/places/${Uri.encodeComponent(placeId.replaceFirst('places/', ''))}';

  /// The newest photo this traveller sent for the place, or null.
  static Future<MyPlacePhoto?> fetchMine(String placeId) async {
    try {
      final response = await ApiClient.instance.get('${_base(placeId)}/photo/mine');
      final data = response.data;
      if (data is Map<String, dynamic>) return MyPlacePhoto.fromJson(data);
    } catch (e) {
      debugPrint('❌ Error fetching my place photo: $e');
    }
    return null;
  }

  /// Sends a photo. The app has already shrunk it (image_picker maxWidth).
  static Future<PlacePhotoUpload> upload(
    String placeId, {
    required String filePath,
    required String placeName,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filePath.split('/').last),
        'place_name': placeName,
        if (latitude != null && latitude != 0.0) 'latitude': latitude.toString(),
        if (longitude != null && longitude != 0.0) 'longitude': longitude.toString(),
        'consent': 'true',
      });
      final response = await ApiClient.instance.post(
        '${_base(placeId)}/photos',
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return PlacePhotoUpload(photo: MyPlacePhoto.fromJson(data));
      }
    } catch (e) {
      debugPrint('❌ Error uploading place photo: $e');
      return PlacePhotoUpload(
        error: (e is DioException ? safeServerDetail(e.response) : null) ??
            'Could not send your photo. Please try again.',
      );
    }
    return const PlacePhotoUpload(error: 'Could not send your photo. Please try again.');
  }
}

class MyPlacePhoto {
  final String id;
  // "pending", "approved" or "rejected".
  final String status;
  final String? rejectReason;

  const MyPlacePhoto({required this.id, required this.status, this.rejectReason});

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  factory MyPlacePhoto.fromJson(Map<String, dynamic> json) => MyPlacePhoto(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'pending',
        rejectReason: json['reject_reason'] as String?,
      );
}

class PlacePhotoUpload {
  final MyPlacePhoto? photo;
  final String? error;

  const PlacePhotoUpload({this.photo, this.error});

  bool get sent => error == null && photo != null;
}
