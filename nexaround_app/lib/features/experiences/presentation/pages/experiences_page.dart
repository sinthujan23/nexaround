import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experiences_tab.dart';

/// Dedicated page for browsing and booking local experiences and tours.
class ExperiencesPage extends StatefulWidget {
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
    _lat = widget.latitude ?? CacheService.getLastFetchLat();
    _lng = widget.longitude ?? CacheService.getLastFetchLng();
    if (_lat == null || _lng == null) {
      _resolveLocation();
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
      body: ExperiencesTab(
        latitude: _lat,
        longitude: _lng,
      ),
    );
  }
}
