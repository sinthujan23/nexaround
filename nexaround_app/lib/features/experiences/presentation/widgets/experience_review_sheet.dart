import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_review.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_stars.dart';

/// Opens the rating form for a package. Returns the saved review, or null when
/// the traveller closed the sheet. [existing] fills the form for an edit.
Future<MyExperienceReview?> showExperienceReviewSheet(
  BuildContext context, {
  required String packageId,
  required String packageTitle,
  String? vendorName,
  MyExperienceReview? existing,
}) {
  return showModalBottomSheet<MyExperienceReview>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(
      packageId: packageId,
      packageTitle: packageTitle,
      vendorName: vendorName,
      existing: existing,
    ),
  );
}

const _labels = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

class _ReviewSheet extends StatefulWidget {
  final String packageId;
  final String packageTitle;
  final String? vendorName;
  final MyExperienceReview? existing;

  const _ReviewSheet({
    required this.packageId,
    required this.packageTitle,
    this.vendorName,
    this.existing,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  static const _maxComment = 1000;

  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
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
    final result = await ExperiencesService.submitReview(
      widget.packageId,
      rating: _rating,
      comment: _comment.text,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop(result.review);
      return;
    }
    setState(() {
      _saving = false;
      _error = result.error;
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
                  editing ? 'Your review' : 'Rate this experience',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.vendorName == null
                      ? widget.packageTitle
                      : '${widget.packageTitle} · ${widget.vendorName}',
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.textSecondary),
                ),
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
                    hintText: 'Tell other travellers about your day (optional)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your review is public and shows your first name and last '
                  'initial. The provider can reply to it.',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            editing ? 'Save changes' : 'Post review',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
