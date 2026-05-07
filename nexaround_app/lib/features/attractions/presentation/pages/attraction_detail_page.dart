import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';

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
                      Text(' (2.3k reviews)', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ).animate().fade(),

                  const SizedBox(height: 16),

                  // Name
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1, height: 1.1),
                  ).animate().fade(delay: 100.ms).slideY(begin: 0.1, end: 0),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: AppColors.actionTeal),
                      const SizedBox(width: 4),
                      Text(widget.distance, style: const TextStyle(fontSize: 13, color: AppColors.actionTeal, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time_rounded, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      const Text('Open · Closes 6 PM', style: TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.w600)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quick stats row
                  Row(
                    children: [
                      _buildStatChip(Icons.attach_money_rounded, 'LKR 1,500', 'Entry Fee'),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.schedule_rounded, '3-4 hrs', 'Avg Visit'),
                      const SizedBox(width: 8),
                      _buildStatChip(Icons.people_rounded, 'Low', 'Crowd'),
                      const SizedBox(width: 8),
                      _buildSaveChip(isSaved),
                    ],
                  ).animate().fade(delay: 200.ms),

                  const SizedBox(height: 28),

                  // History section
                  _buildInfoSection(
                    'History',
                    Icons.history_edu_rounded,
                    'This magnificent site dates back centuries, serving as a testament to the rich cultural heritage of Sri Lanka. Originally built as a royal fortress, it has witnessed the rise and fall of ancient kingdoms and stands today as a UNESCO World Heritage Site.',
                  ),

                  const SizedBox(height: 20),

                  // Cultural Info
                  _buildInfoSection(
                    'Cultural Tips',
                    Icons.info_outline_rounded,
                    '• Dress modestly — cover shoulders and knees\n• Remove shoes before entering sacred areas\n• Photography may be restricted in certain zones\n• Guides available in English, Sinhala, and Tamil',
                  ),

                  const SizedBox(height: 20),

                  // Opening Hours
                  Container(
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
                            const SizedBox(width: 10),
                            const Text('Opening Hours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildHourRow('Monday – Friday', '7:00 AM – 6:00 PM'),
                        _buildHourRow('Saturday', '7:00 AM – 5:00 PM'),
                        _buildHourRow('Sunday', '8:00 AM – 4:00 PM'),
                      ],
                    ),
                  ).animate().fade(delay: 400.ms),

                  const SizedBox(height: 20),

                  // User Ratings
                  Container(
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
                        _buildReview('Sarah M.', 5.0, 'Absolutely breathtaking! One of the most beautiful places I\'ve ever visited.', '2 days ago'),
                        const Divider(color: AppColors.border, height: 24),
                        _buildReview('James K.', 4.0, 'Great historical site. The climb is worth it for the views.', '1 week ago'),
                      ],
                    ),
                  ).animate().fade(delay: 500.ms),

                  const SizedBox(height: 120),
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withOpacity(0.1)),
                color: AppColors.surfaceVariant,
              ),
              child: const Icon(Icons.view_in_ar_rounded, color: Colors.black, size: 24),
            ),
          ],
        ),
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
            'photo_urls': [widget.imageUrl],
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

  Widget _buildInfoSection(String title, IconData icon, String content) {
    return Container(
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
    ).animate().fade(delay: 300.ms);
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
