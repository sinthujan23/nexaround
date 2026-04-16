import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/attractions/domain/entities/review.dart';

class ReviewRepository {
  final Dio _dio = ApiClient.instance;

  Future<List<Review>> getReviews(String attractionId) async {
    final response = await _dio.get('${ApiConstants.baseUrl}/reviews/attraction/$attractionId');
    
    return (response.data as List).map((json) => Review(
      id: json['id'],
      userId: json['user_id'],
      userDisplayName: json['user_display_name'] ?? 'Explorer',
      attractionId: json['attraction_id'],
      rating: json['rating'],
      comment: json['comment'],
      createdAt: DateTime.parse(json['created_at']),
    )).toList();
  }

  Future<Review> postReview({
    required String attractionId,
    required int rating,
    String? comment,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.baseUrl}/reviews/',
      data: {
        'attraction_id': attractionId,
        'rating': rating,
        'comment': comment,
      },
    );

    final json = response.data;
    return Review(
      id: json['id'],
      userId: json['user_id'],
      userDisplayName: 'You',
      attractionId: json['attraction_id'],
      rating: json['rating'],
      comment: json['comment'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
