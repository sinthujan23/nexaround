import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';

/// Travellers' ratings of the vendor's packages, and the vendor's replies.
class VendorReviewsTab extends StatefulWidget {
  final VendorPortalApi api;

  const VendorReviewsTab({super.key, required this.api});

  @override
  State<VendorReviewsTab> createState() => _VendorReviewsTabState();
}

class _VendorReviewsTabState extends State<VendorReviewsTab> {
  VendorReviewPage? _summary;
  final List<VendorReview> _reviews = [];
  int _page = 1;
  bool _unansweredOnly = false;
  bool _loading = false;
  Object? _error;

  bool get _hasMore => _summary != null && _reviews.length < _summary!.total;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = reset ? 1 : _page + 1;
      final result = await widget.api.reviews(page: page, unansweredOnly: _unansweredOnly);
      if (!mounted) return;
      setState(() {
        _summary = result;
        _page = page;
        if (reset) _reviews.clear();
        _reviews.addAll(result.reviews);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reply(VendorReview review) async {
    final controller = TextEditingController(text: review.vendorReply ?? '');
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reply to ${review.reviewerName}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Everyone who reads the review sees your reply.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: vendorInput('Your reply'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Post reply'),
            ),
            if (review.vendorReply != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Remove my reply'),
              ),
          ],
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (summary != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.ratingGold, size: 34),
                  const SizedBox(width: 10),
                  Text(summary.average == null ? '–' : summary.average!.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${summary.reviewCount} review${summary.reviewCount == 1 ? '' : 's'}'
                      '${summary.unanswered > 0 ? '\n${summary.unanswered} waiting for a reply' : ''}',
                      style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !_unansweredOnly,
                onSelected: (_) {
                  setState(() => _unansweredOnly = false);
                  _load(reset: true);
                },
              ),
              ChoiceChip(
                label: const Text('Waiting for a reply'),
                selected: _unansweredOnly,
                onSelected: (_) {
                  setState(() => _unansweredOnly = true);
                  _load(reset: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null && _reviews.isEmpty)
            VendorEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn’t load reviews',
              message: userMessageFor(_error),
              action: OutlinedButton(onPressed: () => _load(reset: true), child: const Text('Try again')),
            )
          else if (summary == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_reviews.isEmpty)
            VendorEmptyState(
              icon: Icons.star_outline_rounded,
              title: _unansweredOnly ? 'Nothing waiting for a reply' : 'No reviews yet',
              message: 'Reviews travellers leave on your packages show here.',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18, color: AppColors.ratingGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(review.reviewerName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(_date(review.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
          if (review.packageTitle != null) ...[
            const SizedBox(height: 4),
            Text(review.packageTitle!,
                style: const TextStyle(fontSize: 12, color: AppColors.brandGreen, fontWeight: FontWeight.w600)),
          ],
          if ((review.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: 10),
          if (review.vendorReply != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your reply',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
                  const SizedBox(height: 4),
                  Text(review.vendorReply!, style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReply,
              icon: Icon(review.vendorReply == null ? Icons.reply_rounded : Icons.edit_outlined, size: 18),
              label: Text(review.vendorReply == null ? 'Reply' : 'Edit reply'),
            ),
          ),
        ],
      ),
    );
  }
}
