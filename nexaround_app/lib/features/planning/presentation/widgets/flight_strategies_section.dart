import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/utils/scenario_price_mapper.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:url_launcher/url_launcher.dart';

class FlightStrategiesSection extends StatelessWidget {
  final Odyssey odyssey;

  /// Currently selected budget scenario ('minimum' | 'recommended' | 'comfortable').
  /// When set, the matching flight option is highlighted and shown first.
  final String? highlightScenario;

  const FlightStrategiesSection({
    super.key,
    required this.odyssey,
    this.highlightScenario,
  });

  @override
  Widget build(BuildContext context) {
    if (odyssey.flightStrategies.isEmpty) {
      return const SizedBox.shrink();
    }

    final strategies = odyssey.flightStrategies;

    // Odysseys generated since tiered flights landed carry a backend `tier` on
    // each strategy, and each tier is a genuinely different itinerary at a
    // different price. There the toggle *selects* an itinerary. Older
    // Odysseys have no tiers, so fall back to ranking their prices
    // client-side and highlighting the match, which is all the toggle ever
    // did before.
    final tiered = strategies
        .where((fs) => fs.tier != null && fs.tier!.isNotEmpty)
        .toList();
    final bool hasBackendTiers = tiered.length >= 2;

    late final List<(FlightStrategy, String?)> cards;
    late final List<(FlightStrategy, String?)> otherCards;
    var tierUnavailable = false;

    if (hasBackendTiers) {
      final selected = [
        for (final fs in tiered)
          if (fs.tier == highlightScenario) (fs, fs.tier),
      ];
      // A route can genuinely have fewer than three distinct offers — the
      // backend omits a tier rather than repeating one. Show the nearest tier
      // it does have instead of an empty tab.
      tierUnavailable = selected.isEmpty;
      cards = selected.isNotEmpty ? selected : [_nearestTier(tiered)];
      final shown = cards.map((c) => c.$1).toSet();
      otherCards = [
        for (final fs in strategies)
          if (!shown.contains(fs)) (fs, fs.tier),
      ];
    } else {
      final tags = mapPricesToScenarios(
        strategies.map((fs) => parseRepresentativePrice(fs.priceRange)).toList(),
      );
      final legacy = List.generate(strategies.length, (i) => (strategies[i], tags[i]));
      if (highlightScenario != null) {
        legacy.sort((a, b) {
          final aMatch = a.$2 == highlightScenario ? 0 : 1;
          final bMatch = b.$2 == highlightScenario ? 0 : 1;
          return aMatch.compareTo(bMatch);
        });
      }
      cards = legacy;
      otherCards = const [];
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
            Expanded(
              child: Text(
                hasBackendTiers ? _headerForTier(cards.first.$2) : 'CHEAPEST FLIGHT OPTIONS',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        if (tierUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This route has no separate '
              '${(highlightScenario ?? '').toLowerCase()} option — showing the closest match.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 12),
        ...cards.map((c) => _buildStrategyCard(context, c.$1, c.$2)),
        if (otherCards.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'OTHER OPTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ...otherCards.map((c) => _buildStrategyCard(context, c.$1, c.$2)),
        ],
        if (odyssey.flightMoreOptions.isNotEmpty) _buildMoreOptions(context),
        if (odyssey.flightGeneralTips.isNotEmpty || odyssey.flightBestMonths.isNotEmpty)
          _buildTipsCard(context),
      ],
    ).animate().fade().slideY(begin: 0.05, end: 0);
  }

  /// Every other real fare on the route, plainly listed.
  ///
  /// Not cards and not tiers: these are deliberately unranked. The tiers above
  /// only fill when an option beats the others on price, speed or stops, so a
  /// route whose cheapest flight is also its fastest fills two and no more —
  /// and travellers comparing against Google's full list read that as missing
  /// data. Departure and arrival times are shown because they are usually the
  /// reason someone picks one of these over the recommendation.
  Widget _buildMoreOptions(BuildContext context) {
    String hhmm(dynamic raw) {
      final t = (raw ?? '').toString();
      if (t.isEmpty) return '';
      final parts = t.split(' ');
      return parts.length > 1 ? parts.last : t;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'ALL ${odyssey.flightMoreOptions.length + 1 + 1} FARES ON THIS ROUTE',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Live fares we did not rank — pick on airline or timing.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          ...odyssey.flightMoreOptions.map((o) {
            final airlines = ((o['airlines'] as List?) ?? const [])
                .map((e) => e.toString())
                .join(', ');
            final dep = hhmm(o['departure_time']);
            final arr = hhmm(o['arrival_time']);
            final stops = (o['stops'] as num?)?.toInt() ?? 0;
            final price = (o['price_per_traveler'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          airlines.isEmpty ? 'Airline unavailable' : airlines,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (dep.isNotEmpty && arr.isNotEmpty) '$dep → $arr',
                            (o['total_duration'] ?? '').toString(),
                            stops == 0 ? 'Non-stop' : '$stops stop${stops > 1 ? 's' : ''}',
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(o['currency'] ?? '').toString()} ${formatAmount(price.round())}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static const _tierOrder = ['minimum', 'recommended', 'comfortable'];

  /// The closest tier to the one selected, for routes where the backend found
  /// fewer than three genuinely different offers. Ties go to the cheaper side.
  (FlightStrategy, String?) _nearestTier(List<FlightStrategy> tiered) {
    final wantedIndex = _tierOrder.indexOf(highlightScenario ?? 'recommended');
    if (wantedIndex == -1) return (tiered.first, tiered.first.tier);

    var best = tiered.first;
    var bestDistance = 99;
    for (final fs in tiered) {
      final index = _tierOrder.indexOf(fs.tier ?? '');
      if (index == -1) continue;
      final distance = (index - wantedIndex).abs();
      // Strictly-less keeps the earlier (cheaper) tier on a tie, since
      // _tierOrder runs cheapest to dearest.
      if (distance < bestDistance) {
        bestDistance = distance;
        best = fs;
      }
    }
    return (best, best.tier);
  }

  /// Names the tier on show, so the heading can't promise "cheapest" while the
  /// Comfortable tab is open.
  String _headerForTier(String? tier) {
    switch (tier) {
      case 'minimum':
        return 'CHEAPEST FLIGHT OPTION';
      case 'comfortable':
        return 'FASTEST & FEWEST STOPS';
      case 'recommended':
        return 'BEST VALUE FLIGHT';
      default:
        return 'FLIGHT OPTIONS';
    }
  }

  /// The fare, stated on the basis the backend actually priced it on.
  ///
  /// Structured prices are rendered from their own numbers and currency —
  /// never through formatPriceString, which relabels a currency symbol
  /// without converting the amount.
  Widget _buildPriceBlock(FlightStrategy fs) {
    if (!fs.hasStructuredPrice) {
      if (fs.priceRange.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          formatPriceString(fs.priceRange, targetCurrency: odyssey.currency),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.brandGreen,
          ),
        ),
      );
    }

    final currency = fs.currency ?? odyssey.currency;
    final travelers = odyssey.travelers < 1 ? 1 : odyssey.travelers;
    final perTraveler = fs.pricePerTraveler!;
    final total = fs.priceTotal ?? perTraveler * travelers;

    // Google prices the return leg only once an outbound is picked, so the
    // duration we hold is the outbound itinerary's — say so rather than let it
    // read as the whole round trip.
    final facts = <String>[
      fs.isRoundTrip ? 'Round trip' : 'One way',
      if (fs.stops == 0) 'Non-stop' else if (fs.stops == 1) '1 stop' else '${fs.stops} stops',
      if (fs.duration.isNotEmpty)
        fs.isRoundTrip ? '${fs.duration} outbound' : fs.duration,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$currency ${formatAmount(perTraveler)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.brandGreen,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'per traveler',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (travelers > 1) ...[
          const SizedBox(height: 2),
          Text(
            '$currency ${formatAmount(total)} total for $travelers travelers',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          facts.join(' · '),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        if (!fs.isLivePrice) ...[
          const SizedBox(height: 2),
          const Text(
            'Estimated fare — confirm before booking',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStrategyCard(BuildContext context, FlightStrategy fs, String? scenarioTag) {
    final isHighlighted = highlightScenario != null && scenarioTag == highlightScenario;
    const scenarioLabels = {
      'minimum': 'MINIMUM BUDGET PICK',
      'recommended': 'RECOMMENDED PICK',
      'comfortable': 'COMFORTABLE PICK',
    };
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
                            formatPriceString(fs.estimatedSavings, targetCurrency: odyssey.currency),
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
                  _buildPriceBlock(fs),
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

