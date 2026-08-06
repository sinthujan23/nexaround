import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';
import 'package:nexaround_app/core/widgets/converted_currency_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/flight_strategies_section.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/hotel_strategies_section.dart';


/// Renders a generated/saved [Odyssey] as a scrollable blueprint. Shared by the
/// planner's result step and the saved-odyssey detail page.
class OdysseyPlanView extends StatelessWidget {
  final Odyssey odyssey;
  final EdgeInsetsGeometry padding;

  /// When provided, each activity shows an edit button that asks the AI to swap
  /// that place. Called with the zero-based (dayIndex, activityIndex). When
  /// null the plan is read-only (e.g. the planner preview).
  final void Function(int dayIndex, int activityIndex)? onSwapActivity;
  final String? swappingKey;
  final void Function(int dayIndex, int activityIndex)? onToggleVisited;

  /// When provided, each dynamic booking partner shows an edit/swap button
  /// to ask the AI for a replacement.
  final void Function(String partnerName)? onSwapPartner;

  /// Name of the partner currently being swapped, so it can show a spinner.
  final String? swappingPartnerName;

  const OdysseyPlanView({
    super.key,
    required this.odyssey,
    this.padding = const EdgeInsets.all(24),
    this.onSwapActivity,
    this.swappingKey,
    this.onToggleVisited,
    this.onSwapPartner,
    this.swappingPartnerName,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ratingGold,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'AI GENERATED ODYSSEY',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            odyssey.title,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (odyssey.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              odyssey.summary,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (odyssey.formattedDateRange.isNotEmpty)
            _infoCard(
              'Trip Dates & Duration',
              '${odyssey.formattedDateRange} (${odyssey.days} ${odyssey.days == 1 ? 'Day' : 'Days'}${odyssey.nights > 0 ? ' / ${odyssey.nights} ${odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''})',
              Icons.calendar_month_rounded,
            )
          else
            _infoCard(
              'Duration',
              '${odyssey.days} ${odyssey.days == 1 ? 'Day' : 'Days'}'
                  '${odyssey.nights > 0 ? ' / ${odyssey.nights} ${odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''}',
              Icons.wb_sunny_rounded,
            ),
          if (odyssey.travelers > 0)
            _infoCard(
              'Travelers / Group Size',
              '${odyssey.travelers} ${odyssey.travelers == 1 ? 'Traveler (1 Pax)' : 'Travelers (${odyssey.travelers} Pax)'}',
              Icons.people_rounded,
            ),
          if (odyssey.destination.isNotEmpty)
            _infoCard('Destination', odyssey.destination, Icons.place_rounded),
          if (odyssey.visa.isNotEmpty)
            _infoCard('Visa / Entry', odyssey.visa, Icons.description_rounded),
          if (odyssey.budgetSplit.isNotEmpty)
            _infoCard('Budget Summary', odyssey.budgetSplit, Icons.pie_chart_rounded),
          if (odyssey.budget > 0)
            _budgetBreakdownCard(context),
          if (odyssey.budgetAdvisory.isNotEmpty)
            _budgetAdvisoryCard(context),
          const SizedBox(height: 16),
          const Text(
            'ODYSSEY BOOKING PARTNERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _buildBookingSection(context),
          FlightStrategiesSection(odyssey: odyssey),
          HotelStrategiesSection(odyssey: odyssey),
          if (odyssey.dayPlans.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'DAY-BY-DAY ITINERARY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            if (onToggleVisited != null) _buildProgress(),
            const SizedBox(height: 12),
            ...odyssey.dayPlans.asMap().entries.map(
                  (e) => _dayCard(e.key, e.value)
                      .animate()
                      .fade(delay: (80 * e.key).ms)
                      .slideY(begin: 0.1, end: 0),
                ),
          ],
          if (odyssey.logistics.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'LOGISTICS BLUEPRINT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                odyssey.logistics,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetBreakdownCard(BuildContext context) {
    final bd = odyssey.budgetBreakdown;
    final currency = odyssey.currency;
    final total = (bd['total'] ?? 0) > 0 ? (bd['total']!) : odyssey.budget;

    // Default category estimates if breakdown dictionary is empty
    final stay = bd['stay'] ?? (total * 0.35);
    final transit = bd['transit'] ?? (total * 0.30);
    final food = bd['food'] ?? (total * 0.20);
    final activities = bd['activities'] ?? (total * 0.15);

    double percent(double val) => total > 0 ? (val / total).clamp(0.0, 1.0) : 0.25;

    Widget categoryBar(String name, String emoji, double val, Color color) {
      final p = (percent(val) * 100).toStringAsFixed(0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$emoji  $name',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '$currency ${val.toStringAsFixed(0)} ($p%)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent(val),
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (transit > (total * 0.65) || (transit + stay) > (total * 0.85))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFB74D)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Budget Notice: Flight and transit expenses for this destination consume a large portion of your allocated budget. A higher budget per person is recommended for a more comfortable stay.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFBF360C),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 20, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'BUDGET ALLOCATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total: $currency ${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          categoryBar('Stay / Accommodation', '🏨', stay, const Color(0xFF2563EB)),
          categoryBar('Flights & Transit', '✈️', transit, const Color(0xFF0D9488)),
          categoryBar('Food & Dining', '🍔', food, const Color(0xFFD97706)),
          categoryBar('Activities & Experiences', '🎟️', activities, const Color(0xFF7C3AED)),
        ],
      ),
    ),
    ],
    );
  }

  Widget _dayCard(int dayIndex, OdysseyDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'DAY ${day.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  day.theme,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...day.activities.asMap().entries.map(
                (a) => _activityRow(dayIndex, a.key, a.value),
              ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final total = odyssey.totalActivities;
    final done = odyssey.visitedActivities;
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                odyssey.isComplete
                    ? 'Trip complete 🎉'
                    : 'Tick off each place as you go',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: odyssey.isComplete
                      ? AppColors.neonGreen
                      : Colors.black54,
                ),
              ),
              const Spacer(),
              Text(
                '$done / $total',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: Colors.black12,
              color: odyssey.isComplete
                  ? AppColors.neonGreen
                  : AppColors.actionTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(int dayIndex, int activityIndex, OdysseyActivity act) {
    final bool isCompleted = odyssey.status == 'completed';
    final bool editable = onSwapActivity != null && !isCompleted;
    final bool checkable = onToggleVisited != null;
    final bool isSwapping = swappingKey == '$dayIndex:$activityIndex';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (checkable) ...[
            GestureDetector(
              onTap: isCompleted ? null : () => onToggleVisited!(dayIndex, activityIndex),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(
                  act.visited
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color:
                      act.visited ? AppColors.neonGreen : Colors.black26,
                ),
              ),
            ),
          ],
          SizedBox(
            width: 56,
            child: Text(
              act.time,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: act.visited
                    ? Colors.black26
                    : AppColors.actionTeal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name, tip, and cost stacked vertically inside Expanded
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name row with cost on the right
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        act.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: act.visited ? Colors.black38 : Colors.black,
                          decoration:
                              act.visited ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (act.cost.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: ConvertedCurrencyText(
                          rawText: act.cost,
                          originalCurrency: odyssey.currency,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (act.tip.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    act.tip,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 4),
            if (isSwapping)
              const SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.actionTeal,
                  ),
                ),
              )
            else
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Swap this place',
                  icon: const Icon(
                    Icons.autorenew_rounded,
                    size: 18,
                    color: Colors.black45,
                  ),
                  onPressed: swappingKey != null
                      ? null
                      : () => onSwapActivity!(dayIndex, activityIndex),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _budgetAdvisoryCard(BuildContext context) {
    if (odyssey.budgetAdvisory.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF57F17), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BUDGET ADVISORY',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF57F17),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  odyssey.budgetAdvisory,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingSection(BuildContext context) {
    final dest = odyssey.destination.isNotEmpty ? odyssey.destination : 'Anywhere';

    if (odyssey.bookingPartners.isNotEmpty) {
      return Column(
        children: odyssey.bookingPartners.map((bp) {
          final title = bp.name;
          final type = bp.type.toLowerCase();
          
          // Deduce Icon
          IconData icon = Icons.bookmark_rounded;
          if (type == 'hotels') {
            icon = Icons.hotel_rounded;
          } else if (type == 'tours') {
            icon = Icons.local_activity_rounded;
          } else if (type == 'transit') {
            if (bp.name.toLowerCase().contains('flight') || 
                bp.name.toLowerCase().contains('aviasales') ||
                bp.name.toLowerCase().contains('skyscanner')) {
              icon = Icons.flight_takeoff_rounded;
            } else {
              icon = Icons.directions_car_rounded;
            }
          }

          // Deduce Brand Color
          Color color = const Color(0xFF007A7C); // Default Theme Teal
          final nameLower = bp.name.toLowerCase();
          if (nameLower.contains('agoda')) {
            color = const Color(0xFF8E24AA); // Purple
          } else if (nameLower.contains('ostrovok')) {
            color = const Color(0xFFFF5722); // Orange-Red
          } else if (nameLower.contains('booking')) {
            color = const Color(0xFF003580); // Blue
          } else if (nameLower.contains('getyourguide')) {
            color = const Color(0xFFFF595D); // GYG Red-Orange
          } else if (nameLower.contains('klook')) {
            color = const Color(0xFFFF5B00); // Klook Orange
          } else if (nameLower.contains('viator')) {
            color = const Color(0xFF00A680); // Viator Green
          } else if (nameLower.contains('pickme')) {
            color = const Color(0xFFFBC02D); // Yellow
          } else if (nameLower.contains('grab')) {
            color = const Color(0xFF00B14F); // Grab Green
          } else if (nameLower.contains('yandex')) {
            color = const Color(0xFFFFCC00); // Yandex Yellow
          } else if (nameLower.contains('skyscanner')) {
            color = const Color(0xFF077078); // Skyscanner Teal
          }

          final bool isHotelCategory = type.contains('hotel') || type.contains('stay') || type.contains('accommodation') || nameLower.contains('booking') || nameLower.contains('agoda') || nameLower.contains('expedia') || nameLower.contains('ostrovok');
          final bool isFlightCategory = type.contains('transit') || type.contains('flight') || type.contains('transport') || nameLower.contains('skyscanner') || nameLower.contains('aviasales') || nameLower.contains('kayak');
          final bool isTourCategory = type.contains('tour') || type.contains('activity') || type.contains('experience') || nameLower.contains('viator') || nameLower.contains('getyourguide') || nameLower.contains('klook');

          // Deduce Subtitle
          String subtitle = 'Find services for $dest via ${bp.name}';
          if (isHotelCategory) {
            subtitle = 'Book top-rated stays in $dest via ${bp.name}';
          } else if (isTourCategory) {
            subtitle = 'Explore local experiences in $dest via ${bp.name}';
          } else if (isFlightCategory) {
            subtitle = 'Get rides or check transit in $dest via ${bp.name}';
          }

          // Build a destination-aware URL through the helper instead of
          // using the raw AI URL which often has empty search fields.
          String resolvedUrl = bp.url;
          if (isHotelCategory) {
            resolvedUrl = BookingUrlHelper.buildHotelUrl(
              rawUrl: bp.url,
              providerName: bp.name,
              hotelName: '',
              destination: dest,
              checkInDate: odyssey.startDate ?? '',
              checkOutDate: odyssey.endDate ?? '',
              travelers: odyssey.travelers,
            );
          } else if (isFlightCategory) {
            resolvedUrl = BookingUrlHelper.buildFlightUrl(
              rawUrl: bp.url,
              providerName: bp.name,
              strategyTitle: '',
              destination: dest,
              departureCity: odyssey.departureCity,
              startDate: odyssey.startDate ?? '',
              endDate: odyssey.endDate ?? '',
              travelers: odyssey.travelers,
            );
          } else if (isTourCategory) {
            resolvedUrl = BookingUrlHelper.buildToursUrl(
              rawUrl: bp.url,
              providerName: bp.name,
              destination: dest,
            );
          } else {
            // Additional fallback by provider name
            if (nameLower.contains('viator') || nameLower.contains('getyourguide') || nameLower.contains('klook')) {
              resolvedUrl = BookingUrlHelper.buildToursUrl(rawUrl: bp.url, providerName: bp.name, destination: dest);
            } else if (nameLower.contains('skyscanner') || nameLower.contains('aviasales') || nameLower.contains('kayak')) {
              resolvedUrl = BookingUrlHelper.buildFlightUrl(rawUrl: bp.url, providerName: bp.name, strategyTitle: '', destination: dest, departureCity: odyssey.departureCity, startDate: odyssey.startDate ?? '', endDate: odyssey.endDate ?? '', travelers: odyssey.travelers);
            } else if (nameLower.contains('booking') || nameLower.contains('agoda')) {
              resolvedUrl = BookingUrlHelper.buildHotelUrl(rawUrl: bp.url, providerName: bp.name, hotelName: '', destination: dest, checkInDate: odyssey.startDate ?? '', checkOutDate: odyssey.endDate ?? '', travelers: odyssey.travelers);
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _bookingCard(
              context,
              title: title,
              subtitle: subtitle,
              icon: icon,
              color: color,
              url: resolvedUrl,
              isAiGenerated: true,
            ),
          );
        }).toList(),
      );
    }

    final correctedSkyscannerUrl = 'https://www.skyscanner.com/flights?q=${Uri.encodeComponent(dest)}';

    return Column(
      children: [
        _bookingCard(
          context,
          title: 'Book Hotels & Stays',
          subtitle: 'Find top-rated properties in $dest',
          icon: Icons.hotel_rounded,
          color: const Color(0xFF003580), // Booking.com Brand Blue
          url: 'https://www.booking.com/searchresults.html?ss=${Uri.encodeComponent(dest)}',
        ),
        const SizedBox(height: 12),
        _bookingCard(
          context,
          title: 'Find Tours & Activities',
          subtitle: 'Uncover curated local experiences',
          icon: Icons.local_activity_rounded,
          color: const Color(0xFFFF595D), // GetYourGuide Orange/Red
          url: 'https://www.getyourguide.com/s?q=${Uri.encodeComponent(dest)}',
        ),
        const SizedBox(height: 12),
        _bookingCard(
          context,
          title: 'Flights & Car Rental',
          subtitle: 'Compare transit options to $dest',
          icon: Icons.flight_takeoff_rounded,
          color: const Color(0xFF077078), // Skyscanner Teal
          url: correctedSkyscannerUrl,
        ),
      ],
    );
  }

  Widget _bookingCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String url,
    bool isAiGenerated = false,
  }) {
    final isSwapping = isAiGenerated && swappingPartnerName == title;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final uri = Uri.parse(url);
            try {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open booking link: $url')),
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error launching link: $e')),
                );
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSwapping)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandGreen,
                    ),
                  )
                else if (isAiGenerated && onSwapPartner != null)
                  IconButton(
                    icon: const Icon(Icons.autorenew_rounded, size: 18, color: Colors.black45),
                    onPressed: () => onSwapPartner!(title),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.black26,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
