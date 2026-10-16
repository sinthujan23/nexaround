import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_review.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_stars.dart';

/// A package's reviews on its detail page: the average with the 5-to-1
/// breakdown, then the reviews newest first, each with the provider's public
/// reply when there is one. Draws nothing until the package has a review.
class ExperienceReviewsSection extends StatefulWidget {
  final String packageId;
  final String vendorName;

  /// From the package itself, so the section knows at once whether there is
  /// anything to load.
  final int ratingCount;

  const ExperienceReviewsSection({
    super.key,
    required this.packageId,
    required this.vendorName,
    required this.ratingCount,
  });

  @override
  State<ExperienceReviewsSection> createState() =>
      _ExperienceReviewsSectionState();
}

class _ExperienceReviewsSectionState extends State<ExperienceReviewsSection> {
  static const _pageSize = 10;

  ReviewSummary? _summary;
  final List<ExperienceReview> _reviews = [];
  int _total = 0;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.ratingCount > 0) _loadMore();
  }

  @override
  void didUpdateWidget(covariant ExperienceReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The full record arrives after the card's copy: load once the count is known.
    if (oldWidget.ratingCount == 0 &&
        widget.ratingCount > 0 &&
        _reviews.isEmpty &&
        !_loading) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final page = await ExperiencesService.fetchReviews(
      widget.packageId,
      offset: _reviews.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page == null) {
        _failed = true;
        return;
      }
      _summary = page.summary;
      _total = page.total;
      _reviews.addAll(page.reviews);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (widget.ratingCount == 0 && summary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reviews',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if (summary != null && summary.count > 0) _Summary(summary: summary),
          if (summary != null && summary.count > 0) const SizedBox(height: 8),
          for (final review in _reviews)
            _ReviewTile(review: review, vendorName: widget.vendorName),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_failed && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Could not load reviews. Tap to retry'),
              ),
            ),
          if (!_loading && !_failed && _reviews.length < _total)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton(
                onPressed: _loadMore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandGreen,
                  side: const BorderSide(color: AppColors.brandGreen),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Show more reviews (${_total - _reviews.length} more)'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final ReviewSummary summary;

  const _Summary({required this.summary});

  @override
  Widget build(BuildContext context) {
    final average = summary.average ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              average.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 40, fontWeight: FontWeight.w800, height: 1.05),
            ),
            const SizedBox(height: 4),
            ExperienceStars(value: average, size: 16),
            const SizedBox(height: 4),
            Text(
              '${summary.count} ${summary.count == 1 ? 'review' : 'reviews'}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < 5; i++)
                _BreakdownRow(
                  stars: 5 - i,
                  count: summary.breakdown[i],
                  total: summary.count,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final int stars;
  final int count;
  final int total;

  const _BreakdownRow({
    required this.stars,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text('$stars',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.star_rounded, size: 12, color: AppColors.ratingGold),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 7,
                backgroundColor: AppColors.surfaceElevated,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.ratingGold),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text('$count',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ExperienceReview review;
  final String vendorName;

  const _ReviewTile({required this.review, required this.vendorName});

  @override
  Widget build(BuildContext context) {
    final created = review.createdAt;
    final when = created == null
        ? ''
        : MaterialLocalizations.of(context).formatMediumDate(created);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.reviewerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              ExperienceStars(value: review.rating.toDouble(), size: 15),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            review.edited ? '$when · edited' : when,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          if (review.comment != null) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: const TextStyle(
                  fontSize: 14.5, height: 1.45, color: AppColors.textPrimary),
            ),
          ],
          if (review.vendorReply != null) ...[
            const SizedBox(height: 10),
            // A bar and a card, not a one-sided border: Flutter refuses a
            // border radius on a border whose sides differ.
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 3, color: AppColors.brandGreen),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reply from $vendorName',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandGreen,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                review.vendorReply!,
                                style: const TextStyle(fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
