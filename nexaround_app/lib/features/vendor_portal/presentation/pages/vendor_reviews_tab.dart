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

  bool get _hasMore => _summary != null && _reviews.length < _summary!.total;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
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
          const SizedBox(height: 2),
          const Text('What travellers say about your packages',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
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
    return VendorCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(average == null ? '–' : average.toStringAsFixed(1),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stars(rating: average ?? 0, size: 18),
                const SizedBox(height: 4),
                Text(
                  '${summary.reviewCount} review${summary.reviewCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// All / Waiting for a reply, as one segmented control.
  Widget _filters(VendorReviewPage? summary) {
    final waiting = summary?.unanswered ?? 0;
    Widget segment(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  boxShadow: selected ? AppShadows.sm : null,
                ),
                child: Text(label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    )),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        children: [
          segment('All', !_unansweredOnly, () => _filter(false)),
          segment(waiting > 0 ? 'Waiting for a reply ($waiting)' : 'Waiting for a reply', _unansweredOnly,
              () => _filter(true)),
        ],
      ),
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
    final name = review.reviewerName.trim();
    final replied = review.vendorReply != null;
    return VendorCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
                child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _Stars(rating: review.rating.toDouble(), size: 14),
                        const SizedBox(width: 6),
                        Text(_date(review.createdAt),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.packageTitle != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.confirmation_number_outlined, size: 14, color: AppColors.brandGreen),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(review.packageTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.brandGreen, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          if ((review.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!, style: const TextStyle(fontSize: 14, height: 1.45)),
          ],
          if (replied) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: AppColors.brandGreenLight,
                borderRadius: AppRadii.brSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your reply',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
                  const SizedBox(height: 4),
                  Text(review.vendorReply!, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (!replied)
                const Text('Waiting for your reply',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB7791F))),
              const Spacer(),
              TextButton.icon(
                onPressed: onReply,
                icon: Icon(replied ? Icons.edit_outlined : Icons.reply_rounded, size: 18),
                label: Text(replied ? 'Edit reply' : 'Reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
