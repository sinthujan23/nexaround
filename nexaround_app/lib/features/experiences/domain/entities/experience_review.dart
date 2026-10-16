/// Ratings and reviews on experience packages.
///
/// The server owns the rules (see experience_reviews.py): only a traveller whose
/// booking the provider confirmed, once the booked day has come, can review it,
/// one review per booking. Reviews are published at once; a moderator can hide
/// one, and the provider can answer in public.

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toLocal();

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// A review as any traveller sees it: first name and last initial only.
class ExperienceReview {
  final String id;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime? createdAt;
  final bool edited;
  final String? vendorReply;
  final DateTime? vendorRepliedAt;

  const ExperienceReview({
    required this.id,
    required this.reviewerName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.edited = false,
    this.vendorReply,
    this.vendorRepliedAt,
  });

  factory ExperienceReview.fromJson(Map<String, dynamic> json) {
    return ExperienceReview(
      id: json['id']?.toString() ?? '',
      reviewerName: _text(json['reviewer_name']) ?? 'Traveller',
      rating: ((json['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
      comment: _text(json['comment']),
      createdAt: _date(json['created_at']),
      edited: json['edited'] as bool? ?? false,
      vendorReply: _text(json['vendor_reply']),
      vendorRepliedAt: _date(json['vendor_replied_at']),
    );
  }
}

/// A package's average, count and the 5-to-1 breakdown.
class ReviewSummary {
  final double? average;
  final int count;

  /// How many reviews gave 5, 4, 3, 2 and 1 stars, in that order.
  final List<int> breakdown;

  const ReviewSummary({
    this.average,
    this.count = 0,
    this.breakdown = const [0, 0, 0, 0, 0],
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['breakdown'];
    final breakdown = raw is List
        ? [for (final n in raw) (n as num?)?.toInt() ?? 0]
        : <int>[];
    while (breakdown.length < 5) {
      breakdown.add(0);
    }
    return ReviewSummary(
      average: (json['average'] as num?)?.toDouble(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      breakdown: breakdown,
    );
  }
}

/// One page of a package's reviews, with the summary.
class ExperienceReviewPage {
  final ReviewSummary summary;
  final List<ExperienceReview> reviews;
  final int total;

  const ExperienceReviewPage({
    required this.summary,
    required this.reviews,
    required this.total,
  });

  factory ExperienceReviewPage.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final reviews = json['reviews'];
    return ExperienceReviewPage(
      summary: summary is Map<String, dynamic>
          ? ReviewSummary.fromJson(summary)
          : const ReviewSummary(),
      reviews: reviews is List
          ? reviews
              .whereType<Map<String, dynamic>>()
              .map(ExperienceReview.fromJson)
              .toList()
          : const [],
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The signed-in traveller's own review of one of their bookings.
class MyExperienceReview {
  final String id;
  final int rating;
  final String? comment;

  /// "published", or "hidden" once a moderator took it down: the traveller
  /// still sees their own text, marked as hidden.
  final String status;
  final String? vendorReply;

  const MyExperienceReview({
    required this.id,
    required this.rating,
    this.comment,
    this.status = 'published',
    this.vendorReply,
  });

  bool get isHidden => status == 'hidden';

  factory MyExperienceReview.fromJson(Map<String, dynamic> json) {
    return MyExperienceReview(
      id: json['id']?.toString() ?? '',
      rating: ((json['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
      comment: _text(json['comment']),
      status: json['status']?.toString() ?? 'published',
      vendorReply: _text(json['vendor_reply']),
    );
  }
}
