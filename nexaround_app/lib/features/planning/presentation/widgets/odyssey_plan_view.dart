import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/flight_strategies_section.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/hotel_strategies_section.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/trip_info_section.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';


/// Renders a generated/saved [Odyssey] as a scrollable blueprint. Shared by the
/// planner's result step and the saved-odyssey detail page.
/// One row of the flattened itinerary.
///
/// Dragging a place into a different day means every place and every day
/// heading has to live in one list: Flutter's reorderable lists move items
/// within a single list only, so keeping a list per day would have confined a
/// drag to the day it started in.
sealed class _PlanRow {
  const _PlanRow();
}

class _DayHeadingRow extends _PlanRow {
  final int dayIndex;
  const _DayHeadingRow(this.dayIndex);
}

class _ActivityPlanRow extends _PlanRow {
  final int dayIndex;
  final int activityIndex;
  final bool isLastOfDay;
  const _ActivityPlanRow(this.dayIndex, this.activityIndex, this.isLastOfDay);
}

class OdysseyPlanView extends StatefulWidget {
  final Odyssey odyssey;
  final EdgeInsetsGeometry padding;

  /// Called when a place is dragged to a new position, possibly into another
  /// day. Indices are the source and destination positions within their days.
  final void Function(int fromDay, int fromIndex, int toDay, int toIndex)?
      onReorderActivity;
  final void Function(int dayIndex, int activityIndex)? onToggleVisited;

  /// When provided, each dynamic booking partner shows an edit/swap button
  /// to ask the AI for a replacement.
  final void Function(String partnerName)? onSwapPartner;

  /// Name of the partner currently being swapped, so it can show a spinner.
  final String? swappingPartnerName;

  /// Called when the user enters/updates the actual cost for a completed activity.
  final void Function(int dayIndex, int activityIndex, String actualCost)? onActualCostChanged;

  const OdysseyPlanView({
    super.key,
    required this.odyssey,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.onReorderActivity,
    this.onToggleVisited,
    this.onSwapPartner,
    this.swappingPartnerName,
    this.onActualCostChanged,
  });

  @override
  State<OdysseyPlanView> createState() => _OdysseyPlanViewState();
}

class _OdysseyPlanViewState extends State<OdysseyPlanView> {
  // 'minimum' | 'recommended' | 'comfortable' — only meaningful when
  // odyssey.budgetScenarios is non-empty (legacy Odysseys have none).
  String _selectedScenario = 'recommended';

  @override
  Widget build(BuildContext context) {
    final bool hasFlights = widget.odyssey.flightStrategies.isNotEmpty ||
        widget.odyssey.flightGeneralTips.isNotEmpty ||
        widget.odyssey.flightBestMonths.isNotEmpty;
    final bool hasHotels = widget.odyssey.hotelStrategies.isNotEmpty ||
        widget.odyssey.hotelGeneralTips.isNotEmpty ||
        widget.odyssey.hotelBestAreas.isNotEmpty;
    final bool hasTripInfo = !widget.odyssey.practicalInfo.isEmpty ||
        widget.odyssey.bookingPlan.isNotEmpty ||
        widget.odyssey.verifiedSources.isNotEmpty;

    Widget buildTabItem({required IconData icon, required String label}) {
      return Tab(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
    }

    final List<Widget> tabs = [
      buildTabItem(icon: Icons.dashboard_outlined, label: 'Overview'),
      buildTabItem(icon: Icons.map_outlined, label: 'Itinerary'),
      if (hasTripInfo)
        buildTabItem(icon: Icons.info_outline_rounded, label: 'Info'),
      if (hasFlights)
        buildTabItem(icon: Icons.flight_outlined, label: 'Flights'),
      if (hasHotels)
        buildTabItem(icon: Icons.hotel_outlined, label: 'Stays'),
    ];

    final List<Widget> tabViews = [
      _buildOverviewTab(context),
      _buildItineraryTab(context),
      if (hasTripInfo) _buildInfoTab(context),
      if (hasFlights) _buildFlightsTab(context),
      if (hasHotels) _buildStaysTab(context),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.black12, width: 1),
              ),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              indicatorColor: Colors.black,
              indicatorWeight: 2.5,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              tabs: tabs,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient _getThemedGradient(String destination) {
    final hash = destination.hashCode;
    final gradients = [
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F766E), Color(0xFF312E81)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF581C87), Color(0xFF0F172A)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFB45309), Color(0xFF451A03)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF065F46), Color(0xFF1E3A8A)],
      ),
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF881337), Color(0xFF1C1917)],
      ),
    ];
    return gradients[hash.abs() % gradients.length];
  }

  Widget _buildCinematicHeroCard(BuildContext context) {
    final hasImage = widget.odyssey.coverUrl != null && widget.odyssey.coverUrl!.isNotEmpty;
    final gradient = _getThemedGradient(widget.odyssey.destination);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      constraints: const BoxConstraints(minHeight: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // ── 1. Real Sharp Hero Cover Photo ───────────────────────────
            Positioned.fill(
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: widget.odyssey.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF0F172A),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        decoration: BoxDecoration(gradient: gradient),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(gradient: gradient),
                    ),
            ),

            // ── 2. Dark Vignette Gradient Overlay (Crisp Text Readability) ─
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.50),
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
            ),

            // ── 3. Content Layer (Auto-expanding, zero text clipping) ────
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Badges Row (Destination & Duration Chips)
                  Row(
                    children: [
                      if (widget.odyssey.destination.isNotEmpty)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.50),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.30),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.place_rounded, color: Color(0xFFFFD600), size: 13),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    widget.odyssey.destination,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '${widget.odyssey.actualDays} ${widget.odyssey.actualDays == 1 ? 'Day' : 'Days'}'
                          '${widget.odyssey.nights > 0 ? ' • ${widget.odyssey.nights} ${widget.odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Mood Tag
                  if (widget.odyssey.mood.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          widget.odyssey.mood.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),

                  // Title (Full text visible)
                  Text(
                    widget.odyssey.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: -0.3,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),

                  // AI Intro / Summary (Fully visible, wraps across lines without ellipsis)
                  if (widget.odyssey.summary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xFFFFD600),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.odyssey.summary,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCinematicHeroCard(context),
          if (widget.odyssey.verdict != null) _verdictBanner(widget.odyssey.verdict!),
          if (widget.odyssey.formattedDateRange.isNotEmpty) ...[
            _infoCard(
              'Trip Dates',
              widget.odyssey.formattedDateRange,
              Icons.calendar_month_rounded,
            ),
            _infoCard(
              'Duration',
              '${widget.odyssey.actualDays} ${widget.odyssey.actualDays == 1 ? 'Day' : 'Days'}'
                  '${widget.odyssey.nights > 0 ? ' / ${widget.odyssey.nights} ${widget.odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''}',
              Icons.wb_sunny_rounded,
            ),
          ] else
            _infoCard(
              'Duration',
              '${widget.odyssey.actualDays} ${widget.odyssey.actualDays == 1 ? 'Day' : 'Days'}'
                  '${widget.odyssey.nights > 0 ? ' / ${widget.odyssey.nights} ${widget.odyssey.nights == 1 ? 'Night' : 'Nights'}' : ''}',
              Icons.wb_sunny_rounded,
            ),
          if (widget.odyssey.travelers > 0)
            _infoCard(
              'Travelers / Group Size',
              '${widget.odyssey.travelers} ${widget.odyssey.travelers == 1 ? 'Traveler (1 Pax)' : 'Travelers (${widget.odyssey.travelers} Pax)'}',
              Icons.people_rounded,
            ),
          if (widget.odyssey.destination.isNotEmpty)
            _infoCard('Destination', widget.odyssey.destination, Icons.place_rounded),
          if (widget.odyssey.visa.isNotEmpty)
            _infoCard('Visa / Entry', widget.odyssey.visa, Icons.description_rounded),
          if (widget.odyssey.budgetSplit.isNotEmpty)
            _infoCard('Budget Summary', widget.odyssey.budgetSplit, Icons.pie_chart_rounded),
          if (widget.odyssey.budget > 0)
            _budgetBreakdownCard(context),
        ],
      ),
    );
  }

  Widget _buildInfoTab(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      child: TripInfoSection(odyssey: widget.odyssey),
    );
  }

  Widget _buildFlightsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlightStrategiesSection(odyssey: widget.odyssey),
        ],
      ),
    );
  }

  List<OdysseyBookingPartner> get _dynamicPartners {
    final List<OdysseyBookingPartner> partners = List.from(widget.odyssey.bookingPartners);
    final existingNames = partners.map((p) => p.name.toLowerCase()).toSet();
    final dest = widget.odyssey.destination.isNotEmpty ? widget.odyssey.destination : 'Anywhere';

    // Extract dynamic transit app partners mentioned in activities/tips if not already included
    for (final day in widget.odyssey.dayPlans) {
      for (final act in day.activities) {
        final text = '${act.name} ${act.tip}'.toLowerCase();

        if (text.contains('uber') && !existingNames.any((n) => n.contains('uber'))) {
          existingNames.add('uber');
          partners.add(OdysseyBookingPartner(
            name: 'Uber',
            type: 'transit',
            url: 'https://m.uber.com/ul/?action=setPickup&dropoff[formatted_address]=${Uri.encodeComponent(dest)}',
          ));
        }
        if (text.contains('pickme') && !existingNames.any((n) => n.contains('pickme'))) {
          existingNames.add('pickme');
          partners.add(const OdysseyBookingPartner(
            name: 'PickMe',
            type: 'transit',
            url: 'https://pickme.lk',
          ));
        }
        if (text.contains('grab') && !existingNames.any((n) => n.contains('grab'))) {
          existingNames.add('grab');
          partners.add(const OdysseyBookingPartner(
            name: 'Grab',
            type: 'transit',
            url: 'https://www.grab.com',
          ));
        }
      }
    }

    return partners;
  }

  Widget _buildStaysTab(BuildContext context) {
    final partners = _dynamicPartners;
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HotelStrategiesSection(odyssey: widget.odyssey),
          if (partners.isNotEmpty) ...[
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
            _buildBookingSection(context, partners),
          ],
        ],
      ),
    );
  }

  Widget _buildItineraryTab(BuildContext context) {
    final rows = _planRows();
    final pad = widget.padding.resolve(Directionality.of(context));

    // A CustomScrollView rather than a SingleChildScrollView so the places can
    // sit in a SliverReorderableList. A shrink-wrapped reorderable list inside a
    // scroll view cannot auto-scroll while dragging, which would make moving a
    // place from day one to day five impossible on anything but a short plan.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.odyssey.dayPlans.isNotEmpty) ...[
                  const Text(
                    'DAY-BY-DAY ITINERARY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  if (widget.onToggleVisited != null) _buildProgress(),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad.left),
          sliver: SliverReorderableList(
            itemCount: rows.length,
            onReorder: _onReorder,
            proxyDecorator: (Widget child, int index, Animation<double> animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (BuildContext context, Widget? child) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    child: child,
                  );
                },
                child: child,
              );
            },
            // Places carry their own handle; a day heading is not draggable, so
            // the default handles are off and added per row instead.
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row is _DayHeadingRow) {
                final day = widget.odyssey.dayPlans[row.dayIndex];
                return Column(
                  key: ValueKey('day-heading-${row.dayIndex}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (row.dayIndex > 0) const SizedBox(height: 16),
                    _dayHeadingRow(row.dayIndex, day),
                    if (day.activities.isEmpty) _emptyDayFooter(),
                  ],
                );
              }
              final place = row as _ActivityPlanRow;
              final act = widget.odyssey.dayPlans[place.dayIndex]
                  .activities[place.activityIndex];
              return _activityRow(
                place.dayIndex,
                place.activityIndex,
                act,
                isLastOfDay: place.isLastOfDay,
                rowIndex: index,
                key: ValueKey(
                  'act-${place.dayIndex}-${place.activityIndex}-${act.name}',
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.odyssey.logistics.isNotEmpty) ...[
                  const SizedBox(height: 16),
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
                      widget.odyssey.logistics,
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
          ),
        ),
      ],
    );
  }

  /// Upfront feasibility read, right under the hero card. Reuses the same
  /// amber warning-card language as the pre-generation budget-shortfall
  /// notice (`odyssey_planner_page.dart`) and the transit-heavy notice below
  /// in this file, so a traveller sees one consistent "pay attention" visual
  /// language rather than three different ones.
  Widget _verdictBanner(OdysseyVerdict verdict) {
    final bool warn = !verdict.feasible || verdict.budgetTightness == 'tight';
    final Color bg = warn ? const Color(0xFFFFF4E5) : AppColors.brandGreenLight;
    final Color border =
        warn ? const Color(0xFFFFB74D) : AppColors.brandGreen.withValues(alpha: 0.35);
    final Color iconColor = warn ? const Color(0xFFE65100) : AppColors.brandGreen;
    final Color textColor = warn ? const Color(0xFF8D4E00) : AppColors.brandGreenDark;
    final IconData icon = !verdict.feasible
        ? Icons.error_outline_rounded
        : (warn ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded);

    final lines = <String>[
      if (verdict.recommendation.isNotEmpty) verdict.recommendation,
      if (verdict.biggestRisk.isNotEmpty) 'Watch out: ${verdict.biggestRisk}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        height: 1.4,
                        color: textColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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

  Widget _scenarioToggle() {
    const options = [
      ('minimum', 'Minimum'),
      ('recommended', 'Recommended'),
      ('comfortable', 'Comfortable'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: options.map((opt) {
          final selected = _selectedScenario == opt.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedScenario = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  opt.$2,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.black : Colors.black45,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _budgetBreakdownCard(BuildContext context) {
    final scenarios = widget.odyssey.budgetScenarios;
    final bd = scenarios[_selectedScenario] ?? widget.odyssey.budgetBreakdown;
    final currency = widget.odyssey.currency;
    final total = (bd['total'] ?? 0) > 0 ? (bd['total']!) : widget.odyssey.budget;

    // Default category estimates if breakdown dictionary is empty
    final stay = bd['stay'] ?? (total * 0.35);
    final transit = bd['transit'] ?? (total * 0.30);
    final food = bd['food'] ?? (total * 0.20);
    final activities = bd['activities'] ?? (total * 0.15);

    double percent(double val) => total > 0 ? (val / total).clamp(0.0, 1.0) : 0.25;

    String formatPercentage(double val) {
      if (val <= 0 || total <= 0) return '0%';
      final pct = (val / total) * 100;
      if (pct >= 0.95) {
        return '${pct.round()}%';
      } else if (pct >= 0.1) {
        return '${pct.toStringAsFixed(1)}%';
      } else {
        final formatted = pct.toStringAsFixed(2);
        return formatted == '0.00' ? '< 0.01%' : '$formatted%';
      }
    }

    Widget categoryBar(String name, String emoji, double val, Color color) {
      final pStr = formatPercentage(val);
      final progVal = (val > 0 && percent(val) < 0.01) ? 0.01 : percent(val);
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
                  '$currency ${formatAmount(val)} ($pStr)',
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
                value: progVal,
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
                      'Total: $currency ${formatAmount(total)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  ),
                ],
              ),
              if (scenarios.isNotEmpty) ...[
                const SizedBox(height: 16),
                _scenarioToggle(),
              ],
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

  /// The itinerary flattened into one list: a heading per day, then its places.
  ///
  /// Rebuilt on every use rather than cached — it is a few dozen small objects
  /// and a stale copy would send a drag to the wrong day.
  List<_PlanRow> _planRows() {
    final rows = <_PlanRow>[];
    for (var d = 0; d < widget.odyssey.dayPlans.length; d++) {
      rows.add(_DayHeadingRow(d));
      final acts = widget.odyssey.dayPlans[d].activities;
      for (var a = 0; a < acts.length; a++) {
        rows.add(_ActivityPlanRow(d, a, a == acts.length - 1));
      }
    }
    return rows;
  }

  /// Position of a place in the flattened list, which is the index
  /// ReorderableDragStartListener needs.
  int _rowIndexOf(int dayIndex, int activityIndex) {
    var index = 0;
    for (var d = 0; d < dayIndex; d++) {
      index += 1 + widget.odyssey.dayPlans[d].activities.length;
    }
    return index + 1 + activityIndex;
  }

  /// Translate a move in the flattened list back into "this place, from this
  /// day and position, to that day and position".
  ///
  /// Done by simulating the move on the flattened list and then reading the
  /// result, rather than by arithmetic on the indices: dropping onto a day
  /// heading, above the first heading, or past the last place are all ordinary
  /// outcomes of the simulation, where each would be a separate special case.
  void _onReorder(int oldIndex, int newIndex) {
    final reorder = widget.onReorderActivity;
    if (reorder == null) return;

    final rows = _planRows();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    final moved = rows[oldIndex];
    if (moved is! _ActivityPlanRow) return;

    // Flutter reports the destination as if the dragged row were still present.
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, rows.length - 1);

    rows.removeAt(oldIndex);
    rows.insert(newIndex, moved);

    var currentDay = -1;
    var positionInDay = 0;
    for (final row in rows) {
      if (row is _DayHeadingRow) {
        currentDay = row.dayIndex;
        positionInDay = 0;
        continue;
      }
      if (identical(row, moved)) break;
      positionInDay++;
    }

    // Dropped above the first heading: treat it as the start of day one.
    if (currentDay < 0) {
      currentDay = 0;
      positionInDay = 0;
    }

    if (currentDay == moved.dayIndex && positionInDay == moved.activityIndex) {
      return; // nothing actually moved
    }
    reorder(moved.dayIndex, moved.activityIndex, currentDay, positionInDay);
  }

  /// The "DAY n — theme" strip that opens each day's block.
  Widget _dayHeadingRow(int dayIndex, OdysseyDay day) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black12),
          left: BorderSide(color: Colors.black12),
          right: BorderSide(color: Colors.black12),
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Row(
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  /// An empty day still needs a floor, or its heading has no bottom edge.
  Widget _emptyDayFooter() => Container(
        height: 18,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: Colors.black12),
            right: BorderSide(color: Colors.black12),
            bottom: BorderSide(color: Colors.black12),
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      );

  Widget _buildProgress() {
    final total = widget.odyssey.totalActivities;
    final done = widget.odyssey.visitedActivities;
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.odyssey.isComplete
                    ? 'Trip complete 🎉'
                    : 'Tick off each place as you go',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: widget.odyssey.isComplete
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
              color: widget.odyssey.isComplete
                  ? AppColors.neonGreen
                  : AppColors.actionTeal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(
    int dayIndex,
    int activityIndex,
    OdysseyActivity act, {
    bool isLastOfDay = false,
    int? rowIndex,
    Key? key,
  }) {
    final bool isCompleted = widget.odyssey.status == 'completed';
    final bool checkable = widget.onToggleVisited != null;
    final bool reorderable = widget.onReorderActivity != null && !isCompleted;

    return Material(
      key: key,
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            left: const BorderSide(color: Colors.black12),
            right: const BorderSide(color: Colors.black12),
            bottom: isLastOfDay
                ? const BorderSide(color: Colors.black12)
                : BorderSide(color: Colors.black.withValues(alpha: 0.04)),
          ),
          borderRadius: isLastOfDay
              ? const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (checkable)
                    GestureDetector(
                      onTap: isCompleted
                          ? null
                          : () => widget.onToggleVisited!(dayIndex, activityIndex),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          act.visited
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 22,
                          color: act.visited ? AppColors.neonGreen : Colors.black26,
                        ),
                      ),
                    ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _navigateToSmartMap(context, act.name),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
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
                    ),
                  ),
                  if (reorderable)
                    ReorderableDragStartListener(
                      index: rowIndex ?? _rowIndexOf(dayIndex, activityIndex),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 2, right: 4),
                        child: Icon(Icons.drag_indicator_rounded,
                            size: 20, color: Colors.black26),
                      ),
                    ),
                ],
              ),
            ),
            // Details are always visible
            Padding(
              padding: EdgeInsets.fromLTRB(
                checkable ? 48 : 16,
                0,
                16,
                14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final hasCost = act.cost.isNotEmpty;
                      final actionBtn = _buildActionButton(act, dayIndex, activityIndex);
                      final hasActionBtn = actionBtn is! SizedBox;

                      if (!hasCost && !hasActionBtn) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (hasCost) _buildPriceWithSource(context, act),
                            if (hasActionBtn) actionBtn,
                          ],
                        ),
                      );
                    },
                  ),
                  if (act.tip.isNotEmpty) ...[
                    Text(
                      act.tip,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (act.visited && widget.onActualCostChanged != null) ...[
                    const SizedBox(height: 8),
                    _buildActualCostInput(dayIndex, activityIndex, act),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the type-specific action button for an activity.
  Widget _buildActionButton(OdysseyActivity act, int dayIndex, int activityIndex) {
    Widget btn;
    switch (act.type) {
      case ActivityType.transport:
        btn = _buildTransportButton(act);
        break;
      case ActivityType.attraction:
        btn = _buildAttractionButton(act);
        break;
      case ActivityType.accommodation:
        btn = _buildAccommodationButton(act);
        break;
      case ActivityType.dining:
        btn = _buildDiningButton(act, dayIndex, activityIndex);
        break;
      case ActivityType.exploration:
        btn = _buildExplorationButton(act);
        break;
      case ActivityType.other:
        btn = const SizedBox.shrink();
        break;
    }

    if (btn is SizedBox) return btn;

    final lowerCost = act.cost.trim().toLowerCase();
    final bool isFree = lowerCost.isEmpty ||
        lowerCost == 'free' ||
        lowerCost == '0' ||
        lowerCost == '\$0' ||
        lowerCost.endsWith(' 0') ||
        lowerCost.endsWith(' 0.00');

    // If activity is Free and we have a platform action button (Headout, GetYourGuide, Uber, Google Hotels, etc.)
    // show [Paid] badge chip beside the platform logo (except for LIST restaurant sheet)
    if (isFree && act.type != ActivityType.dining) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Text(
              'Paid',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
          const SizedBox(width: 5),
          btn,
        ],
      );
    }

    return btn;
  }

  /// Uber button for transport activities (shows clean logo only, no box/container).
  Widget _buildTransportButton(OdysseyActivity act) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        // Strip directional prefix and append destination for accurate geocoding
        final placeName = act.name.replaceAll(RegExp(r'^(Travel|Drive|Taxi|Transfer|Ride)\s+to\s+', caseSensitive: false), '').trim();
        final dest = widget.odyssey.destination.isNotEmpty ? widget.odyssey.destination : '';
        final fullAddress = dest.isNotEmpty ? '$placeName, $dest' : placeName;
        final destination = Uri.encodeComponent(fullAddress);
        final uberUri = Uri.parse('https://m.uber.com/ul/?action=setPickup&dropoff[formatted_address]=$destination');
        if (await canLaunchUrl(uberUri)) {
          await launchUrl(uberUri, mode: LaunchMode.externalApplication);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.asset(
          'assets/images/uber_logo.png',
          height: 20,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Headout button for ticketed attraction activities (shows clean logo only, no box/container).
  Widget _buildAttractionButton(OdysseyActivity act) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final dest = widget.odyssey.destination.isNotEmpty ? ' ${widget.odyssey.destination}' : '';
        final query = Uri.encodeComponent('${act.name} tickets$dest');
        final url = Uri.parse('https://www.headout.com/search/?q=$query');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Image.asset(
        'assets/images/headout.png',
        height: 20,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Google Hotels button for accommodation activities (opens direct entity link).
  Widget _buildAccommodationButton(OdysseyActivity act) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (act.bookingUrl.isNotEmpty) {
          final uri = Uri.parse(act.bookingUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        }
        final hotelName = act.name.replaceAll(RegExp(r'^(Check into|Check in|Hotel Check-out & Transfer to|Hotel Check-out|Rest & Freshen Up at)\s+', caseSensitive: false), '').trim();
        final dest = widget.odyssey.destination.isNotEmpty ? widget.odyssey.destination : '';
        final query = hotelName.isNotEmpty ? (dest.isNotEmpty ? '$hotelName, $dest' : hotelName) : dest;
        final url = Uri.parse('https://www.google.com/travel/search?q=${Uri.encodeComponent(query)}');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hotel_rounded, size: 12, color: Color(0xFF9333EA)),
            SizedBox(width: 4),
            Text(
              'Google Hotels',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF9333EA),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// LIST chip button for dining activities. Tapping opens a restaurant sheet.
  Widget _buildDiningButton(OdysseyActivity act, int dayIndex, int activityIndex) {
    return Builder(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showRestaurantSheet(context, act),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black26),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.restaurant_menu_rounded, size: 10, color: Colors.black54),
              SizedBox(width: 3),
              Text(
                'LIST',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// GetYourGuide logo button for exploration activities (shows clean logo only).
  Widget _buildExplorationButton(OdysseyActivity act) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final placeName = act.name.replaceAll(RegExp(r'^(Explore|Wander|Walk through|Stroll)\s+', caseSensitive: false), '').trim();
        final dest = widget.odyssey.destination.isNotEmpty ? ' ${widget.odyssey.destination}' : '';
        final query = Uri.encodeComponent('$placeName guided tour$dest');
        final url = Uri.parse('https://www.getyourguide.com/s/?q=$query');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Image.asset(
        'assets/images/getyourguide.png',
        height: 22,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Actual cost input field shown when an activity is marked visited.
  Widget _buildActualCostInput(int dayIndex, int activityIndex, OdysseyActivity act) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Text(
            'Actual Cost:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActualCostInputField(
              initialValue: act.actualCost,
              currency: widget.odyssey.currency,
              onSaved: (val) => widget.onActualCostChanged?.call(dayIndex, activityIndex, val),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves rich, context-aware source tag, detailed explanation, and matching category icon.
  (String sourceTag, String sourceDetail, IconData icon, bool isFree, Color iconBgColor, Color iconColor, String displayCost)
      _resolvePriceContext(OdysseyActivity act) {
    String rawCost = act.cost.trim();
    final lowerCost = rawCost.toLowerCase();
    final bool isFree = lowerCost == 'free' ||
        rawCost == '0' ||
        rawCost == '\$0' ||
        lowerCost.endsWith(' 0') ||
        lowerCost.endsWith(' 0.00');

    final planCurr = widget.odyssey.currency.isNotEmpty ? widget.odyssey.currency : 'USD';

    // Format displayCost: e.g. "1500" -> "~ LKR 1,500"
    String displayCost = formatPriceString(rawCost, targetCurrency: planCurr);
    if (!isFree && displayCost.isNotEmpty) {
      final hasCurrency = RegExp(r'[A-Za-z]').hasMatch(displayCost);
      if (!hasCurrency && planCurr.isNotEmpty) {
        displayCost = '$planCurr $displayCost';
      }
      if (!displayCost.startsWith('~') &&
          !displayCost.toLowerCase().contains('included') &&
          !displayCost.toLowerCase().contains('approx')) {
        displayCost = '~ $displayCost';
      }
      displayCost = formatPriceString(displayCost, targetCurrency: planCurr);
    }

    final lowerName = act.name.toLowerCase();
    final lowerTip = act.tip.toLowerCase();

    // 1. Explicit AI-provided source & basis from Gemini
    if (act.priceSource.isNotEmpty) {
      final detail = act.priceBasis.isNotEmpty
          ? act.priceBasis
          : 'Estimated price baseline derived from travel intelligence and regional pricing data.';
      IconData icon = Icons.price_change_outlined;
      Color iconBg = const Color(0xFFEFF6FF);
      Color iconColor = const Color(0xFF2563EB);

      if (act.type == ActivityType.accommodation || lowerName.contains('hotel') || lowerName.contains('check-in')) {
        icon = Icons.hotel_outlined;
        iconBg = const Color(0xFFF3E8FF);
        iconColor = const Color(0xFF9333EA);

        if ((displayCost.isEmpty || displayCost.toLowerCase() == 'included in stay') &&
            act.priceBasis.isNotEmpty &&
            act.priceBasis.contains('rate:')) {
          final match = RegExp(r'rate:\s*([^(\n]+)').firstMatch(act.priceBasis);
          if (match != null) {
            final rate = match.group(1)?.trim();
            if (rate != null && rate.isNotEmpty) {
              final formattedRate = formatPriceString(rate, targetCurrency: planCurr);
              displayCost = formattedRate.startsWith('~') ? formattedRate : '~ $formattedRate';
            }
          }
        }
      } else if (act.type == ActivityType.transport || lowerName.contains('airport') || lowerName.contains('taxi')) {
        icon = Icons.directions_car_outlined;
        iconBg = const Color(0xFFFEF3C7);
        iconColor = const Color(0xFFD97706);
      } else if (act.type == ActivityType.dining || lowerName.contains('lunch') || lowerName.contains('dinner')) {
        icon = Icons.restaurant_rounded;
        iconBg = const Color(0xFFFFEDD5);
        iconColor = const Color(0xFFEA580C);
      } else if (act.type == ActivityType.attraction) {
        icon = Icons.confirmation_number_outlined;
        iconBg = const Color(0xFFE0F2FE);
        iconColor = const Color(0xFF0284C7);
      } else if (isFree) {
        iconBg = const Color(0xFFDCFCE7);
        iconColor = const Color(0xFF16A34A);
      }

      return (act.priceSource, detail, icon, isFree, iconBg, iconColor, displayCost);
    }

    // 2. Accommodation (Hotel check-in / check-out / freshen up)
    if (act.type == ActivityType.accommodation ||
        lowerName.contains('hotel') ||
        lowerName.contains('check-in') ||
        lowerName.contains('check in') ||
        lowerName.contains('check-out') ||
        lowerName.contains('check out') ||
        lowerName.contains('freshen up') ||
        lowerName.contains('resort') ||
        lowerName.contains('hostel') ||
        lowerName.contains('villa') ||
        lowerName.contains('guest house')) {
      String accCost = 'Included in Stay';
      if (act.priceBasis.isNotEmpty && act.priceBasis.contains('rate:')) {
        final match = RegExp(r'rate:\s*([^(\n]+)').firstMatch(act.priceBasis);
        if (match != null) {
          final rate = match.group(1)?.trim();
          if (rate != null && rate.isNotEmpty) {
            final formattedRate = formatPriceString(rate, targetCurrency: planCurr);
            accCost = formattedRate.startsWith('~') ? formattedRate : '~ $formattedRate';
          }
        }
      }
      return (
        'Google Hotels',
        'Hotel accommodation rate based on verified lowest Google Hotels room rate.',
        Icons.hotel_outlined,
        false,
        const Color(0xFFF3E8FF),
        const Color(0xFF9333EA),
        accCost,
      );
    }

    // 3. Transport & Airport Transfers (Airport arrival, PickMe, Uber, Grab, taxi, bus, train)
    if (act.type == ActivityType.transport ||
        lowerName.contains('arrival') ||
        lowerName.contains('airport') ||
        lowerName.contains('flight') ||
        lowerName.contains('transfer') ||
        lowerName.contains('taxi') ||
        lowerName.contains('drive to') ||
        lowerName.contains('travel to') ||
        lowerName.contains('train') ||
        lowerName.contains('bus') ||
        lowerName.contains('ferry') ||
        lowerTip.contains('pickme') ||
        lowerTip.contains('uber') ||
        lowerTip.contains('grab') ||
        lowerTip.contains('taxi') ||
        lowerTip.contains('bus') ||
        lowerTip.contains('train')) {
      String tag = 'Est. Fare';
      if (lowerTip.contains('pickme') || lowerName.contains('pickme')) {
        tag = 'PickMe / Taxi';
      } else if (lowerTip.contains('uber') || lowerName.contains('uber')) {
        tag = 'Uber / Taxi';
      } else if (lowerTip.contains('grab') || lowerName.contains('grab')) {
        tag = 'Grab / Taxi';
      } else if (lowerTip.contains('bus') || lowerName.contains('bus')) {
        tag = 'Bus / Transit';
      } else if (lowerTip.contains('train') || lowerName.contains('train')) {
        tag = 'Train Fare';
      }

      String detail = 'Estimated local transit / ride-hail fare calculated from standard route distance rates.';
      if (lowerName.contains('airport') || lowerName.contains('arrival')) {
        detail = 'Estimated airport transfer fare based on standard local taxi / ride-hail metered distance rates.';
      }
      return (
        tag,
        detail,
        Icons.directions_car_outlined,
        isFree,
        const Color(0xFFFEF3C7),
        const Color(0xFFD97706),
        displayCost,
      );
    }

    // 4. Dining (Breakfast, Lunch, Dinner, Cafe, Restaurant)
    if (act.type == ActivityType.dining ||
        lowerName.startsWith('lunch') ||
        lowerName.startsWith('dinner') ||
        lowerName.startsWith('breakfast') ||
        lowerName.startsWith('brunch') ||
        lowerName.contains('restaurant') ||
        lowerName.contains('dining') ||
        lowerName.contains('food tour') ||
        lowerName.contains('street food') ||
        lowerName.contains('cafe') ||
        lowerName.contains('coffee')) {
      return (
        'Avg. Meal',
        'Average meal cost estimate based on local restaurant menu price tiers in this destination.',
        Icons.restaurant_rounded,
        isFree,
        const Color(0xFFFFEDD5),
        const Color(0xFFEA580C),
        displayCost,
      );
    }

    // 5. Exploration & Public Sights (Walking, beach, markets, viewpoints)
    if (act.type == ActivityType.exploration ||
        lowerName.startsWith('explore') ||
        lowerName.startsWith('wander') ||
        lowerName.startsWith('stroll') ||
        lowerName.contains('walking tour') ||
        lowerName.contains('street market') ||
        lowerName.contains('market') ||
        lowerName.contains('bazaar') ||
        lowerName.contains('beach') ||
        lowerName.contains('promenade') ||
        lowerName.contains('sunset view') ||
        lowerName.contains('viewpoint')) {
      return (
        'Free Access',
        'Public scenic area, open street market, or self-guided walk with zero admission charge.',
        Icons.directions_walk_rounded,
        true,
        const Color(0xFFDCFCE7),
        const Color(0xFF16A34A),
        'Free',
      );
    }

    // 6. Attractions & Heritage (Museums, temples, forts, galleries, national parks)
    if (act.type == ActivityType.attraction ||
        lowerName.contains('museum') ||
        lowerName.contains('temple') ||
        lowerName.contains('fort') ||
        lowerName.contains('palace') ||
        lowerName.contains('cathedral') ||
        lowerName.contains('church') ||
        lowerName.contains('castle') ||
        lowerName.contains('gallery') ||
        lowerName.contains('park') ||
        lowerName.contains('sanctuary') ||
        lowerName.contains('garden')) {
      if (isFree) {
        return (
          'Free Entry',
          'Open heritage grounds, public park, or free admission landmark.',
          Icons.museum_outlined,
          true,
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A),
          'Free',
        );
      } else {
        return (
          'Est. Ticket',
          'Estimated admission ticket fee based on official venue pricing and tour partner guides.',
          Icons.confirmation_number_outlined,
          false,
          const Color(0xFFE0F2FE),
          const Color(0xFF0284C7),
          displayCost,
        );
      }
    }

    // 7. General fallback
    if (isFree) {
      return (
        'Free',
        'Complimentary activity with zero admission fees.',
        Icons.check_circle_outline_rounded,
        true,
        const Color(0xFFDCFCE7),
        const Color(0xFF16A34A),
        'Free',
      );
    }

    return (
      'Est. Rate',
      'Estimated regional cost baseline derived from destination travel data.',
      Icons.price_change_outlined,
      false,
      const Color(0xFFF1F5F9),
      const Color(0xFF475569),
      displayCost,
    );
  }

  /// Builds the price pill with contextual source attribution tag and tap-to-inspect info.
  Widget _buildPriceWithSource(BuildContext context, OdysseyActivity act) {
    final ctx = _resolvePriceContext(act);
    final sourceTag = ctx.$1;
    final sourceDetail = ctx.$2;
    final isFree = ctx.$4;
    final displayCost = ctx.$7;

    final screenWidth = MediaQuery.of(context).size.width;
    final maxPillWidth = screenWidth > 120 ? screenWidth - 120 : 220.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPriceSourceInfo(context, act),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxPillWidth),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isFree ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFree ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              displayCost,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isFree ? const Color(0xFF166534) : Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 9,
              color: isFree ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                sourceTag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isFree ? const Color(0xFF15803D) : const Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.info_outline_rounded,
              size: 10.5,
              color: isFree ? const Color(0xFF15803D) : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns a list of (label, url, icon, color) verification link tuples
  /// based on the activity type and destination.
  List<(String label, String url, IconData icon, Color color)> _getVerifyLinks(
    OdysseyActivity act,
    String sourceTag,
  ) {
    final dest = widget.odyssey.destination.isNotEmpty ? widget.odyssey.destination : '';
    final q = Uri.encodeComponent('${act.name} $dest'.trim());
    final destQ = Uri.encodeComponent(dest);
    final nameQ = Uri.encodeComponent(act.name);
    final lowerName = act.name.toLowerCase();

    // Google Maps is universal for all types
    final gmapsUrl = 'https://www.google.com/maps/search/$q';

    // Accommodation
    if (act.type == ActivityType.accommodation ||
        lowerName.contains('hotel') ||
        lowerName.contains('check-in') ||
        lowerName.contains('check in') ||
        lowerName.contains('resort') ||
        lowerName.contains('hostel') ||
        lowerName.contains('villa') ||
        lowerName.contains('guest house')) {
      return [
        ('Google Maps', gmapsUrl, Icons.map_outlined, const Color(0xFF4285F4)),
        ('Booking.com', 'https://www.booking.com/searchresults.html?ss=$q', Icons.hotel_outlined, const Color(0xFF003580)),
        ('Agoda', 'https://www.agoda.com/search?q=$q', Icons.bed_outlined, const Color(0xFFAB1F2A)),
      ];
    }

    // Transport & Airport
    if (act.type == ActivityType.transport ||
        lowerName.contains('airport') ||
        lowerName.contains('arrival') ||
        lowerName.contains('taxi') ||
        lowerName.contains('transfer') ||
        lowerName.contains('drive to') ||
        lowerName.contains('travel to')) {
      final links = <(String, String, IconData, Color)>[
        ('Google Maps', 'https://www.google.com/maps/dir/$destQ/$nameQ', Icons.map_outlined, const Color(0xFF4285F4)),
      ];
      // Add ride-hail link
      if (act.tip.toLowerCase().contains('uber') || lowerName.contains('uber')) {
        links.add(('Uber', 'https://m.uber.com/looking?pickup=$destQ', Icons.local_taxi_outlined, const Color(0xFF000000)));
      } else if (act.tip.toLowerCase().contains('pickme') || lowerName.contains('pickme')) {
        links.add(('PickMe', 'https://pickme.lk', Icons.local_taxi_outlined, const Color(0xFF00A651)));
      } else if (act.tip.toLowerCase().contains('grab') || lowerName.contains('grab')) {
        links.add(('Grab', 'https://www.grab.com', Icons.local_taxi_outlined, const Color(0xFF00B14F)));
      } else {
        links.add(('Uber', 'https://m.uber.com/looking?pickup=$destQ', Icons.local_taxi_outlined, const Color(0xFF000000)));
      }
      return links;
    }

    // Dining
    if (act.type == ActivityType.dining ||
        lowerName.startsWith('lunch') ||
        lowerName.startsWith('dinner') ||
        lowerName.startsWith('breakfast') ||
        lowerName.contains('restaurant') ||
        lowerName.contains('cafe') ||
        lowerName.contains('food')) {
      return [
        ('Google Maps', gmapsUrl, Icons.map_outlined, const Color(0xFF4285F4)),
        ('TripAdvisor', 'https://www.tripadvisor.com/Search?q=$q', Icons.star_outline_rounded, const Color(0xFF34E0A1)),
      ];
    }

    // Attractions & Heritage
    if (act.type == ActivityType.attraction ||
        lowerName.contains('museum') ||
        lowerName.contains('temple') ||
        lowerName.contains('fort') ||
        lowerName.contains('palace') ||
        lowerName.contains('cathedral') ||
        lowerName.contains('church') ||
        lowerName.contains('castle') ||
        lowerName.contains('gallery') ||
        lowerName.contains('park') ||
        lowerName.contains('sanctuary') ||
        lowerName.contains('garden')) {
      return [
        ('Google Maps', gmapsUrl, Icons.map_outlined, const Color(0xFF4285F4)),
        ('TripAdvisor', 'https://www.tripadvisor.com/Search?q=$q', Icons.star_outline_rounded, const Color(0xFF34E0A1)),
        ('GetYourGuide', 'https://www.getyourguide.com/s/?q=$q', Icons.confirmation_number_outlined, const Color(0xFFFF5533)),
      ];
    }

    // Exploration / generic — just Google Maps + TripAdvisor
    return [
      ('Google Maps', gmapsUrl, Icons.map_outlined, const Color(0xFF4285F4)),
      ('TripAdvisor', 'https://www.tripadvisor.com/Search?q=$q', Icons.star_outline_rounded, const Color(0xFF34E0A1)),
    ];
  }

  /// Bottom sheet detailing the source basis for an activity's estimated price
  /// with clickable verification links to real booking & pricing platforms.
  void _showPriceSourceInfo(BuildContext context, OdysseyActivity act) {
    final ctx = _resolvePriceContext(act);
    final sourceTag = ctx.$1;
    final icon = ctx.$3;
    final isFree = ctx.$4;
    final iconBg = ctx.$5;
    final iconColor = ctx.$6;
    final displayCost = ctx.$7;

    final verifyLinks = _getVerifyLinks(act, sourceTag);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctxModal) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ──
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // ── Header: icon + title + activity name ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 22, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Price & Rate Details',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            act.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ── Scrollable Body ──
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Rate + Source Tag card ──
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Estimated Rate',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isFree
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      displayCost,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: isFree
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFF0369A1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.5),
                                    child: Icon(icon, size: 15, color: iconColor),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Source: $sourceTag',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // ── Verify on: clickable platform links ──
                        const Text(
                          '🔍  Verify price on',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...verifyLinks.map((link) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () async {
                                  final uri = Uri.parse(link.$2);
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: const Color(0xFFE2E8F0), width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: link.$4.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(link.$3, size: 18, color: link.$4),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          link.$1,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.open_in_new_rounded,
                                        size: 16,
                                        color: link.$4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                        const SizedBox(height: 6),
                        // ── Disclaimer banner ──
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFFD97706),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Prices may vary due to seasonal demand, exchange rates & vendor updates. Verify on the platforms above for live rates.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Pinned Close button (Always completely visible) ──
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctxModal).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// Bottom sheet showing restaurant options for a dining activity.
  void _showRestaurantSheet(BuildContext context, OdysseyActivity act) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RestaurantListBottomSheet(
        activity: act,
        destination: widget.odyssey.destination,
        onSelectRestaurant: (name) => _navigateToSmartMap(context, name),
      ),
    );
  }

  /// Geocodes a place name and navigates to the Smart Tourism Map.
  void _navigateToSmartMap(BuildContext context, String placeName) async {
    final dest = widget.odyssey.destination;
    final searchQuery = dest.isNotEmpty ? '$placeName, $dest' : placeName;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Locating $placeName on Smart Map...'),
        duration: const Duration(seconds: 2),
      ),
    );

    // Close any open bottom sheets first
    Navigator.of(context, rootNavigator: true).maybePop();

    try {
      final results = await GooglePlacesService.searchPlaces(
        query: searchQuery,
        latitude: 6.9271,
        longitude: 79.8612,
      );

      if (!context.mounted) return;

      if (results.isNotEmpty) {
        final place = results.first;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SmartTourismMapPage(
              initialLat: place.latitude,
              initialLng: place.longitude,
              destinationName: place.name,
            ),
          ),
        );
      } else {
        // Fallback: stay in-app on Smart Tourism Map
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SmartTourismMapPage(
              initialLat: 6.9271,
              initialLng: 79.8612,
              destinationName: placeName,
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      // Fallback: stay in-app on Smart Tourism Map
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SmartTourismMapPage(
            initialLat: 6.9271,
            initialLng: 79.8612,
            destinationName: placeName,
          ),
        ),
      );
    }
  }


  /// Returns the asset image path for a known provider, or null if no logo exists yet.
  static String? _getPartnerLogoPath(String providerName) {
    final name = providerName.toLowerCase().trim();
    if (name.contains('booking')) return 'assets/images/booking_logo.jpg';
    if (name.contains('uber')) return 'assets/images/uber_logo.png';
    if (name.contains('headout')) return 'assets/images/headout.png';
    if (name.contains('getyourguide')) return 'assets/images/getyourguide.png';
    if (name.contains('viator')) return 'assets/images/viator.png';
    if (name.contains('skyscanner')) return 'assets/images/skyscanner.png';
    // Future logos — return null until assets are added:
    // if (name.contains('agoda')) return 'assets/images/agoda_logo.png';
    // if (name.contains('klook')) return 'assets/images/klook_logo.png';
    // if (name.contains('grab')) return 'assets/images/grab_logo.png';
    // if (name.contains('expedia')) return 'assets/images/expedia_logo.png';
    // if (name.contains('airbnb')) return 'assets/images/airbnb_logo.png';
    // if (name.contains('kayak')) return 'assets/images/kayak_logo.png';
    // if (name.contains('google')) return 'assets/images/google_travel_logo.png';
    // if (name.contains('ostrovok')) return 'assets/images/ostrovok_logo.png';
    // if (name.contains('pickme')) return 'assets/images/pickme_logo.png';
    // if (name.contains('yandex')) return 'assets/images/yandex_logo.png';
    // if (name.contains('hotels.com')) return 'assets/images/hotelscom_logo.png';
    return null;
  }

  Widget _buildBookingSection(BuildContext context, List<OdysseyBookingPartner> partners) {
    if (partners.isEmpty) {
      return const SizedBox.shrink();
    }

    final dest = widget.odyssey.destination.isNotEmpty ? widget.odyssey.destination : 'Anywhere';

    return Column(
      children: partners.map((bp) {
        final title = bp.name;
        final type = bp.type.toLowerCase();
        final nameLower = bp.name.toLowerCase();
        final String? logoPath = _getPartnerLogoPath(bp.name);
        
        // Deduce Icon (fallback when no logo asset exists)
        IconData icon = Icons.bookmark_rounded;
        if (type == 'hotels') {
          icon = Icons.hotel_rounded;
        } else if (type == 'tours') {
          icon = Icons.local_activity_rounded;
        } else if (type == 'transit') {
          if (nameLower.contains('flight') || 
              nameLower.contains('aviasales') ||
              nameLower.contains('skyscanner')) {
            icon = Icons.flight_takeoff_rounded;
          } else {
            icon = Icons.directions_car_rounded;
          }
        }

        // Deduce Brand Color
        Color color = const Color(0xFF007A7C); // Default Theme Teal
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
        } else if (nameLower.contains('uber')) {
          color = Colors.black; // Uber Black
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
            checkInDate: widget.odyssey.startDate ?? '',
            checkOutDate: widget.odyssey.endDate ?? '',
            travelers: widget.odyssey.travelers,
          );
        } else if (isFlightCategory) {
          resolvedUrl = BookingUrlHelper.buildFlightUrl(
            rawUrl: bp.url,
            providerName: bp.name,
            strategyTitle: '',
            destination: dest,
            departureCity: widget.odyssey.departureCity,
            startDate: widget.odyssey.startDate ?? '',
            endDate: widget.odyssey.endDate ?? '',
            travelers: widget.odyssey.travelers,
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
            resolvedUrl = BookingUrlHelper.buildFlightUrl(rawUrl: bp.url, providerName: bp.name, strategyTitle: '', destination: dest, departureCity: widget.odyssey.departureCity, startDate: widget.odyssey.startDate ?? '', endDate: widget.odyssey.endDate ?? '', travelers: widget.odyssey.travelers);
          } else if (nameLower.contains('booking') || nameLower.contains('agoda')) {
            resolvedUrl = BookingUrlHelper.buildHotelUrl(rawUrl: bp.url, providerName: bp.name, hotelName: '', destination: dest, checkInDate: widget.odyssey.startDate ?? '', checkOutDate: widget.odyssey.endDate ?? '', travelers: widget.odyssey.travelers);
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
            logoPath: logoPath,
          ),
        );
      }).toList(),
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
    String? logoPath,
  }) {
    final isSwapping = isAiGenerated && widget.swappingPartnerName == title;
    final bool isBookingLogo = logoPath != null && logoPath.contains('booking_logo');
    final bool isHeadoutLogo = logoPath != null && logoPath.contains('headout');
    final bool isGYGLogo = logoPath != null && logoPath.contains('getyourguide');
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
                // Logo avatar: use real brand logo when available, fall back to icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: logoPath != null
                        ? (isHeadoutLogo || isGYGLogo ? Colors.transparent : Colors.white)
                        : color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: logoPath != null && !isHeadoutLogo && !isGYGLogo
                        ? Border.all(color: Colors.black.withValues(alpha: 0.08))
                        : null,
                  ),
                  child: logoPath != null
                      ? ClipOval(
                          child: (isHeadoutLogo || isGYGLogo)
                              ? Image.asset(
                                  logoPath,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                )
                              : Padding(
                                  padding: EdgeInsets.all(isBookingLogo ? 4 : 8),
                                  child: Image.asset(
                                    logoPath,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                        )
                      : Icon(icon, color: color, size: 24),
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
                else if (isAiGenerated && widget.onSwapPartner != null)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: AppColors.actionTeal),
                    onPressed: () => widget.onSwapPartner!(title),
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

class _ActualCostInputField extends StatefulWidget {
  final String initialValue;
  final String currency;
  final ValueChanged<String> onSaved;

  const _ActualCostInputField({
    required this.initialValue,
    required this.currency,
    required this.onSaved,
  });

  @override
  State<_ActualCostInputField> createState() => _ActualCostInputFieldState();
}

class _ActualCostInputFieldState extends State<_ActualCostInputField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ActualCostInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _save();
    }
  }

  void _save() {
    final text = _controller.text.trim();
    if (text != widget.initialValue) {
      widget.onSaved(text);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'e.g. ${widget.currency} 850',
          hintStyle: const TextStyle(fontSize: 11, color: Colors.black26),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.actionTeal, width: 1.5),
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 8, right: 4),
            child: Icon(Icons.receipt_long_rounded, size: 14, color: Colors.black38),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
        ),
        onSubmitted: (_) => _save(),
      ),
    );
  }
}

class _RestaurantListBottomSheet extends StatefulWidget {
  final OdysseyActivity activity;
  final String destination;
  final Function(String) onSelectRestaurant;

  const _RestaurantListBottomSheet({
    required this.activity,
    required this.destination,
    required this.onSelectRestaurant,
  });

  @override
  State<_RestaurantListBottomSheet> createState() => _RestaurantListBottomSheetState();
}

class _RestaurantListBottomSheetState extends State<_RestaurantListBottomSheet> {
  List<RestaurantOption> _restaurants = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.activity.restaurants.isNotEmpty) {
      _restaurants = widget.activity.restaurants;
    } else {
      _fetchDynamicRestaurants();
    }
  }

  Future<void> _fetchDynamicRestaurants() async {
    setState(() => _isLoading = true);
    try {
      final location = widget.activity.name
          .replaceAll(RegExp(r'^(Lunch|Dinner|Breakfast|Brunch)\s+(at|in)\s+', caseSensitive: false), '')
          .trim();
      final query = widget.destination.isNotEmpty
          ? 'restaurants in $location, ${widget.destination}'
          : 'restaurants in $location';

      final places = await GooglePlacesService.searchPlaces(
        query: query,
        latitude: 6.9271,
        longitude: 79.8612,
      );

      if (mounted) {
        setState(() {
          _restaurants = places.take(6).map((p) => RestaurantOption(
            name: p.name,
            cuisine: p.categoryName ?? 'Local Cuisine',
            priceRange: r'$$',
            rating: p.rating > 0 ? '${p.rating} ★' : '4.5 ★',
            tip: p.address ?? 'Popular spot near $location',
          )).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Restaurant Options',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                widget.activity.name,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.actionTeal),
                        SizedBox(height: 12),
                        Text(
                          'Discovering top nearby dining options...',
                          style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_restaurants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.restaurant_rounded, size: 40, color: Colors.black26),
                        const SizedBox(height: 10),
                        const Text(
                          'No specific restaurant list found',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap below to explore all restaurants on Smart Map',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => widget.onSelectRestaurant(widget.activity.name),
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Explore on Smart Map'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.actionTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _restaurants.map((r) => InkWell(
                        onTap: () => widget.onSelectRestaurant(r.name),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F8F8),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (r.rating.isNotEmpty) ...[
                                    const Icon(Icons.star_rounded, size: 14, color: AppColors.ratingGold),
                                    const SizedBox(width: 2),
                                    Text(r.rating, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                  const SizedBox(width: 6),
                                  const Icon(Icons.map_outlined, size: 16, color: AppColors.actionTeal),
                                ],
                              ),
                              if (r.cuisine.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(r.cuisine, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                              ],
                              if (r.priceRange.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.priceRange,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.actionTeal,
                                  ),
                                ),
                              ],
                              if (r.tip.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(r.tip, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                              const SizedBox(height: 6),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.touch_app_outlined, size: 12, color: Colors.black26),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to view on Smart Map',
                                    style: TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
