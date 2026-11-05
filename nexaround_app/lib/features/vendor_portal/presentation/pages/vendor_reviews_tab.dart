import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';

/// Travellers' ratings of the vendor's packages, and the vendor's replies.
class VendorReviewsTab extends StatefulWidget {
  final VendorPortalApi api;

  /// After a reply is posted or removed (Home counts the ones waiting).
  final VoidCallback? onReplied;

  const VendorReviewsTab({super.key, required this.api, this.onReplied});

  @override
  State<VendorReviewsTab> createState() => _VendorReviewsTabState();
}

class _VendorReviewsTabState extends State<VendorReviewsTab> {
  // What the device kept, until the server answers.
  late VendorReviewPage? _summary = widget.api.cachedReviews();
  late final List<VendorReview> _reviews = [...?_summary?.reviews];
  // The list showing is the kept one: no load for this filter worked yet.
  late bool _fromCache = _summary != null;
  int _page = 1;
  bool _unansweredOnly = false;
  bool _loading = false;
  Object? _error;
  // A fresh list (pull, or the filter changed) outdates any load still
  // running: its answer is for the old filter.
  int _generation = 0;
  // Reviews per star, one star first, for the summary's bars. The server sends
  // no such counts, so they exist only while every review is loaded; with
  // more than a page there are no bars rather than wrong ones.
  List<int>? _starCounts;

  bool get _hasMore => _summary != null && _reviews.length < _summary!.total;

  @override
  void initState() {
    super.initState();
    _countStars();
    _load(reset: true);
  }

  /// Counts the unfiltered list; the filtered one leaves the bars as they are.
  void _countStars() {
    final summary = _summary;
    if (_unansweredOnly || summary == null) return;
    if (_reviews.isEmpty || _reviews.length < summary.reviewCount) {
      _starCounts = null;
      return;
    }
    final counts = List.filled(5, 0);
    for (final review in _reviews) {
      if (review.rating >= 1 && review.rating <= 5) counts[review.rating - 1]++;
    }
    _starCounts = counts;
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    setState(() => _loading = true);
    try {
      final page = reset ? 1 : _page + 1;
      final result = await widget.api.reviews(page: page, unansweredOnly: _unansweredOnly);
      if (!mounted || generation != _generation) return;
      setState(() {
        _summary = result;
        _page = page;
        if (reset) _reviews.clear();
        _reviews.addAll(result.reviews);
        if (reset) _fromCache = false;
        _error = null;
        _countStars();
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _filter(bool unansweredOnly) {
    if (unansweredOnly == _unansweredOnly) return;
    // That filter's kept list while it loads, else the spinner.
    final kept = widget.api.cachedReviews(unansweredOnly: unansweredOnly);
    setState(() {
      _unansweredOnly = unansweredOnly;
      _reviews
        ..clear()
        ..addAll(kept?.reviews ?? const []);
      if (kept != null) _summary = kept;
      _fromCache = kept != null;
      _error = null;
    });
    _load(reset: true);
  }

  Future<void> _reply(VendorReview review) async {
    final controller = TextEditingController(text: review.vendorReply ?? '');
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            vendorGutter, 0, vendorGutter, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reply to ${review.reviewerName}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              const SizedBox(height: 4),
              const Text('Everyone who reads the review sees your reply.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: vendorInput('Your reply'),
              ),
              const SizedBox(height: 12),
              VendorPrimaryButton(
                label: 'Post reply',
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              ),
              if (review.vendorReply != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Remove my reply'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (text == null) return;
    try {
      final updated = await widget.api.reply(review.id, text.isEmpty ? null : text);
      if (!mounted) return;
      setState(() {
        final i = _reviews.indexWhere((r) => r.id == review.id);
        if (i >= 0) _reviews[i] = updated;
      });
      showVendorSnack(context, text.isEmpty ? 'Reply removed' : 'Reply posted');
      widget.onReplied?.call();
      // The counts in the summary changed.
      _load(reset: true);
    } catch (e) {
      if (mounted) showVendorSnack(context, userMessageFor(e, action: 'save the reply'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(vendorGutter, 4, vendorGutter, 24),
        children: [
          const Text('Reviews',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          const SizedBox(height: 12),
          if (_error != null && _fromCache) const VendorSavedNote(),
          if (summary != null) _summaryCard(summary),
          _filters(summary),
          const SizedBox(height: 14),
          if (_error != null && _reviews.isEmpty)
            VendorEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load reviews',
              message: userMessageFor(_error),
              action: OutlinedButton(onPressed: () => _load(reset: true), child: const Text('Try again')),
            )
          else if (summary == null || (_loading && _reviews.isEmpty))
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_reviews.isEmpty)
            VendorEmptyState(
              icon: _unansweredOnly ? Icons.mark_chat_read_outlined : Icons.star_outline_rounded,
              title: _unansweredOnly ? 'All caught up' : 'No reviews yet',
              message: _unansweredOnly
                  ? 'Every review has your reply.'
                  : 'Reviews travellers leave on your packages show here.',
            )
          else ...[
            for (final review in _reviews) _ReviewCard(review: review, onReply: () => _reply(review)),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _load(),
                  child: Text(_loading ? 'Loading…' : 'Show more'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(VendorReviewPage summary) {
    final average = summary.average;
    final counts = _starCounts;
    return VendorCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Column(
            children: [
              Text(average == null ? '–' : average.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1)),
              const SizedBox(height: 4),
              _Stars(rating: average ?? 0, size: 14),
              const SizedBox(height: 3),
              Text(
                '${summary.reviewCount} review${summary.reviewCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (counts != null) ...[
            const SizedBox(width: 16),
            Expanded(child: _RatingBars(counts: counts)),
          ],
        ],
      ),
    );
  }

  /// All / Waiting for a reply, as chips.
  Widget _filters(VendorReviewPage? summary) {
    final waiting = summary?.unanswered ?? 0;
    Widget chip(String label, bool selected, VoidCallback onTap) => Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppDurations.fast,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: selected ? AppColors.primary : AppColors.border),
              ),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  )),
            ),
          ),
        );
    return Row(
      children: [
        chip('All', !_unansweredOnly, () => _filter(false)),
        const SizedBox(width: 8),
        Flexible(
          child: chip(waiting > 0 ? 'Waiting for a reply · $waiting' : 'Waiting for a reply', _unansweredOnly,
              () => _filter(true)),
        ),
      ],
    );
  }
}

/// How the reviews split by stars, five at the top.
class _RatingBars extends StatelessWidget {
  /// Reviews per star, one star first.
  final List<int> counts;

  const _RatingBars({required this.counts});

  @override
  Widget build(BuildContext context) {
    final total = counts.fold<int>(0, (sum, n) => sum + n);
    return Column(
      children: [
        for (var star = 5; star >= 1; star--)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 10,
                  child: Text('$star',
                      style: const TextStyle(fontSize: 11.5, height: 1.2, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 6,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: total == 0 ? 0.0 : counts[star - 1] / total,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.ratingGold,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating;
  final double size;

  const _Stars({required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: AppColors.ratingGold,
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final VendorReview review;
  final VoidCallback onReply;

  const _ReviewCard({required this.review, required this.onReply});

  String _date(DateTime? d) {
    if (d == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = d.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final replied = review.vendorReply != null;
    return VendorCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(review.reviewerName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(_date(review.createdAt),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              _Stars(rating: review.rating.toDouble(), size: 14),
              if (review.packageTitle != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(review.packageTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
          if ((review.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(review.comment!, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ],
          const SizedBox(height: 10),
          if (replied) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadii.brSm),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Your reply: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: review.vendorReply),
                  ],
                ),
                style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit reply'),
              ),
            ),
          ] else
            ElevatedButton(
              onPressed: onReply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                // From the theme's, which carries the app font: this one replaces it.
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              child: const Text('Reply'),
            ),
        ],
      ),
    );
  }
}
