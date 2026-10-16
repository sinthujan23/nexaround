import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/experiences/data/services/experiences_service.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience_terms.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/legal_body.dart';

Future<void> showExperienceTerms(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ExperienceTermsPage()),
  );
}

/// The full Experience Booking Terms, opened from "Read full terms" on an
/// experience and from the request sheet. Shows the saved copy at once and
/// replaces it with the current version.
class ExperienceTermsPage extends StatefulWidget {
  const ExperienceTermsPage({super.key});

  @override
  State<ExperienceTermsPage> createState() => _ExperienceTermsPageState();
}

class _ExperienceTermsPageState extends State<ExperienceTermsPage> {
  ExperienceTerms? _terms = ExperiencesService.cachedTerms();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fresh = await ExperiencesService.fetchTerms();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _terms = fresh;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final terms = _terms;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          terms?.title ?? 'Experience Booking Terms',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: terms == null
          ? _buildEmpty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  _versionLine(context, terms),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 18),
                LegalBody(body: terms.body),
              ],
            ),
    );
  }

  String _versionLine(BuildContext context, ExperienceTerms terms) {
    final updated = terms.updatedAt;
    final date = updated == null
        ? ''
        : ' · Last updated '
            '${MaterialLocalizations.of(context).formatMediumDate(updated.toLocal())}';
    return 'Version ${terms.version}$date';
  }

  Widget _buildEmpty() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandGreen),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 36, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load the terms. Check your connection and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(foregroundColor: AppColors.brandGreen),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
