import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experiences_tab.dart';

/// Dedicated page for browsing and booking local experiences and tours.
class ExperiencesPage extends StatefulWidget {
  /// When true, experiences are marked as coming soon and vendor lists are hidden.
  /// Set to false when vendor negotiations and pricing are finalized.
  static const bool isComingSoon = true;

  final double? latitude;
  final double? longitude;

  const ExperiencesPage({
    super.key,
    this.latitude,
    this.longitude,
  });

  @override
  State<ExperiencesPage> createState() => _ExperiencesPageState();
}

class _ExperiencesPageState extends State<ExperiencesPage> {
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    if (!ExperiencesPage.isComingSoon) {
      _lat = widget.latitude ?? CacheService.getLastFetchLat();
      _lng = widget.longitude ?? CacheService.getLastFetchLng();
      if (_lat == null || _lng == null) {
        _resolveLocation();
      }
    }
  }

  Future<void> _resolveLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            timeLimit: const Duration(seconds: 4),
          );
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: const Text(
          'Experiences',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ExperiencesPage.isComingSoon
          ? _buildComingSoonBody(context)
          : ExperiencesTab(
              latitude: _lat,
              longitude: _lng,
            ),
    );
  }

  Widget _buildComingSoonBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sailing_rounded,
                size: 40,
                color: Color(0xFF00E676),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Handcrafted Tours Coming Soon',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'We are partnering with vetted local tour operators and finalizing exclusive rates. Check back soon for curated adventures!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Blueprints'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
