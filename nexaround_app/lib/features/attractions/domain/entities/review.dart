import 'package:equatable/equatable.dart';

class Review extends Equatable {
  final String id;
  final String userId;
  final String userDisplayName;
  final String attractionId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.attractionId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, userId, attractionId, rating, comment, createdAt];
}
