import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// Photos travellers send for places: one per traveller per place, any place
/// (since 2026-11-20). A photo waits for our team; once approved it shows for
/// everyone and earns Explorer Points (more for a place that had no photo).
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

  /// A place's approved traveller photos, newest first (empty on failure).
  static Future<List<PlacePhotoPublic>> fetchPhotos(String placeId, {int limit = 20}) async {
    try {
      final response = await ApiClient.instance.get(
        '${_base(placeId)}/photos',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return ((data['photos'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PlacePhotoPublic.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('❌ Error fetching place photos: $e');
    }
    return const [];
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
  // The first photo of a place that had none (Trailblazer bonus).
  final bool trailblazer;
  // What it earns once approved (0 from an older server).
  final int points;

  const MyPlacePhoto({
    required this.id,
    required this.status,
    this.rejectReason,
    this.trailblazer = false,
    this.points = 0,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory MyPlacePhoto.fromJson(Map<String, dynamic> json) => MyPlacePhoto(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'pending',
        rejectReason: json['reject_reason'] as String?,
        trailblazer: json['trailblazer'] == true,
        points: (json['points'] as num?)?.toInt() ?? 0,
      );
}

/// An approved traveller photo on the place page.
class PlacePhotoPublic {
  final String id;
  final String url;
  final String cardUrl;
  final String uploaderName;
  final int? uploaderLevel;
  final String? uploaderLevelName;

  const PlacePhotoPublic({
    required this.id,
    required this.url,
    required this.cardUrl,
    required this.uploaderName,
    this.uploaderLevel,
    this.uploaderLevelName,
  });

  factory PlacePhotoPublic.fromJson(Map<String, dynamic> json) {
    final url = json['url'] as String? ?? '';
    return PlacePhotoPublic(
      id: json['id'] as String? ?? '',
      url: url,
      cardUrl: json['card_url'] as String? ?? url,
      uploaderName: json['uploader_name'] as String? ?? 'Traveller',
      uploaderLevel: (json['uploader_level'] as num?)?.toInt(),
      uploaderLevelName: json['uploader_level_name'] as String?,
    );
  }
}

class PlacePhotoUpload {
  final MyPlacePhoto? photo;
  final String? error;

  const PlacePhotoUpload({this.photo, this.error});

  bool get sent => error == null && photo != null;
}
