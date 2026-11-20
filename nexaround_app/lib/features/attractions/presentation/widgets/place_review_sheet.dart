import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/data/place_reviews_service.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_stars.dart';
import 'package:nexaround_app/features/explorer_points/data/explorer_points_service.dart';
import 'package:nexaround_app/features/explorer_points/domain/explorer_points.dart';
import 'package:nexaround_app/features/explorer_points/presentation/widgets/points_help.dart';

/// The outcome of the place rating sheet.
class PlaceReviewSheetResult {
  final MyPlaceReview? review;
  final bool isDeleted;

  const PlaceReviewSheetResult.saved(this.review) : isDeleted = false;
  const PlaceReviewSheetResult.deleted() : review = null, isDeleted = true;
}

/// Opens the rating form for a place. Returns what happened, or null when the
/// traveller closed the sheet. [existing] fills the form for an edit.
Future<PlaceReviewSheetResult?> showPlaceReviewSheet(
  BuildContext context, {
  required String placeId,
  required String placeName,
  double? latitude,
  double? longitude,
  MyPlaceReview? existing,
}) {
  return showModalBottomSheet<PlaceReviewSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (_) => _PlaceReviewSheet(
      placeId: placeId,
      placeName: placeName,
      latitude: latitude,
      longitude: longitude,
      existing: existing,
    ),
  );
}

const _labels = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

class _PlaceReviewSheet extends StatefulWidget {
  final String placeId;
  final String placeName;
  final double? latitude;
  final double? longitude;
  final MyPlaceReview? existing;

  const _PlaceReviewSheet({
    required this.placeId,
    required this.placeName,
    this.latitude,
    this.longitude,
    this.existing,
  });

  @override
  State<_PlaceReviewSheet> createState() => _PlaceReviewSheetState();
}

class _PlaceReviewSheetState extends State<_PlaceReviewSheet> {
  static const _maxComment = 1000;

  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The hint below the text box counts as the traveller types.
    _comment.addListener(_onTyping);
    ExplorerPointsService.loadInfo();
  }

  void _onTyping() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _comment.removeListener(_onTyping);
    _comment.dispose();
    super.dispose();
  }

  /// "Worth 10 points · 170 more characters for +10", from the server's table.
  String? _pointsHint(PointsInfo? info) {
    if (info == null) return null;
    final stars = info.rule('rating');
    final written = info.rule('written');
    final detailed = info.rule('detailed');
    if (stars == null) return null;
    if (_rating == 0) {
      return 'Rate it for +${stars.points} points, write a review for more';
    }
    final length = _comment.text.trim().length;
    var worth = stars.points;
    EarnRule? next;
    for (final r in [written, detailed]) {
      if (r == null || r.minChars <= 0) continue;
      if (length >= r.minChars) {
        worth += r.points;
      } else {
        next ??= r;
      }
    }
    if (next == null) return 'Worth $worth points';
    final more = next.minChars - length;
    return 'Worth $worth points · $more more ${more == 1 ? 'character' : 'characters'} for +${next.points}';
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Choose a star rating first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await PlaceReviewsService.submit(
      widget.placeId,
      rating: _rating,
      comment: _comment.text,
      placeName: widget.placeName,
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop(PlaceReviewSheetResult.saved(result.review));
      return;
    }
    setState(() {
      _saving = false;
      _error = result.error;
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text(
          'Are you sure you want to delete your review and rating? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    final ok = await PlaceReviewsService.delete(widget.placeId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(const PlaceReviewSheetResult.deleted());
      return;
    }
    setState(() {
      _deleting = false;
      _error = 'Could not delete your review. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  editing ? 'Your review' : 'Rate this place',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                ),
                if (widget.existing?.isHidden == true) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Our team hid this review, so other travellers do not see it.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 18),
                ExperienceStarPicker(
                  value: _rating,
                  onChanged: (n) => setState(() {
                    _rating = n;
                    _error = null;
                  }),
                ),
                SizedBox(
                  height: 22,
                  child: Center(
                    child: Text(
                      _labels[_rating],
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandGreen),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _comment,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: _maxComment,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Tell other travellers what it was like (optional)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                ValueListenableBuilder<PointsInfo?>(
                  valueListenable: ExplorerPointsService.info,
                  builder: (context, info, _) {
                    final hint = _pointsHint(info);
                    if (hint == null) return const SizedBox(height: 4);
                    return Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.brandGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(hint,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
                        ),
                        const PointsHelpButton(size: 17),
                      ],
                    );
                  },
                ),
                const Text(
                  'Your review is public and shows your first name and last initial.',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving || _deleting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            editing ? 'Save changes' : 'Post review',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                if (editing) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton.icon(
                      onPressed: _saving || _deleting ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                            )
                          : const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                      label: Text(
                        _deleting ? 'Deleting...' : 'Delete review',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
