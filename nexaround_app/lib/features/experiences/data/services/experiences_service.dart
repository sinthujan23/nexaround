import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/experiences/data/models/experience_model.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// One page of nearest-first results, plus what the tab needs to decide
/// whether to show the "nothing nearby" banner.
class ExperiencesResult {
  final List<ExperiencePackageEntity> packages;
  final int total;
  final double? nearestDistanceM;

  /// False when the closest result is beyond the server's threshold. The app
  /// does not hardcode 50 km — the server sends both this and the threshold,
  /// so the rule can be retuned without an app release.
  final bool hasNearby;
  final int nearbyThresholdM;

  const ExperiencesResult({
    this.packages = const [],
    this.total = 0,
    this.nearestDistanceM,
    this.hasNearby = false,
    this.nearbyThresholdM = 50000,
  });
}

class ExperiencesService {
  /// How many pages deep the tab will go. With no radius cap, paging forever
  /// eventually walks the user onto another continent for no value.
  static const int maxPages = 5;
  static const int pageSize = 20;

  static Future<ExperiencesResult> fetchNearby({
    required double latitude,
    required double longitude,
    String? category,
    int limit = pageSize,
    int offset = 0,
  }) async {
    final response = await ApiClient.instance.get(
      ApiConstants.experiencesNearby,
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        'limit': limit,
        'offset': offset,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) return const ExperiencesResult();

    final rawPackages = data['packages'];
    return ExperiencesResult(
      packages: rawPackages is List
          ? rawPackages
              .whereType<Map<String, dynamic>>()
              .map(ExperiencePackageModel.fromJson)
              .toList()
          : const [],
      total: (data['total'] as num?)?.toInt() ?? 0,
      nearestDistanceM: (data['nearest_distance_m'] as num?)?.toDouble(),
      hasNearby: data['has_nearby'] as bool? ?? false,
      nearbyThresholdM: (data['nearby_threshold_m'] as num?)?.toInt() ?? 50000,
    );
  }

  static Future<ExperiencePackageEntity?> fetchPackage(
    String packageId, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.experiencePackages}/$packageId',
        queryParameters: {
          if (latitude != null) 'lat': latitude,
          if (longitude != null) 'lng': longitude,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return ExperiencePackageModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching experience package: $e');
      return null;
    }
  }

  /// Submits an enquiry. Returns null on success, or a message to show.
  static Future<String?> submitEnquiry({
    required String packageId,
    required String contactName,
    required String contactPhone,
    String? contactEmail,
    DateTime? preferredDate,
    int? partySize,
    String? message,
  }) async {
    try {
      await ApiClient.instance.post(
        ApiConstants.experienceEnquiries,
        data: {
          'package_id': packageId,
          'contact_name': contactName,
          'contact_phone': contactPhone,
          if (contactEmail != null && contactEmail.isNotEmpty)
            'contact_email': contactEmail,
          if (preferredDate != null)
            'preferred_date':
                preferredDate.toIso8601String().split('T').first,
          if (partySize != null) 'party_size': partySize,
          if (message != null && message.isNotEmpty) 'message': message,
        },
      );
      return null;
    } catch (e) {
      debugPrint('❌ Error submitting experience enquiry: $e');
      return 'Could not send your request. Please try again.';
    }
  }
}
