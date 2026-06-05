import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';

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
  });

  @override
  State<AttractionDetailPage> createState() => _AttractionDetailPageState();
}

class _AttractionDetailPageState extends State<AttractionDetailPage> {
  String get _placeId => widget.id ?? widget.name.hashCode.toString();

  // ── Google Places data ──
  bool _isLoadingPlaces = true;
  String? _openNowText;
  String? _closingTime;
  int? _totalReviews;
  String? _priceLevel;
  List<Map<String, dynamic>> _realReviews = [];
  List<String> _weekdayHours = [];

  // ── Gemini data ──
  bool _isLoadingGemini = true;
  String? _historyText;
  String? _culturalTips;
  String? _avgVisit;
  String? _crowdLevel;

  @override
  void initState() {
    super.initState();
    _fetchPlacesDetails();
    _fetchGeminiInfo();
  }

  Future<void> _fetchPlacesDetails() async {
    try {
      // Use place_id if it looks like a real Google place ID, else find by name+location
      String? resolvedId = widget.id;
      if (resolvedId == null || resolvedId.length < 10 || int.tryParse(resolvedId) != null) {
        resolvedId = await _findPlaceId();
      }
      if (resolvedId == null) {
        if (mounted) setState(() => _isLoadingPlaces = false);
        return;
      }

      final fields = 'opening_hours,user_ratings_total,price_level,reviews,editorial_summary';
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/details/json',
        queryParameters: {
          'place_id': resolvedId,
          'fields': fields,
        },
      );
      if (response.statusCode != 200) {
        if (mounted) setState(() => _isLoadingPlaces = false);
        return;
      }
      final data = response.data['result'] as Map<String, dynamic>?;
      if (data == null) {
        if (mounted) setState(() => _isLoadingPlaces = false);
        return;
      }

      // Opening hours
      final hours = data['opening_hours'] as Map<String, dynamic>?;
      final openNow = hours?['open_now'] as bool?;
      final weekday = (hours?['weekday_text'] as List?)?.cast<String>() ?? [];
      String? closingTime;
      if (openNow == true && weekday.isNotEmpty) {
        final today = weekday[DateTime.now().weekday - 1];
        final match = RegExp(r'–\s*(.+)$').firstMatch(today);
        closingTime = match?.group(1)?.trim();
      }

      // Price level → human readable
      final priceInt = data['price_level'] as int?;
      final priceText = priceInt == null ? null
          : priceInt == 0 ? 'Free'
          : priceInt == 1 ? 'Inexpensive'
          : priceInt == 2 ? 'Moderate'
          : priceInt == 3 ? 'Expensive'
          : 'Very Expensive';

      // Reviews
      final rawReviews = (data['reviews'] as List?)?.cast<Map>() ?? [];
      final reviews = rawReviews.take(3).map((r) => {
        'author': r['author_name'] ?? 'Anonymous',
        'rating': (r['rating'] as num?)?.toDouble() ?? 0.0,
        'text': r['text'] ?? '',
        'time': r['relative_time_description'] ?? '',
      }).toList();

      if (mounted) {
        setState(() {
          _openNowText = openNow == null ? null : (openNow ? 'Open' : 'Closed');
          _closingTime = closingTime;
          _totalReviews = data['user_ratings_total'] as int?;
          _priceLevel = priceText;
          _realReviews = List<Map<String, dynamic>>.from(reviews);
          _weekdayHours = weekday;
          _isLoadingPlaces = false;
        });
      }
    } catch (e) {
      debugPrint('Places detail error: $e');
      if (mounted) setState(() => _isLoadingPlaces = false);
    }
  }

  Future<String?> _findPlaceId() async {
    try {
      final queryParams = {
        'input': widget.name,
        'inputtype': 'textquery',
        'fields': 'place_id',
      };
      if (widget.latitude != null && widget.longitude != null) {
        queryParams['locationbias'] = 'circle:5000@${widget.latitude},${widget.longitude}';
      }
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/findplacefromtext/json',
        queryParameters: queryParams,
      );
      final candidates = response.data['candidates'] as List?;
      return candidates?.isNotEmpty == true ? candidates![0]['place_id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchGeminiInfo() async {
    try {
      final locationHint = (widget.latitude != null && widget.longitude != null)
          ? ' at coordinates (${widget.latitude}, ${widget.longitude})'
          : '';
      final prompt =
          'For the place named "${widget.name}" (category: ${widget.category})$locationHint, '
          'give me ONLY a JSON object (no markdown) with these fields: '
          '{"history":"2-3 sentence history or description","cultural_tips":"bullet-point tips for visitors (use \\n• for each)","avg_visit":"estimated visit duration e.g. 1-2 hrs","crowd":"Low/Medium/High crowd level"}';

      final raw = await GeminiService().getResponse(prompt);
      String cleaned = raw.trim();
      if (cleaned.contains('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'```json?\n?'), '').replaceAll(RegExp(r'\n?```'), '');
      }
      final info = jsonDecode(cleaned) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _historyText = info['history'] as String?;
          _culturalTips = info['cultural_tips'] as String?;
          _avgVisit = info['avg_visit'] as String?;
          _crowdLevel = info['crowd'] as String?;
          _isLoadingGemini = false;
        });
      }
    } catch (e) {
      debugPrint('Gemini detail error: $e');
      if (mounted) setState(() => _isLoadingGemini = false);
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

  @override
  Widget build(BuildContext context) {
    final isSaved = CacheService.isPlaceSaved(_placeId);

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
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PlaceImageHelper.buildPlaceImage(
                    imagePath: widget.imageUrl,
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
                      Text(
                        _totalReviews != null
                            ? ' (${_totalReviews! >= 1000 ? '${(_totalReviews! / 1000).toStringAsFixed(1)}k' : _totalReviews} reviews)'
                            : '',
                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1, height: 1.1),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: AppColors.actionTeal),
                      const SizedBox(width: 4),
                      Text(widget.distance, style: const TextStyle(fontSize: 13, color: AppColors.actionTeal, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time_rounded, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      if (_isLoadingPlaces)
                        Container(width: 100, height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)))
                      else if (_openNowText != null)
                        Text(
                          _openNowText == 'Open'
                              ? 'Open${_closingTime != null ? ' · Closes $_closingTime' : ''}'
                              : 'Closed',
                          style: TextStyle(fontSize: 13, color: _openNowText == 'Open' ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quick stats row
                  Row(
                    children: [
                      _buildStatChip(Icons.attach_money_rounded, _isLoadingPlaces ? '...' : (_priceLevel ?? 'N/A'), 'Entry Fee'),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.schedule_rounded, _isLoadingGemini ? '...' : (_avgVisit ?? 'N/A'), 'Avg Visit'),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.people_rounded, _isLoadingGemini ? '...' : (_crowdLevel ?? 'N/A'), 'Crowd'),
                      const SizedBox(width: 8),
                      _buildSaveChip(isSaved),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // History section
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingGemini
                        ? _buildSkeletonSection(key: const ValueKey('hist_skel'))
                        : _historyText != null
                            ? _buildInfoSection('History', Icons.history_edu_rounded, _historyText!, key: const ValueKey('hist_real'))
                            : const SizedBox.shrink(key: ValueKey('hist_none')),
                  ),
                  const SizedBox(height: 16),

                  // Cultural Tips
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingGemini
                        ? _buildSkeletonSection(key: const ValueKey('tips_skel'))
                        : _culturalTips != null
                            ? _buildInfoSection('Cultural Tips', Icons.info_outline_rounded, _culturalTips!, key: const ValueKey('tips_real'))
                            : const SizedBox.shrink(key: ValueKey('tips_none')),
                  ),
                  const SizedBox(height: 16),

                  // Opening Hours
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingPlaces
                        ? _buildSkeletonSection(key: const ValueKey('hours_skel'))
                        : _weekdayHours.isNotEmpty
                            ? _buildOpeningHoursCard(key: const ValueKey('hours_real'))
                            : const SizedBox.shrink(key: ValueKey('hours_none')),
                  ),
                  const SizedBox(height: 16),

                  // Visitor Reviews
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingPlaces
                        ? _buildSkeletonSection(key: const ValueKey('rev_skel'))
                        : _realReviews.isNotEmpty
                            ? _buildReviewsCard(key: const ValueKey('rev_real'))
                            : const SizedBox.shrink(key: ValueKey('rev_none')),
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
            // Navigate button
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
                        Icon(Icons.map_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text('View on Smart Map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // AR button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArCameraPage(
                    initialPlace: {
                      'name': widget.name,
                      'category': widget.category,
                      'distance': widget.distance,
                      'distanceM': 0.0,
                      'rating': widget.rating,
                      'latitude': widget.latitude,
                      'longitude': widget.longitude,
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

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.actionTeal),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveChip(bool isSaved) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          final map = {
            'id': _placeId,
            'name': widget.name,
            'category_name': widget.category,
            'rating': widget.rating,
            'photo_urls': widget.imageUrl != null ? [widget.imageUrl!] : <String>[],
            'latitude': widget.latitude ?? 0.0,
            'longitude': widget.longitude ?? 0.0,
            'created_at': DateTime.now().toIso8601String(),
          };
          await CacheService.toggleSavedPlace(map);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          decoration: BoxDecoration(
            color: isSaved ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSaved ? AppColors.primary.withOpacity(0.3) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, 
                size: 18, 
                color: isSaved ? AppColors.primary : AppColors.actionTeal
              ),
              const SizedBox(height: 8),
              Text(isSaved ? 'Saved' : 'Save', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isSaved ? AppColors.primary : AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('To Profile', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ],
          ),
        ),
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
        children: [
          Text(day, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(hours, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
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
}
