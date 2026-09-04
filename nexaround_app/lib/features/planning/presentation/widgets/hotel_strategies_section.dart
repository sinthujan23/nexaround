import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/utils/scenario_price_mapper.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

class HotelStrategiesSection extends StatelessWidget {
  final Odyssey odyssey;

  /// Currently selected budget scenario ('minimum' | 'recommended' | 'comfortable').
  /// When set, the matching hotel option is highlighted and shown first.
  final String? highlightScenario;

  const HotelStrategiesSection({
    super.key,
    required this.odyssey,
    this.highlightScenario,
  });

  @override
  Widget build(BuildContext context) {
    if (odyssey.hotelStrategies.isEmpty) {
      return const SizedBox.shrink();
    }

    // Grouped by the city leg the hotel was searched for.
    //
    // The backend searches hotels once per leg and tags each result with its
    // leg. Rendering them as one flat list is what showed a Siem Reap hotel and
    // a Sihanoukville hotel side by side against every day of a Cambodia trip,
    // with no indication that they are for different cities.
    //
    // Odysseys generated before legs existed have no `legIndex`, and fall into
    // a single group keyed -1 — which renders exactly as this list used to.
    final grouped = <int, List<HotelStrategy>>{};
    for (final hs in odyssey.hotelStrategies) {
      grouped.putIfAbsent(hs.legIndex ?? -1, () => []).add(hs);
    }
    final legKeys = grouped.keys.toList()..sort();

    /// Price tiers are scoped to the leg, not to the trip.
    ///
    /// Ranking every city's hotels together makes the cheapest city's rooms
    /// look like the "minimum" tier everywhere and the dearest city's the
    /// "comfortable" one, when what the traveller is choosing between is the
    /// options *in the city they are in that night*.
    List<(HotelStrategy, String?)> cardsFor(List<HotelStrategy> group) {
      final tags = mapPricesToScenarios(
        group.map((hs) => parseRepresentativePrice(hs.pricePerNight)).toList(),
      );
      final cards = List.generate(group.length, (i) => (group[i], tags[i]));
      if (highlightScenario != null) {
        cards.sort((a, b) {
          final aMatch = a.$2 == highlightScenario ? 0 : 1;
          final bMatch = b.$2 == highlightScenario ? 0 : 1;
          return aMatch.compareTo(bMatch);
        });
      }
      return cards;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
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
        ...legKeys.expand((key) {
          final group = grouped[key]!;
          final first = group.first;
          return [
            // Only labelled when there is something to distinguish. A
            // single-leg trip — or a pre-legs Odyssey — reads as before.
            if (legKeys.length > 1 && first.city.isNotEmpty)
              _buildLegHeader(first.city, first.nights, first.rooms),
            ...cardsFor(group).map((c) => _buildHotelCard(context, c.$1, c.$2)),
          ];
        }),

        // General Tips / Best Areas Card
        if (odyssey.hotelGeneralTips.isNotEmpty || odyssey.hotelBestAreas.isNotEmpty)
          _buildTipsCard(context),
      ],
    );
  }

  /// City heading above each leg's hotels.
  ///
  /// Carries the nights and rooms because "Est. Total" is
  /// `nights x rooms x nightly` for *this leg* — without them the figure reads
  /// as a whole-trip price, which is how a 2-night stay came across as nine
  /// nights' worth.
  Widget _buildLegHeader(String city, int nights, int rooms) {
    final parts = <String>[
      if (nights > 0) '$nights ${nights == 1 ? 'night' : 'nights'}',
      if (rooms > 0) '$rooms ${rooms == 1 ? 'room' : 'rooms'}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            city,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              parts.join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHotelCard(BuildContext context, HotelStrategy hs, String? scenarioTag) {
    final isHighlighted = highlightScenario != null && scenarioTag == highlightScenario;
    const scenarioLabels = {
      'minimum': 'MINIMUM BUDGET PICK',
      'recommended': 'RECOMMENDED PICK',
      'comfortable': 'COMFORTABLE PICK',
    };
    String provider = hs.providerName.trim();
    if (provider.isEmpty || provider.toLowerCase() == 'hotel provider') {
      final lowerUrl = hs.bookingUrl.toLowerCase();
      if (lowerUrl.contains('google')) {
        provider = 'Google Hotels';
      } else if (lowerUrl.contains('agoda')) {
        provider = 'Agoda';
      } else if (lowerUrl.contains('expedia')) {
        provider = 'Expedia';
      } else if (lowerUrl.contains('hotels.com')) {
        provider = 'Hotels.com';
      } else if (lowerUrl.contains('airbnb')) {
        provider = 'Airbnb';
      } else if (lowerUrl.contains('booking')) {
        provider = 'Booking.com';
      } else {
        provider = 'Google Hotels';
      }
    } else if (provider.toLowerCase() == 'google' || provider.toLowerCase() == 'google travel') {
      provider = 'Google Hotels';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isHighlighted ? AppColors.brandGreen : Colors.black12,
          width: isHighlighted ? 2 : 1,
        ),
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
            if (isHighlighted && scenarioTag != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  scenarioLabels[scenarioTag] ?? '',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Header Row: Hotel Icon + Name & Rating + Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.actionTeal.withValues(alpha: 0.12),
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
                                color: AppColors.ratingGold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 12, color: AppColors.ratingGold),
                                  const SizedBox(width: 4),
                                  Text(
                                    hs.reviews > 0
                                        ? '${hs.rating} (${hs.reviews >= 1000 ? "${(hs.reviews / 1000).toStringAsFixed(1)}k" : hs.reviews})'
                                        : hs.rating,
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
                        '~${formatPriceString(hs.pricePerNight, targetCurrency: odyssey.currency)}',
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
                      'Est. Total: ${formatPriceString(hs.totalEstimatedCost, targetCurrency: odyssey.currency)}',
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
                      color: Colors.black.withValues(alpha: 0.04),
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

            // Direct Booking Button (always active with deep pre-filled links)
            Builder(
                builder: (context) {
                  final deepUrl = BookingUrlHelper.buildHotelUrl(
                    rawUrl: hs.bookingUrl,
                    providerName: provider,
                    hotelName: hs.name,
                    destination: odyssey.destination,
                    checkInDate: odyssey.startDate ?? '',
                    checkOutDate: odyssey.endDate ?? '',
                    travelers: odyssey.travelers,
                    serpApiLink: hs.serpApiLink,
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
                              'Book Hotel on $provider',
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
        ),
      ),
    );
  }

  /// Returns the asset path for a provider logo, or null if none exists yet.
  static String? _getProviderLogoPath(String providerName) {
    final name = providerName.toLowerCase().trim();
    if (name.contains('booking')) return 'assets/images/booking_logo.jpg';
    if (name.contains('uber')) return 'assets/images/uber_logo.png';
    if (name.contains('skyscanner')) return 'assets/images/skyscanner.png';
    if (name.contains('getyourguide')) return 'assets/images/getyourguide.png';
    if (name.contains('viator')) return 'assets/images/viator.png';
    // Future logos — uncomment when assets are added:
    // if (name.contains('agoda')) return 'assets/images/agoda_logo.png';
    // if (name.contains('expedia')) return 'assets/images/expedia_logo.png';
    // if (name.contains('airbnb')) return 'assets/images/airbnb_logo.png';
    // if (name.contains('google')) return 'assets/images/google_travel_logo.png';
    return null;
  }

  Widget _buildTipsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
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
                'Accommodation Insights',
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

