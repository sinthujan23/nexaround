import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:url_launcher/url_launcher.dart';

class FlightStrategiesSection extends StatelessWidget {
  final Odyssey odyssey;

  const FlightStrategiesSection({
    super.key,
    required this.odyssey,
  });

  @override
  Widget build(BuildContext context) {
    if (odyssey.flightStrategies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.flight_takeoff_rounded,
                color: Colors.black,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'CHEAPEST FLIGHT OPTIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...odyssey.flightStrategies.map((fs) => _buildStrategyCard(context, fs)),
        if (odyssey.flightGeneralTips.isNotEmpty || odyssey.flightBestMonths.isNotEmpty)
          _buildTipsCard(context),
      ],
    ).animate().fade().slideY(begin: 0.05, end: 0);
  }

  Widget _buildStrategyCard(BuildContext context, FlightStrategy fs) {
    // Deduce rank icon / color
    IconData rankIcon = Icons.looks_one_rounded;
    Color rankColor = const Color(0xFFFFD700); // Gold
    if (fs.rank == 2) {
      rankIcon = Icons.looks_two_rounded;
      rankColor = const Color(0xFFC0C0C0); // Silver
    } else if (fs.rank == 3) {
      rankIcon = Icons.looks_3_rounded;
      rankColor = const Color(0xFFCD7F32); // Bronze
    }

    // Deduce strategy icon
    IconData strategyIcon = Icons.shuffle_rounded;
    if (fs.strategy == 'direct') {
      strategyIcon = Icons.flight_rounded;
    } else if (fs.strategy == 'budget_carrier') {
      strategyIcon = Icons.savings_rounded;
    } else if (fs.strategy == 'nearby_airport') {
      strategyIcon = Icons.place_rounded;
    }

    // Clean convenience stars from any trailing text
    String convenienceStars = fs.convenience.split(' ').firstWhere(
          (s) => s.contains('★') || s.contains('☆'),
          orElse: () => fs.convenience,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
            // Top Row: Rank Icon + Title + Savings Badge stacked cleanly
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(rankIcon, color: rankColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fs.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      if (fs.estimatedSavings.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.ratingGold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatPriceString(fs.estimatedSavings),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Route & Price Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(strategyIcon, color: Colors.black54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fs.route,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (fs.priceRange.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatPriceString(fs.priceRange),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Detailed description
            if (fs.description.isNotEmpty)
              Text(
                fs.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),

            // Airlines tag list
            if (fs.airlines.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fs.airlines.map((airline) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      airline,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],

            // Duration, stops & convenience wrap
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (fs.duration.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded, size: 14, color: Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        fs.duration,
                        style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.airline_stops_rounded, size: 14, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      fs.stops == 0 ? 'Direct' : '${fs.stops} stop${fs.stops > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (convenienceStars.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Convenience: ',
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                      Text(
                        convenienceStars,
                        style: const TextStyle(fontSize: 12, color: Colors.black87, letterSpacing: 1),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Tip box
            if (fs.tip.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.actionTeal.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.actionTeal.withValues(alpha: 0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: AppColors.actionTeal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fs.tip,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Button: Direct Booking Link
            if (fs.bookingUrl.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  String provider = fs.providerName.trim();
                  if (provider.isEmpty) {
                    final lowerUrl = fs.bookingUrl.toLowerCase();
                    if (lowerUrl.contains('expedia')) {
                      provider = 'Expedia';
                    } else if (lowerUrl.contains('skyscanner')) {
                      provider = 'Skyscanner';
                    } else if (lowerUrl.contains('google')) {
                      provider = 'Google Flights';
                    } else if (lowerUrl.contains('kayak')) {
                      provider = 'Kayak';
                    } else {
                      provider = 'Flight Provider';
                    }
                  }
                  final deepUrl = BookingUrlHelper.buildFlightUrl(
                    rawUrl: fs.bookingUrl,
                    providerName: provider,
                    strategyTitle: fs.title,
                    destination: odyssey.destination,
                    departureCity: odyssey.departureCity,
                    startDate: odyssey.startDate ?? '',
                    endDate: odyssey.endDate ?? '',
                    travelers: odyssey.travelers,
                    route: fs.route,
                    airlines: fs.airlines,
                  );
                  final logoPath = _getProviderLogoPath(provider);
                  return SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _launchUrl(context, deepUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (logoPath != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                logoPath,
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              'Book Flight on $provider',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns the asset path for a provider logo, or null if none exists yet.
  static String? _getProviderLogoPath(String providerName) {
    final name = providerName.toLowerCase().trim();
    if (name.contains('booking')) return 'assets/images/booking_logo.jpg';
    if (name.contains('uber')) return 'assets/images/uber_logo.png';
    if (name.contains('headout')) return 'assets/images/headout.png';
    if (name.contains('skyscanner')) return 'assets/images/skyscanner.png';
    if (name.contains('getyourguide')) return 'assets/images/getyourguide.png';
    if (name.contains('viator')) return 'assets/images/viator.png';
    // Future logos — uncomment when assets are added:
    // if (name.contains('expedia')) return 'assets/images/expedia_logo.png';
    // if (name.contains('kayak')) return 'assets/images/kayak_logo.png';
    // if (name.contains('google')) return 'assets/images/google_flights_logo.png';
    return null;
  }

  Widget _buildTipsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.black87),
                  SizedBox(width: 8),
                  Text(
                    'Flight Planning Insights',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (odyssey.flightBestMonths.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Best months: ${odyssey.flightBestMonths}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (odyssey.flightGeneralTips.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...odyssey.flightGeneralTips.map((tip) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: CircleAvatar(
                        radius: 3,
                        backgroundColor: Colors.black54,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tip,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    // Ensure url has a proper scheme
    var sanitized = urlString.trim();
    if (sanitized.isNotEmpty &&
        !sanitized.startsWith('http://') &&
        !sanitized.startsWith('https://')) {
      sanitized = 'https://$sanitized';
    }
    final uri = Uri.tryParse(sanitized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid booking link: $urlString')),
        );
      }
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to platform default
        final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open booking link: $sanitized')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $sanitized')),
        );
      }
    }
  }
}

