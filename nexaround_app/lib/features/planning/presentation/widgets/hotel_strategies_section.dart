import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

class HotelStrategiesSection extends StatelessWidget {
  final Odyssey odyssey;

  const HotelStrategiesSection({
    super.key,
    required this.odyssey,
  });

  @override
  Widget build(BuildContext context) {
    if (odyssey.hotelStrategies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.hotel_rounded,
                color: Colors.black87,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOTEL RECOMMENDATIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Colors.black54,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Recommended Stays & Booking Deals',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // List of Hotel Cards
        ...odyssey.hotelStrategies.map((hs) => _buildHotelCard(context, hs)),

        // General Tips / Best Areas Card
        if (odyssey.hotelGeneralTips.isNotEmpty || odyssey.hotelBestAreas.isNotEmpty)
          _buildTipsCard(context),
      ],
    );
  }

  Widget _buildHotelCard(BuildContext context, HotelStrategy hs) {
    String provider = hs.providerName.trim();
    if (provider.isEmpty) {
      final lowerUrl = hs.bookingUrl.toLowerCase();
      if (lowerUrl.contains('booking.com')) {
        provider = 'Booking.com';
      } else if (lowerUrl.contains('agoda')) {
        provider = 'Agoda';
      } else if (lowerUrl.contains('expedia')) {
        provider = 'Expedia';
      } else if (lowerUrl.contains('hotels.com')) {
        provider = 'Hotels.com';
      } else if (lowerUrl.contains('airbnb')) {
        provider = 'Airbnb';
      } else {
        provider = 'Hotel Provider';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Hotel Icon + Name & Rating + Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.actionTeal.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.apartment_rounded, color: AppColors.actionTeal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hs.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (hs.rating.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.ratingGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 12, color: AppColors.ratingGold),
                                  const SizedBox(width: 4),
                                  Text(
                                    hs.rating,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          if (hs.category.isNotEmpty)
                            Text(
                              hs.category,
                              style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hs.pricePerNight.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hs.pricePerNight,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandGreen,
                        ),
                      ),
                      const Text(
                        'per night',
                        style: TextStyle(fontSize: 10, color: Colors.black45),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Description
            if (hs.description.isNotEmpty)
              Text(
                hs.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),

            // Location & Total Cost
            if (hs.location.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.location_on_rounded, size: 14, color: Colors.black45),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      hs.location,
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (hs.totalEstimatedCost.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Est. Total: ${hs.totalEstimatedCost}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),

            // Amenities
            if (hs.amenities.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: hs.amenities.map((amenity) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      amenity,
                      style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Direct Booking Button
            if (hs.bookingUrl.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(context, hs.bookingUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white),
                  label: Text(
                    'Book Hotel on $provider',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'AI Accommodation Insights',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (odyssey.hotelBestAreas.isNotEmpty) ...[
            Text(
              'Best areas to stay: ${odyssey.hotelBestAreas}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 8),
          ],
          if (odyssey.hotelGeneralTips.isNotEmpty)
            ...odyssey.hotelGeneralTips.map((tip) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open hotel link: $urlString')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching URL: $e')),
        );
      }
    }
  }
}
