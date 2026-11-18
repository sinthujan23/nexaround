import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/network/api_client.dart';

/// Our travellers' own ratings and reviews of map places. Any place can be
/// rated — Google, free map data or our own — by the id the app shows it with.
/// Published at once; an admin can hide a review.
class PlaceReviewsService {
  PlaceReviewsService._();

  static String _base(String placeId) =>
      '${ApiConstants.apiVersion}/places/${Uri.encodeComponent(placeId.replaceFirst('places/', ''))}';

  /// The newest published reviews with the average, or null when they could
  /// not be fetched.
  static Future<PlaceReviewPage?> fetchReviews(String placeId, {int limit = 10}) async {
    try {
      final response = await ApiClient.instance.get(
        '${_base(placeId)}/reviews',
        queryParameters: {'limit': limit, 'offset': 0},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return PlaceReviewPage.fromJson(data);
    } catch (e) {
      debugPrint('❌ Error fetching place reviews: $e');
    }
    return null;
  }

  /// The signed-in traveller's own review of this place, or null.
  static Future<MyPlaceReview?> fetchMine(String placeId) async {
    try {
      final response = await ApiClient.instance.get('${_base(placeId)}/review/mine');
      final data = response.data;
      if (data is Map<String, dynamic>) return MyPlaceReview.fromJson(data);
    } catch (e) {
      debugPrint('❌ Error fetching my place review: $e');
    }
    return null;
  }

  /// Rates a place, or changes the rating already given.
  static Future<PlaceReviewSubmission> submit(
    String placeId, {
    required int rating,
    String? comment,
    required String placeName,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await ApiClient.instance.put(
        '${_base(placeId)}/review',
        data: {
          'rating': rating,
          if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
          'place_name': placeName,
          if (latitude != null && latitude != 0.0) 'latitude': latitude,
          if (longitude != null && longitude != 0.0) 'longitude': longitude,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return PlaceReviewSubmission(review: MyPlaceReview.fromJson(data));
      }
    } catch (e) {
      debugPrint('❌ Error saving place review: $e');
      return PlaceReviewSubmission(
        error: (e is DioException ? safeServerDetail(e.response) : null) ??
            'Could not save your review. Please try again.',
      );
    }
    return const PlaceReviewSubmission(error: 'Could not save your review. Please try again.');
  }

  /// Deletes the traveller's own review of this place.
  static Future<bool> delete(String placeId) async {
    try {
      final response = await ApiClient.instance.delete('${_base(placeId)}/review');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint('❌ Error deleting place review: $e');
      return false;
    }
  }
}

class PlaceReview {
  final String id;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final bool edited;

  const PlaceReview({
    required this.id,
    required this.reviewerName,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.edited = false,
  });

  factory PlaceReview.fromJson(Map<String, dynamic> json) => PlaceReview(
        id: json['id'] as String,
        reviewerName: json['reviewer_name'] as String? ?? 'Traveller',
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        edited: json['edited'] as bool? ?? false,
      );
}

class PlaceReviewPage {
  final double? average;
  final int count;
  final List<PlaceReview> reviews;

  const PlaceReviewPage({this.average, this.count = 0, this.reviews = const []});

  factory PlaceReviewPage.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? const {};
    return PlaceReviewPage(
      average: (summary['average'] as num?)?.toDouble(),
      count: (summary['count'] as num?)?.toInt() ?? 0,
      reviews: ((json['reviews'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlaceReview.fromJson)
          .toList(),
    );
  }
}

class MyPlaceReview {
  final String id;
  final int rating;
  final String? comment;
  // "hidden" when an admin took it down.
  final String status;

  const MyPlaceReview({
    required this.id,
    required this.rating,
    this.comment,
    this.status = 'published',
  });

  bool get isHidden => status == 'hidden';

  factory MyPlaceReview.fromJson(Map<String, dynamic> json) => MyPlaceReview(
        id: json['id'] as String,
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        status: json['status'] as String? ?? 'published',
      );
}

class PlaceReviewSubmission {
  final MyPlaceReview? review;
  final String? error;

  const PlaceReviewSubmission({this.review, this.error});

  bool get saved => error == null && review != null;
}
