import 'dart:convert';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/google_maps_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/permission_service.dart';

class AttractionDetailPage extends StatefulWidget {
  final String? id;
  final String name;
  final String category;
  final double rating;
  final String distance;
  final String emoji;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final int? reviewCount;
  final String? aiWhy;
  final String? aiWhen;
  final String? aiCost;
  final String? aiBestFor;
  final String? aiConfidence;

  const AttractionDetailPage({
    super.key,
    this.id,
    required this.name,
    required this.category,
    required this.rating,
    required this.distance,
    required this.emoji,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.reviewCount,
    this.aiWhy,
    this.aiWhen,
    this.aiCost,
    this.aiBestFor,
    this.aiConfidence,
  });

  @override
  State<AttractionDetailPage> createState() => _AttractionDetailPageState();
}

class _AttractionDetailPageState extends State<AttractionDetailPage> {
  String get _placeId => widget.id ?? widget.name.hashCode.toString();
  String? _resolvedImageUrl;

  // ── Google Places data ──
  bool _isLoadingPlaces = true;
  String? _openNowText;
  String? _closingTime;
  int? _totalReviews;
  String? _priceLevel;
  List<Map<String, dynamic>> _realReviews = [];
  List<String> _weekdayHours = [];

  // ── Route data ──
  String? _routeDistanceStr;
  String? _routeDurationStr;
  bool _isLoadingRoute = true;

  // ── Gemini data ──
  // (Removed history/cultural tips as requested to speed up Near You places)

  @override
  void initState() {
    super.initState();
    _resolvedImageUrl = widget.imageUrl;
    _totalReviews = widget.reviewCount;
    _fetchPlacesDetails();
    _fetchRouteDistance();
  }

  Future<void> _fetchRouteDistance() async {
    if (widget.latitude == null || widget.longitude == null || (widget.latitude == 0.0 && widget.longitude == 0.0)) {
      if (mounted) setState(() => _isLoadingRoute = false);
      return;
    }
    
    try {
      final position = await PermissionService.getSafePosition();
      if (position == null) {
        if (mounted) setState(() => _isLoadingRoute = false);
        return;
      }
      
      final routeData = await GooglePlacesService.getDirections(
        originLat: position.latitude,
        originLng: position.longitude,
        destLat: widget.latitude!,
        destLng: widget.longitude!,
        profile: 'driving',
      );
      
      if (routeData != null && mounted) {
        final distM = routeData['distance_meters'] as double;
        final durSec = routeData['duration_seconds'] as double;
        
        setState(() {
          _routeDistanceStr = formatDistance(distM);
          if (durSec > 0) {
            final mins = (durSec / 60).round();
            if (mins > 60) {
              final hrs = mins ~/ 60;
              final remMins = mins % 60;
              _routeDurationStr = remMins > 0 ? '$hrs hr $remMins min' : '$hrs hr';
            } else {
              _routeDurationStr = '$mins min';
            }
          }
          _isLoadingRoute = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingRoute = false);
      }
    } catch (e) {
      debugPrint('Error fetching route distance: $e');
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  Future<void> _fetchPlacesDetails() async {
    try {
      // The id is passed through as-is. Whatever kind it is — a Google Place ID,
      // one of our UUIDs, or the name-hash placeholder used when a place arrived
      // without one — the backend resolves it, using Places API (Legacy) Find
      // Place and its own stored mapping. Resolving it here instead meant a
      // /places/search round trip that answered from our database with the same
      // UUID it was given, so the details call could never reach Google.
      final resolvedId = (widget.id != null && widget.id!.isNotEmpty)
          ? widget.id!
          : _placeId;
      final cleanId = resolvedId.replaceFirst('places/', '');
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/$cleanId/details',
        queryParameters: {
          // Resolution hints, used only when the id is not something Google
          // accepts. Ignored otherwise.
          'name': widget.name,
          if (widget.latitude != null && widget.latitude != 0.0) 'lat': widget.latitude,
          if (widget.longitude != null && widget.longitude != 0.0) 'lng': widget.longitude,
        },
        // This is enrichment, not core content — the page already has name,
        // rating and category without it. The app-wide 60s timeout left users
        // staring at shimmer for up to a minute whenever this call queued
        // behind other Google-bound requests; failing fast here means they see
        // the "no reviews/hours available" fallback in a few seconds instead,
        // and can still use the page while this was never going to be quick.
        options: Options(
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>?;
        if (data != null) {
          final openNowText = data['open_now_text'] as String?;
          final closingTime = data['closing_time'] as String?;
          final totalReviews = data['user_ratings_total'] as int?;
          final priceLevel = data['price_level'] as String?;
          final weekday = (data['weekday_hours'] as List?)?.cast<String>() ?? [];
          final rawReviews = (data['reviews'] as List?)?.cast<Map>() ?? [];
          final reviews = rawReviews.map((r) => Map<String, dynamic>.from(r)).toList();
          final photoUrls = (data['photo_urls'] as List?)?.cast<String>() ?? [];
          final String? firstPhoto = photoUrls.isNotEmpty ? photoUrls[0] : null;

          if (mounted) {
            setState(() {
              _openNowText = openNowText;
              _closingTime = closingTime;
              _totalReviews = totalReviews;
              _priceLevel = priceLevel;
              _realReviews = reviews;
              _weekdayHours = weekday;
              if ((_resolvedImageUrl == null || _resolvedImageUrl!.isEmpty) && firstPhoto != null) {
                _resolvedImageUrl = firstPhoto;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Places detail error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPlaces = false);
      }
    }
  }

  Future<void> _launchNavigation(BuildContext context) async {
    if (widget.latitude == null || widget.longitude == null ||
        (widget.latitude == 0.0 && widget.longitude == 0.0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📍 Location coordinates not available for this place'),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartTourismMapPage(
          initialLat: widget.latitude!,
          initialLng: widget.longitude!,
          destinationName: widget.name,
        ),
      ),
    );
  }

  Future<void> _launchGoogleMaps() async {
    if (widget.latitude == null || widget.longitude == null ||
        (widget.latitude == 0.0 && widget.longitude == 0.0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('📍 Location coordinates not available for this place'),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoogleMapsPage(
          initialLat: widget.latitude!,
          initialLng: widget.longitude!,
          destinationName: widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = CacheService.isPlaceFavorite(_placeId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.3),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final map = {
                    'id': _placeId,
                    'name': widget.name,
                    'category_name': widget.category,
                    'rating': widget.rating,
                    'photo_urls': _resolvedImageUrl != null ? [_resolvedImageUrl!] : <String>[],
                    'latitude': widget.latitude ?? 0.0,
                    'longitude': widget.longitude ?? 0.0,
                    'created_at': DateTime.now().toIso8601String(),
                  };
                  await CacheService.toggleFavoritePlace(map);
                  if (mounted) setState(() {});
                },
                child: Container(
                  margin: const EdgeInsets.all(8),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.3),
                  ),
                  child: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                    color: isFav ? const Color(0xFFFF2D55) : Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PlaceImageHelper.buildPlaceImage(
                    imagePath: _resolvedImageUrl,
                    category: widget.category,
                    name: widget.name,
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.transparent,
                          AppColors.background,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category tag
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.actionTeal.withOpacity(0.1),
                        ),
                        child: Text(
                          widget.category.toUpperCase(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.actionTeal, letterSpacing: 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.star_rounded, size: 18, color: AppColors.ratingGold),
                      const SizedBox(width: 4),
                      Text('${widget.rating}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1, height: 1.1),
                  ),

                  if (_openNowText != null && _openNowText!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: _openNowText == 'Open' ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _openNowText == 'Open' ? 'Open' : 'Closed',
                          style: TextStyle(
                            fontSize: 13,
                            color: _openNowText == 'Open' ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),



                  const SizedBox(height: 28),

                  // AI Experience Insights if available
                  if (widget.aiWhy != null) ...[
                    _buildAiExperienceSection(),
                    const SizedBox(height: 16),
                  ],

                  // History and Cultural Tips removed as requested.

                  // Opening Hours
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingPlaces
                        ? _buildSkeletonSection(key: const ValueKey('hours_skel'))
                        : _weekdayHours.isNotEmpty
                            ? _buildOpeningHoursCard(key: const ValueKey('hours_real'))
                            : _buildEmptyStateCard('Opening Hours', Icons.schedule_rounded, 'No opening hours available for this location.', key: const ValueKey('hours_none')),
                  ),
                  const SizedBox(height: 16),

                  // Visitor Reviews
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingPlaces
                        ? _buildSkeletonSection(key: const ValueKey('rev_skel'))
                        : _realReviews.isNotEmpty
                            ? _buildReviewsCard(key: const ValueKey('rev_real'))
                            : _buildEmptyStateCard('Visitor Reviews', Icons.rate_review_rounded, 'No reviews available yet.', key: const ValueKey('rev_none')),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom action bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            // Smart Map button
            Expanded(
              child: GestureDetector(
                onTap: () => _launchNavigation(context),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.black,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text('Smart Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Google Map button
            Expanded(
              child: GestureDetector(
                onTap: _launchGoogleMaps,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.black,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text('Google Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // AR button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArCameraPage(
                    initialPlace: {
                      'name': widget.name,
                      'category': widget.category,
                      'distance': widget.distance.contains('9049') ? 'Nearby' : widget.distance,
                      'distanceM': 0.0,
                      'rating': widget.rating,
                      'latitude': widget.latitude,
                      'longitude': widget.longitude,
                      'imageUrl': _resolvedImageUrl ?? widget.imageUrl,
                      'description': widget.aiWhy ?? '',
                    },
                  ),
                ),
              ),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withOpacity(0.1)),
                  color: AppColors.surfaceVariant,
                ),
                child: const Icon(Icons.view_in_ar_rounded, color: Colors.black, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonSection({Key? key}) {
    return Container(key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 14, width: 120, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 14),
          Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 10, width: 220, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 10, width: 180, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: Colors.white54);
  }

  Widget _buildEmptyStateCard(String title, IconData icon, String message, {Key? key}) {
    return Container(key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningHoursCard({Key? key}) {
    return Container(key: key,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: AppColors.textPrimary),
              SizedBox(width: 10),
              Text('Opening Hours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          ..._weekdayHours.map((h) {
            final parts = h.split(': ');
            final day = parts.isNotEmpty ? parts[0] : h;
            final time = parts.length > 1 ? parts[1] : '';
            return _buildHourRow(day, time);
          }),
        ],
      ),
    );
  }

  Widget _buildReviewsCard({Key? key}) {
    return Container(key: key,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Visitor Reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          ..._realReviews.asMap().entries.map((e) {
            final r = e.value;
            return Column(
              children: [
                if (e.key > 0) const Divider(color: AppColors.border, height: 24),
                _buildReview(
                  r['author'] as String,
                  r['rating'] as double,
                  r['text'] as String,
                  r['time'] as String,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }



  Widget _buildInfoSection(String title, IconData icon, String content, {Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.actionTeal),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildHourRow(String day, String hours) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(day, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              hours, 
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(String name, double stars, String text, String time) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black12,
              ),
              child: Center(child: Text(name[0], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 14))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(Icons.star_rounded, size: 12, color: i < stars ? AppColors.ratingGold : Colors.black12)),
                      const SizedBox(width: 8),
                      Text(time, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
      ],
    );
  }


  Widget _buildAiExperienceSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.ratingGold.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ratingGold.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'AI Experience Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ratingGold,
                ),
              ),
              const Spacer(),
              if (widget.aiConfidence != null && widget.aiConfidence!.trim().isNotEmpty)
                (() {
                  final cleanConf = widget.aiConfidence!.replaceAll(RegExp(r'[\s\-]+$'), '');
                  if (cleanConf.isEmpty) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ratingGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.ratingGold.withOpacity(0.3)),
                    ),
                    child: Text(
                      '$cleanConf Match',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ratingGold,
                      ),
                    ),
                  );
                })(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.aiWhy!,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _shortenCost(String cost) {
    if (cost.toLowerCase() == 'n/a') return 'N/A';
    String cleaned = cost.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^(estimated|approx|approx\.|about|around)\s+', caseSensitive: false), '').trim();
    if (cleaned.length > 20) {
      final match = RegExp(r'(\d+[\d,]*\s*(?:-|to)\s*\d+[\d,]*)').firstMatch(cleaned);
      if (match != null) {
        final currencyMatch = RegExp(r'\b([A-Z]{3}|Rs\.?|\$)\b').firstMatch(cleaned);
        if (currencyMatch != null) {
          return '${currencyMatch.group(1)} ${match.group(1)}';
        }
        return match.group(1) ?? cleaned;
      }
      return cleaned.substring(0, 17) + '...';
    }
    return cleaned;
  }

  Widget _buildHorizontalStatRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.actionTeal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.actionTeal),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
