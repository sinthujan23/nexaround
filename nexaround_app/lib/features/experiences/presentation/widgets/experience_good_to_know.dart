import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_terms.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_terms_page.dart';

/// An icon for a highlight line. The lines are admin-edited text, so this
/// matches loosely and falls back to a plain info icon.
IconData highlightIcon(String line) {
  final text = line.toLowerCase();
  if (text.contains('pay') || text.contains('cash')) return Icons.payments_outlined;
  if (text.contains('cancel')) return Icons.event_busy_outlined;
  if (text.contains('confirm')) return Icons.verified_outlined;
  if (text.contains('provider') || text.contains('local')) {
    return Icons.handshake_outlined;
  }
  return Icons.info_outline_rounded;
}

/// The highlight lines of the Experience Booking Terms, one per row.
class ExperienceHighlights extends StatelessWidget {
  final List<String> lines;

  const ExperienceHighlights({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(highlightIcon(line), size: 17, color: AppColors.brandGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textPrimary,
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

/// "Good to know" on an experience: the rules that matter before requesting,
/// and the way into the full terms.
class ExperienceGoodToKnow extends StatefulWidget {
  const ExperienceGoodToKnow({super.key});

  @override
  State<ExperienceGoodToKnow> createState() => _ExperienceGoodToKnowState();
}

class _ExperienceGoodToKnowState extends State<ExperienceGoodToKnow> {
  List<String> _lines = ExperiencesService.cachedTerms()?.highlights ??
      ExperienceTerms.fallbackHighlights;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final fresh = await ExperiencesService.fetchTerms();
    if (!mounted || fresh == null || fresh.highlights.isEmpty) return;
    setState(() => _lines = fresh.highlights);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Good to know',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ExperienceHighlights(lines: _lines),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showExperienceTerms(context),
              style: TextButton.styleFrom(foregroundColor: AppColors.brandGreen),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Read full terms',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
