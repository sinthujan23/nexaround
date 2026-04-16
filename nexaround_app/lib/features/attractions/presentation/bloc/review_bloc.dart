import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/data/repositories/review_repository_impl.dart';
import 'package:nexaround_app/features/attractions/domain/entities/review.dart';

// Events
abstract class ReviewEvent extends Equatable {
  const ReviewEvent();
  @override
  List<Object?> get props => [];
}

class FetchReviews extends ReviewEvent {
  final String attractionId;
  const FetchReviews(this.attractionId);
}

class PostReview extends ReviewEvent {
  final String attractionId;
  final int rating;
  final String? comment;
  const PostReview({required this.attractionId, required this.rating, this.comment});
}

// State
class ReviewState extends Equatable {
  final List<Review> reviews;
  final bool isLoading;
  final String? errorMessage;

  const ReviewState({
    this.reviews = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ReviewState copyWith({
    List<Review>? reviews,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ReviewState(
      reviews: reviews ?? this.reviews,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [reviews, isLoading, errorMessage];
}

// Bloc
class ReviewBloc extends Bloc<ReviewEvent, ReviewState> {
  final ReviewRepository _repository;

  ReviewBloc(this._repository) : super(const ReviewState()) {
    on<FetchReviews>(_onFetchReviews);
    on<PostReview>(_onPostReview);
  }

  Future<void> _onFetchReviews(FetchReviews event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final reviews = await _repository.getReviews(event.attractionId);
      emit(state.copyWith(isLoading: false, reviews: reviews));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onPostReview(PostReview event, Emitter<ReviewState> emit) async {
    try {
      await _repository.postReview(
        attractionId: event.attractionId,
        rating: event.rating,
        comment: event.comment,
      );
      add(FetchReviews(event.attractionId));
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
}
