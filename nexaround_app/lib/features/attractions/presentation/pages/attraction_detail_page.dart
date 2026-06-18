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

  // ── Gemini data ──
  bool _isLoadingGemini = true;
  String? _historyText;
  String? _culturalTips;
  String? _avgVisit;
  String? _crowdLevel;

  @override
  void initState() {
    super.initState();
    _resolvedImageUrl = widget.imageUrl;
    _totalReviews = widget.reviewCount;
    _fetchPlacesDetails();
  }

  Future<void> _fetchPlacesDetails() async {
    List<String> types = [];
    String? summaryText;
    try {
      // Use place_id if it looks like a real Google place ID, else find by name+location
      String? resolvedId = widget.id;
      if (resolvedId == null || resolvedId.length < 10 || int.tryParse(resolvedId) != null) {
        resolvedId = await _findPlaceId();
      }
      if (resolvedId != null) {
        final fields = 'opening_hours,user_ratings_total,price_level,reviews,editorial_summary,types,photos';
        final response = await ApiClient.instance.get(
          '${ApiConstants.googleMapsProxy}/place/details/json',
          queryParameters: {
            'place_id': resolvedId,
            'fields': fields,
          },
        );
        if (response.statusCode == 200) {
          final data = response.data['result'] as Map<String, dynamic>?;
          if (data != null) {
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

            types = (data['types'] as List?)?.cast<String>() ?? [];
            final summaryMap = data['editorial_summary'] as Map<String, dynamic>?;
            summaryText = summaryMap?['overview'] as String?;

            // Retrieve photo if local photo is null/empty
            String? fetchedPhotoUrl;
            final photos = data['photos'] as List? ?? [];
            if (photos.isNotEmpty) {
              final ref = photos[0]['photo_reference'] as String?;
              if (ref != null && ref.isNotEmpty) {
                fetchedPhotoUrl = '/api/v1/places/photo?ref=$ref';
              }
            }

            if (mounted) {
              setState(() {
                _openNowText = openNow == null ? null : (openNow ? 'Open' : 'Closed');
                _closingTime = closingTime;
                _totalReviews = data['user_ratings_total'] as int?;
                _priceLevel = priceText;
                _realReviews = List<Map<String, dynamic>>.from(reviews);
                _weekdayHours = weekday;
                if ((_resolvedImageUrl == null || _resolvedImageUrl!.isEmpty) && fetchedPhotoUrl != null) {
                  _resolvedImageUrl = fetchedPhotoUrl;
                }
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Places detail error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPlaces = false);
      }
      if (widget.aiWhy == null) {
        _fetchGeminiInfo(types: types, summary: summaryText);
      } else {
        if (mounted) {
          setState(() => _isLoadingGemini = false);
        }
      }
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

  Future<void> _fetchGeminiInfo({List<String> types = const [], String? summary}) async {
    try {
      final locationHint = (widget.latitude != null && widget.longitude != null)
          ? ' at coordinates (${widget.latitude}, ${widget.longitude})'
          : '';

      String contextHint = '';
      if (types.isNotEmpty) {
        contextHint += 'Google Maps Place Types: ${types.join(', ')}. ';
      }
      if (summary != null && summary.isNotEmpty) {
        contextHint += 'Google Maps Editorial Summary: "$summary". ';
      }

      final prompt =
          'For the place named "${widget.name}" (category: ${widget.category})$locationHint. '
          '${contextHint.isNotEmpty ? 'Additional context about this place from Google Maps: $contextHint' : ''}'
          'Please note: if the name, types, or summary suggest this is a private residential area, housing complex, housing society, apartment complex, or gated community (and not a public attraction/monument/park/museum), you must clearly describe it as such in the "history" field (e.g. "Arackal is a residential housing complex...") and state that it is a residential area with no public historical or tourist attractions inside. '
          'Give me ONLY a JSON object (no markdown) with these fields: '
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
            actions: [
              GestureDetector(
                onTap: () async {
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
                  await CacheService.toggleSavedPlace(map);
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
                    isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: isSaved ? AppColors.ratingGold : Colors.white,
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
                      if (_isLoadingPlaces) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Container(width: 100, height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6))),
                      ] else if (_openNowText != null && _openNowText!.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          _openNowText == 'Open'
                              ? 'Open${_closingTime != null ? ' · Closes $_closingTime' : ''}'
                              : 'Closed',
                          style: TextStyle(fontSize: 13, color: _openNowText == 'Open' ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Stats Section as wrapping badges
                  (() {
                    final displayCost = _isLoadingPlaces ? '...' : (_priceLevel ?? widget.aiCost ?? 'N/A');
                    final displayAvgVisit = _isLoadingGemini ? '...' : (_avgVisit ?? widget.aiWhen ?? 'N/A');
                    final displayCrowd = _isLoadingGemini ? '...' : (_crowdLevel ?? 'N/A');

                    Widget buildStatBadge(IconData icon, String title, String value, bool isLoading) {
                      if (isLoading) {
                        return Container(
                          width: 140,
                          height: 56,
                          margin: const EdgeInsets.only(right: 12, bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: Colors.white54);
                      }
                      
                      return Container(
                        margin: const EdgeInsets.only(right: 12, bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 18, color: AppColors.actionTeal),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    value,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Wrap(
                      children: [
                        buildStatBadge(Icons.attach_money_rounded, 'ENTRY FEE', displayCost, _isLoadingPlaces),
                        buildStatBadge(Icons.schedule_rounded, 'WHEN TO VISIT', displayAvgVisit.isEmpty ? 'N/A' : displayAvgVisit, _isLoadingGemini),
                        buildStatBadge(Icons.people_rounded, 'CROWD LEVEL', displayCrowd.isEmpty ? 'N/A' : displayCrowd, _isLoadingGemini),
                      ],
                    );
                  })(),

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
                            : _buildEmptyStateCard('Opening Hours', Icons.schedule_rounded, 'No opening hours available', key: const ValueKey('hours_none')),
                  ),
                  const SizedBox(height: 16),

                  // Visitor Reviews
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _isLoadingPlaces
                        ? _buildSkeletonSection(key: const ValueKey('rev_skel'))
                        : _realReviews.isNotEmpty
                            ? _buildReviewsCard(key: const ValueKey('rev_real'))
                            : _buildEmptyStateCard('Reviews', Icons.star_rounded, 'No reviews available', key: const ValueKey('rev_none')),
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
    // Remove parentheses and everything inside
    String cleaned = cost.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    // Remove common prefix words
    cleaned = cleaned.replaceAll(RegExp(r'^(estimated|approx|approx\.|about|around)\s+', caseSensitive: false), '').trim();
    // If still very long (more than 20 chars), try to find a number range
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
