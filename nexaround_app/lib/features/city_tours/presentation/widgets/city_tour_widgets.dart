import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart' as ll;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour_trip.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';
import 'package:url_launcher/url_launcher.dart';

// The admin panel draws a copy of these screens as its preview
// (nexaround_admin/src/components/CityTourPreview.jsx), so a change to sizes,
// colours or icons here should be made there too.

/// The icon for each way of getting to the next stop (the server's
/// city_tours.TRANSPORT_MODES).
IconData cityTourModeIcon(String mode) {
  switch (mode) {
    case 'metro':
      return Icons.subway_rounded;
    case 'bus':
      return Icons.directions_bus_rounded;
    case 'tram':
      return Icons.tram_rounded;
    case 'train':
      return Icons.train_rounded;
    case 'taxi':
      return Icons.local_taxi_rounded;
    case 'tuk_tuk':
      return Icons.electric_rickshaw_rounded;
    case 'boat':
      return Icons.directions_boat_rounded;
    case 'bike':
      return Icons.directions_bike_rounded;
    case 'car':
      return Icons.directions_car_rounded;
    default:
      return Icons.directions_walk_rounded;
  }
}

/// How long a stop card takes to open, close or shrink to "Visited", and a
/// leg's details to slide open (client: a card snapping shut went unnoticed).
const cityTourMorph = Duration(milliseconds: 350);

/// Lays the card going out over the card coming in without taking room, so
/// the space shrinks or grows straight to the new card's size while the two
/// fade into each other.
Widget _morphLayout(Widget? current, List<Widget> previous) {
  return Stack(
    fit: StackFit.passthrough,
    alignment: Alignment.topCenter,
    children: [
      for (final old in previous) Positioned(left: 0, right: 0, top: 0, child: IgnorePointer(child: old)),
      if (current != null) current,
    ],
  );
}

/// A clock time in the phone's own style: "11:45" or "11:45 AM".
String cityTourClock(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "45 min", "2 h", "1 h 20 min".
String cityTourSpan(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// A step's time from the guide, marked as an estimate: "2 hr 45 min (est)".
/// Left as written when the guide already says so ("about 2 hours").
String cityTourEst(String time) =>
    _alreadyEstimate.hasMatch(time) ? time : '$time (est)';

final _alreadyEstimate = RegExp(r'\b(est|estimated|approx|about|around)\b|~', caseSensitive: false);

/// "On time", "15 min behind", "10 min ahead": the trip against its plan.
String cityTourPace(int behindMinutes) {
  if (behindMinutes.abs() < 5) return 'On time';
  return behindMinutes > 0
      ? '${cityTourSpan(behindMinutes)} behind'
      : '${cityTourSpan(-behindMinutes)} ahead';
}

/// A small grey pill: "5 stops", "6–7 hours", "€40–60".
class CityTourFact extends StatelessWidget {
  final IconData icon;
  final String text;

  const CityTourFact({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.brandGreen),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The facts a guide card and the guide's header show.
List<Widget> cityTourFacts(CityTourCard card) => [
      if (card.dayCount > 1)
        CityTourFact(icon: Icons.calendar_today_rounded, text: '${card.dayCount} days'),
      if (card.stopCount > 0)
        CityTourFact(
          icon: Icons.place_rounded,
          text: card.stopCount == 1 ? '1 stop' : '${card.stopCount} stops',
        ),
      if (card.duration.isNotEmpty)
        CityTourFact(icon: Icons.schedule_rounded, text: card.duration),
      if (card.budget.isNotEmpty)
        CityTourFact(icon: Icons.payments_rounded, text: card.budget),
    ];

/// A stop's number in a circle, on the route and on the map. The start is teal.
class CityTourStopBadge extends StatelessWidget {
  final int number;
  final double size;

  const CityTourStopBadge(this.number, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: number == 1 ? AppColors.brandGreen : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A guide in a list: cover, title, intro and its facts.
class CityTourCardTile extends StatelessWidget {
  final CityTourCard card;
  final VoidCallback onTap;

  const CityTourCardTile({super.key, required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: card.coverUrl.isEmpty
                  ? Container(color: AppColors.surfaceVariant)
                  : CachedNetworkImage(
                      imageUrl: cityTourMediaUrl(card.coverUrl),
                      fit: BoxFit.cover,
                      memCacheWidth: 1080,
                      placeholder: (_, __) => Container(color: AppColors.surface),
                      errorWidget: (_, __, ___) =>
                          Container(color: AppColors.surfaceVariant),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          if (card.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              card.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: cityTourFacts(card)),
        ],
      ),
    );
  }
}

/// The stops on a map, joined in order, by [route] when there is one and
/// otherwise by straight lines ([dashed] for a ride with no route). Inside the
/// page it does not pan or zoom (that would fight the page's scrolling);
/// [onExpand] opens it full screen, where [interactive] is set.
class CityTourMap extends StatelessWidget {
  final List<CityTourStep> stops;
  final bool interactive;
  final VoidCallback? onExpand;
  final void Function(CityTourStep stop)? onStopTap;
  final List<ll.LatLng>? route;
  final bool dashed;
  final double height;

  const CityTourMap({
    super.key,
    required this.stops,
    this.interactive = false,
    this.onExpand,
    this.onStopTap,
    this.route,
    this.dashed = false,
    this.height = 200,
  });

  /// Mapbox streets when the app has its token, else CARTO's free tiles: the
  /// same pair Neva's map and the manual-mode map use.
  static String get tileUrl {
    final token = ApiConstants.mapboxAccessToken;
    return token.isNotEmpty && token != 'YOUR_MAPBOX_ACCESS_TOKEN_HERE'
        ? ApiConstants.mapboxStreets
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
  }

  @override
  Widget build(BuildContext context) {
    final pinned = stops.where((s) => s.hasPin).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    final points = [for (final s in pinned) ll.LatLng(s.lat!, s.lng!)];
    final line = route ?? points;
    final inView = [...points, ...?route];

    final map = FlutterMap(
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 15,
        initialCameraFit: inView.length > 1
            ? CameraFit.coordinates(
                coordinates: inView,
                padding: const EdgeInsets.all(36),
                maxZoom: 16,
              )
            : null,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          maxZoom: 19,
          userAgentPackageName: 'com.nexaround.app',
        ),
        if (line.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: line,
                color: AppColors.brandGreen.withValues(alpha: 0.85),
                strokeWidth: 3,
                pattern: dashed
                    ? StrokePattern.dashed(segments: const [8, 6])
                    : const StrokePattern.solid(),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Last stop first, so the start is drawn on top.
            for (var i = pinned.length - 1; i >= 0; i--)
              Marker(
                point: points[i],
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: onStopTap == null ? null : () => onStopTap!(pinned[i]),
                  child: CityTourStopBadge(pinned[i].number, size: 28),
                ),
              ),
          ],
        ),
      ],
    );

    if (interactive) return map;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            map,
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onExpand),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.textPrimary),
                      SizedBox(width: 4),
                      Text(
                        'Open map',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ride on a small map, from the stop before it to the stop after: the
/// street route when Google has one, else a dashed straight line. A day's first
/// ride has no stop before it, so it shows just where it goes. Its route is
/// fetched the first time the ride is opened. [onExpand] opens it full screen.
class CityTourLegMap extends StatefulWidget {
  final CityTourStep step;
  final CityTourStep? from;
  final CityTourStep to;
  final void Function(List<ll.LatLng>? route)? onExpand;

  const CityTourLegMap({
    super.key,
    required this.step,
    required this.to,
    this.from,
    this.onExpand,
  });

  @override
  State<CityTourLegMap> createState() => _CityTourLegMapState();
}

class _CityTourLegMapState extends State<CityTourLegMap> {
  static const double _height = 170;

  final _service = CityToursService();
  List<ll.LatLng>? _route;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final from = widget.from;
    if (from == null) return;
    _route = _service.cachedLegRoute(widget.step, from, widget.to);
    if (_route == null) {
      _loading = true;
      _fetch(from);
    }
  }

  Future<void> _fetch(CityTourStep from) async {
    final route = await _service.getLegRoute(widget.step, from, widget.to);
    if (!mounted) return;
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The map fits itself to the route when it is built, so it waits for it.
    if (_loading) {
      return Container(
        height: _height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
        ),
      );
    }
    final onExpand = widget.onExpand;
    final from = widget.from;
    return CityTourMap(
      stops: [if (from != null) from, widget.to],
      route: _route,
      dashed: from != null && _route == null,
      height: _height,
      onExpand: onExpand == null ? null : () => onExpand(_route),
    );
  }
}

// ── The route's steps ───────────────────────────────────────────────────────

const _navy = Color(0xFF0F172A);
const _slate = Color(0xFF64748B);
const _line = Color(0xFFE5E9EF);
// Finished steps wear the app's own teal, like the start pin on the map.
const _done = AppColors.brandGreen;

// A visited sight: a clear theme-teal (green) tint, told apart at a glance
// from the light blue sights still to see.
const _visitedFill = Color(0xFFD8EEEE);
const _visitedLine = Color(0xFF8CCACB);

// A sight still to see: light blue, so it holds the eye over the dark ride
// pills and stands apart from a visited one (light teal).
const _sight = Color(0xFFEEF5FF);
const _sightLine = Color(0xFFD6E6FB);

// A break's pill: warm amber, apart from the navy rides.
const _breakPill = Color(0xFF92400E);

/// Where a step stands: no trip on its day ([plain]), finished, skipped, the
/// step in hand, or still to come. A stop passed over (one further on was
/// ticked first) is still to come; a ride or break passed over counts done.
enum CityTourStepState { plain, done, skipped, current, upcoming }

/// A step's state from its place in a trip's schedule; [plain] without one.
CityTourStepState cityTourStepState(CityTourStepTime? time) {
  if (time == null) return CityTourStepState.plain;
  if (time.isDone) return time.skipped ? CityTourStepState.skipped : CityTourStepState.done;
  if (time.passed) return CityTourStepState.done;
  return time.isCurrent ? CityTourStepState.current : CityTourStepState.upcoming;
}

/// A step's own estimated length, "1 hr 15 min (est)": a stop's time to
/// spend, a ride's or break's duration. Clock times are not shown (client:
/// the estimate is enough); the trip still plans with them.
String? cityTourStepEst(CityTourStep step) {
  final text = step.isStop ? step.timeHere : step.duration;
  return text.isEmpty ? null : cityTourEst(text);
}

/// A step's circle: a stop's number, or a ride's or break's icon. On a trip,
/// a tap on the step in hand's circle marks it done (as in Odyssey) and it
/// turns into a teal tick; a skipped one looks like one still to come.
class CityTourTick extends StatelessWidget {
  final CityTourStep step;
  final CityTourStepState state;
  final double size;

  /// Drawn on a photo: the step in hand gets a white ring, not a teal one.
  final bool onPhoto;

  /// Drawn on a dark leg pill of this colour: a walk or break waiting its
  /// turn is a white circle with its icon in the pill's colour.
  final Color? onDark;
  final VoidCallback? onTap;

  const CityTourTick({
    super.key,
    required this.step,
    required this.state,
    this.size = 36,
    this.onPhoto = false,
    this.onDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // No grey skip mark: a skipped step keeps its number or icon.
    final state = this.state == CityTourStepState.skipped ? CityTourStepState.upcoming : this.state;
    final Color fg;
    final BoxDecoration box;
    switch (state) {
      case CityTourStepState.done:
        fg = Colors.white;
        box = BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandGreen, AppColors.brandGreenDark],
          ),
          boxShadow: [
            BoxShadow(color: _done.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        );
      case CityTourStepState.skipped:
        fg = Colors.white;
        box = const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFCBD5E1));
      case CityTourStepState.current:
        fg = AppColors.brandGreen;
        box = BoxDecoration(
          shape: BoxShape.circle,
          color: onPhoto ? Colors.white.withValues(alpha: 0.95) : Colors.white,
          border: Border.all(color: onPhoto ? Colors.white : AppColors.brandGreen, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: onPhoto
                  ? Colors.white.withValues(alpha: 0.3)
                  : AppColors.brandGreen.withValues(alpha: 0.15),
              spreadRadius: 5,
            ),
          ],
        );
      case CityTourStepState.upcoming:
        fg = step.isStop ? _slate : (onDark ?? Colors.white);
        box = step.isStop
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
              )
            : BoxDecoration(
                shape: BoxShape.circle,
                color: onDark != null ? Colors.white : const Color(0xFF334155),
              );
      case CityTourStepState.plain:
        fg = step.isStop ? Colors.white : (onDark ?? Colors.white);
        box = step.isStop
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: step.number == 1 ? AppColors.brandGreen : _navy,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : BoxDecoration(
                shape: BoxShape.circle,
                color: onDark != null ? Colors.white : const Color(0xFF334155),
              );
    }
    final Widget face;
    if (state == CityTourStepState.done) {
      face = Icon(Icons.check_rounded, size: size * 0.48, color: fg);
    } else if (step.isStop) {
      face = Text(
        '${step.number}',
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: fg),
      );
    } else {
      face = Icon(
        step.isBreak ? Icons.restaurant_rounded : cityTourModeIcon(step.mode),
        size: size * 0.56,
        color: fg,
      );
    }
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: box,
      child: face,
    );
    if (onTap == null) return circle;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: circle);
  }
}

/// A stop on the route as a card. With no trip each stop is open: its photo
/// with the name on it, times, notes, story and partner buttons. On a trip
/// the stop in hand is open and edged in teal, and every stop opened has a
/// "Yet to visit" button that marks it visited, in any order; a visited stop
/// opened is tinted teal with its button teal "Visited". Visited stops shrink
/// to a teal-tinted card with a "Visited" chip, ones skipped to a white card
/// with "Not visited", ones passed over (a stop further on ticked first) to
/// a closed card with "Yet to visit", and stops still to come wait as closed
/// cards. Only the traveller opens or folds a card (a tap on it, or "Show
/// less" at its foot); ticking never does.
class CityTourStopCard extends StatelessWidget {
  final CityTourStep step;

  /// Its place in the trip (visited, passed over…); null with no trip.
  final CityTourStepTime? time;
  final CityTourStepState state;
  final bool open;

  /// "START HERE" or "LAST STOP", on a day nobody is following.
  final String? caption;

  final VoidCallback? onTick;
  final VoidCallback? onToggle;

  /// The "Yet to visit" / "Visited" / "Not visited" button: marks the stop
  /// in hand visited, or sets the last one marked back.
  final VoidCallback? onVisited;
  final void Function(CityTourLink link) onLinkTap;

  const CityTourStopCard({
    super.key,
    required this.step,
    required this.time,
    required this.state,
    required this.open,
    required this.onLinkTap,
    this.caption,
    this.onTick,
    this.onToggle,
    this.onVisited,
  });

  bool get _finished => state == CityTourStepState.done || state == CityTourStepState.skipped;

  @override
  Widget build(BuildContext context) {
    final String shape;
    final Widget card;
    if (!open && _finished) {
      shape = 'done';
      card = _doneCard(context);
    } else if (!open) {
      // Still to visit, the one in hand, or a guide read with no trip
      // ("Collapse all").
      shape = 'closed';
      card = _closedCard(context);
    } else {
      shape = 'open';
      card = _openCard(context);
    }
    // Opening, closing or shrinking to "Visited" changes size smoothly while
    // the old look fades into the new (blue into teal), rather than jumping.
    return AnimatedSize(
      duration: cityTourMorph,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: cityTourMorph,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: _morphLayout,
        child: KeyedSubtree(key: ValueKey(shape), child: card),
      ),
    );
  }

  String get _doneText => state == CityTourStepState.skipped ? 'Not visited' : 'Visited';

  /// A finished stop, shrunk: like a closed card, with its status chip.
  Widget _doneCard(BuildContext context) {
    final visited = state == CityTourStepState.done;
    return _compactCard(
      decoration: BoxDecoration(
        color: visited ? _visitedFill : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: visited ? _visitedLine : _line),
      ),
      mark: visited
          ? Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGreen, AppColors.brandGreenDark],
                ),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
            )
          : null,
      trailing: _StatusChip(visited: visited, onTap: onVisited),
    );
  }

  Widget _closedCard(BuildContext context) {
    final span = cityTourStepEst(step);
    return _compactCard(
      decoration: BoxDecoration(
        color: _sight,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _sightLine),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      subtitle: span == null
          ? null
          : Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 12, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    span,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _slate),
                  ),
                ),
              ],
            ),
      trailing: (time?.missed ?? false)
          ? _StatusChip(visited: false, label: 'Yet to visit', onTap: onVisited)
          : const _RoundIcon(icon: Icons.keyboard_arrow_down_rounded),
    );
  }

  /// A shut card: the photo with the stop's number (or [mark]) on it, the
  /// name, an optional line under it, and [trailing] at the right.
  Widget _compactCard({
    required BoxDecoration decoration,
    required Widget trailing,
    Widget? mark,
    Widget? subtitle,
  }) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: decoration,
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: step.photoUrl.isEmpty
                          ? Container(
                              color: AppColors.surface,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.location_on_rounded,
                                size: 24,
                                color: _slate,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: cityTourMediaUrl(step.photoUrl),
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
                              placeholder: (_, __) => Container(color: AppColors.surface),
                              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                            ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    top: 5,
                    child: GestureDetector(
                      onTap: onTick,
                      child: mark ??
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '${step.number}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: _navy),
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    subtitle,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _openCard(BuildContext context) {
    final current = state == CityTourStepState.current;
    final visited = state == CityTourStepState.done;
    final hasPhoto = step.photoUrl.isNotEmpty;
    final body = _body(context);
    // Turning visited while open, the blue fades to teal.
    return AnimatedContainer(
      duration: cityTourMorph,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: visited ? _visitedFill : _sight,
        borderRadius: BorderRadius.circular(26),
        // A black edge in every state (client: the pale one did not show);
        // closed and finished cards keep their light edges.
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: current
                ? AppColors.brandGreen.withValues(alpha: 0.18)
                : _navy.withValues(alpha: 0.06),
            blurRadius: current ? 40 : 18,
            offset: Offset(0, current ? 18 : 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: hasPhoto ? _photoHeader(context) : _plainHeader(context),
            ),
            if (body.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(15, hasPhoto ? 14 : 0, 15, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// The pill at the photo's top left: NOW, Visited, Not visited, or the caption.
  Widget? _badge(BuildContext context) {
    switch (state) {
      case CityTourStepState.current:
        return _Pill(
          color: const Color(0xFFF59E0B),
          shadow: const Color(0xFFF59E0B),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.4), spreadRadius: 3)],
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'NOW',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white),
              ),
            ],
          ),
        );
      case CityTourStepState.done:
      case CityTourStepState.skipped:
        return _Pill(
          color: state == CityTourStepState.done ? _done : const Color(0xFF94A3B8),
          child: Text(
            _doneText,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        );
      case CityTourStepState.plain:
        final caption = this.caption;
        if (caption == null) return null;
        return _Pill(
          color: AppColors.brandGreen,
          child: Text(
            caption,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: Colors.white),
          ),
        );
      case CityTourStepState.upcoming:
        return null;
    }
  }

  Widget _photoHeader(BuildContext context) {
    final badge = _badge(context);
    return SizedBox(
      height: 210,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: cityTourMediaUrl(step.photoUrl),
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            placeholder: (_, __) => Container(color: AppColors.surface),
            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Color(0x00000000), Color(0xD9020617)],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          if (badge != null) Positioned(left: 12, top: 12, child: badge),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(
              children: [
                CityTourTick(step: step, state: state, size: 40, onPhoto: true, onTap: onTick),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        step.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plainHeader(BuildContext context) {
    final badge = _badge(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
      child: Row(
        children: [
          CityTourTick(step: step, state: state, size: 40, onTap: onTick),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge != null) ...[badge, const SizedBox(height: 6)],
                Text(
                  step.name,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    // On a trip the visit button sits beside the time and price chips, at
    // the top, rather than under everything.
    final visit = onVisited != null && state != CityTourStepState.plain
        ? _VisitedButton(
            visited: state == CityTourStepState.done,
            label: state == CityTourStepState.skipped ? 'Not visited' : null,
            onTap: onVisited,
          )
        : null;
    final hasChips = step.timeHere.isNotEmpty || step.price.isNotEmpty;
    final parts = <Widget>[
      if (hasChips || visit != null)
        Row(
          children: [
            Expanded(child: hasChips ? _chips() : const SizedBox.shrink()),
            if (visit != null) ...[const SizedBox(width: 8), visit],
          ],
        ),
      if (step.accessNote.isNotEmpty) _NoteBox(text: step.accessNote),
      if (step.bodyMd.isNotEmpty) ExperienceDescription(markdown: step.bodyMd),
      if (step.links.isNotEmpty) _Links(links: step.links, onLinkTap: onLinkTap),
      if (step.website.isNotEmpty) _MoreInfo(url: step.website),
      if (onToggle != null) _ShowLess(onTap: onToggle),
    ];
    return [
      for (var i = 0; i < parts.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        parts[i],
      ],
    ];
  }

  /// The stop's "1 hr (est)" and price chips.
  Widget _chips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (step.timeHere.isNotEmpty)
          _Chip(
            icon: Icons.hourglass_top_rounded,
            text: cityTourEst(step.timeHere),
            fg: const Color(0xFF5B21B6),
            bg: const Color(0xFFF3EEFF),
            iconColour: const Color(0xFF7C3AED),
          ),
        if (step.price.isNotEmpty)
          _Chip(
            icon: Icons.confirmation_number_rounded,
            text: step.price,
            fg: const Color(0xFF166534),
            bg: const Color(0xFFE7F5EC),
            iconColour: const Color(0xFF15803D),
          ),
      ],
    );
  }
}

/// The way from one stop to the next as a dark navy pill on a dashed line,
/// like the stop numbers, or a break as a warm amber one, so they stand apart
/// from the light blue sights: "Metro · 15 min (est) · Travel to Hôtel des
/// Invalides". Only for reading: rides and breaks are never ticked, on a trip
/// or not (only sights are). A tap opens its directions, notes and partner
/// buttons below it.
class CityTourLegPill extends StatelessWidget {
  final CityTourStep step;
  final bool open;
  final VoidCallback? onToggle;
  final void Function(CityTourLink link) onLinkTap;

  /// The stops either side of a ride, for its map. A day's first ride has no
  /// stop before it; its last, with no stop after it, has no map.
  final CityTourStep? from;
  final CityTourStep? to;

  /// Opens the ride's map full screen.
  final void Function(List<CityTourStep> stops, List<ll.LatLng>? route)? onOpenMap;

  const CityTourLegPill({
    super.key,
    required this.step,
    required this.open,
    required this.onLinkTap,
    this.onToggle,
    this.from,
    this.to,
    this.onOpenMap,
  });

  bool get _hasMap => step.isMove && (to?.hasPin ?? false);
  CityTourStep? get _pinnedFrom => (from?.hasPin ?? false) ? from : null;

  bool get _hasMore =>
      _hasMap ||
      step.directions.isNotEmpty ||
      step.accessNote.isNotEmpty ||
      step.bodyMd.isNotEmpty ||
      step.links.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final title = step.isBreak
        ? (step.breakTitle.isEmpty ? 'Break' : step.breakTitle)
        : (step.modeLabel.isEmpty ? 'Walk' : step.modeLabel);
    final extras = [
      if (step.duration.isNotEmpty) cityTourEst(step.duration),
      if (step.cost.isNotEmpty) step.cost,
      if (!open && step.directions.isNotEmpty) step.directions,
    ];
    final fill = step.isBreak ? _breakPill : _navy;
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: fill.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CityTourTick(step: step, state: CityTourStepState.plain, size: 24, onDark: fill),
          const SizedBox(width: 7),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: title,
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                children: [
                  if (extras.isNotEmpty)
                    TextSpan(
                      text: ' · ${extras.join(' · ')}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.72)),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_hasMore) ...[
            const SizedBox(width: 4),
            Icon(
              open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Dash(height: 12),
        Center(
          child: GestureDetector(
            onTap: _hasMore ? onToggle : null,
            behavior: HitTestBehavior.opaque,
            child: pill,
          ),
        ),
        AnimatedSize(
          duration: cityTourMorph,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: open && _hasMore
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _details(context),
                )
              : const SizedBox(width: double.infinity),
        ),
        const _Dash(height: 12),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final parts = <Widget>[
      if (step.directions.isNotEmpty)
        Text(
          step.directions,
          style: const TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w600, color: _navy),
        ),
      if (_hasMap)
        CityTourLegMap(
          step: step,
          from: _pinnedFrom,
          to: to!,
          onExpand: onOpenMap == null
              ? null
              : (route) => onOpenMap!([if (_pinnedFrom != null) _pinnedFrom!, to!], route),
        ),
      if (step.accessNote.isNotEmpty) _NoteBox(text: step.accessNote),
      if (step.bodyMd.isNotEmpty) ExperienceDescription(markdown: step.bodyMd),
      if (step.links.isNotEmpty) _Links(links: step.links, onLinkTap: onLinkTap),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            parts[i],
          ],
        ],
      ),
    );
  }
}

/// The dashed line between the route's cards.
class _Dash extends StatelessWidget {
  final double height;

  const _Dash({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, child: const CustomPaint(painter: _DashPainter()));
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Dark slate so the route reads clearly between the cards (client).
    final paint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2;
    final x = size.width / 2;
    for (var y = 0.0; y < size.height; y += 8) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, size.height)), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// A coloured pill on a stop's photo: NOW, Done 10:24, START HERE.
class _Pill extends StatelessWidget {
  final Color color;
  final Color? shadow;
  final Widget child;

  const _Pill({required this.color, required this.child, this.shadow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: shadow == null
            ? null
            : [BoxShadow(color: shadow!.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// A small tinted chip with a two-tone icon: "1 hr 15 min (est)".
class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color fg;
  final Color bg;
  final Color iconColour;

  const _Chip({
    required this.icon,
    required this.text,
    required this.fg,
    required this.bg,
    required this.iconColour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColour),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// The guide's "Closure / Access" note, in an amber box.
class _NoteBox extends StatelessWidget {
  final String text;

  const _NoteBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFD97706)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stop's own page ("More info · acropolisofathens.gr"), opened in the
/// browser.
class _MoreInfo extends StatelessWidget {
  final String url;

  const _MoreInfo({required this.url});

  String get _site {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the website.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.language_rounded, size: 17, color: AppColors.brandGreen),
              const SizedBox(width: 8),
              const Text(
                'More info',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _navy),
              ),
              if (site.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    site,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: _slate),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, size: 16, color: _slate),
            ],
          ),
        ),
      ),
    );
  }
}

/// "TICKETS & TOURS" and the step's partner buttons.
class _Links extends StatelessWidget {
  final List<CityTourLink> links;
  final void Function(CityTourLink link) onLinkTap;

  const _Links({required this.links, required this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TICKETS & TOURS',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: _slate),
        ),
        for (final link in links) ...[
          const SizedBox(height: 8),
          CityTourLinkButton(link: link, onTap: () => onLinkTap(link)),
        ],
      ],
    );
  }
}

/// A stop's visit toggle: "Yet to visit" in white with an empty circle, or
/// "Visited" filled in the theme teal with a tick.
class _VisitedButton extends StatelessWidget {
  final bool visited;

  /// In place of "Yet to visit": "Not visited", for a stop passed over.
  final String? label;
  final VoidCallback? onTap;

  const _VisitedButton({required this.visited, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    final fg = visited ? Colors.white : const Color(0xFF475569);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        decoration: BoxDecoration(
          color: visited ? null : Colors.white,
          gradient: visited
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGreen, AppColors.brandGreenDark],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          border: visited ? null : Border.all(color: AppColors.border, width: 1.5),
          boxShadow: visited
              ? [
                  BoxShadow(
                    color: AppColors.brandGreen.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              visited ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 17,
              color: fg,
            ),
            const SizedBox(width: 7),
            Text(
              visited ? 'Visited' : (label ?? 'Yet to visit'),
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shut stop's status: teal "Visited", or grey "Not visited" ([label]
/// "Yet to visit" on one passed over).
class _StatusChip extends StatelessWidget {
  final bool visited;
  final String label;
  final VoidCallback? onTap;

  const _StatusChip({required this.visited, required this.onTap, this.label = 'Not visited'});

  @override
  Widget build(BuildContext context) {
    final fg = visited ? Colors.white : const Color(0xFF475569);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 11, 6),
        decoration: BoxDecoration(
          color: visited ? null : const Color(0xFFF1F5F9),
          gradient: visited
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGreen, AppColors.brandGreenDark],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              visited ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 5),
            Text(
              visited ? 'Visited' : label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Show less ⌃" at the foot of an open sight on a trip: folds it without
/// scrolling back up to its photo.
class _ShowLess extends StatelessWidget {
  final VoidCallback? onTap;

  const _ShowLess({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Show less',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
              ),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Color(0xFF475569)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;

  const _RoundIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: const Color(0xFF475569)),
    );
  }
}

/// A partner button: an Experience (opens in the app) or a partner's site.
class CityTourLinkButton extends StatelessWidget {
  final CityTourLink link;
  final VoidCallback onTap;

  const CityTourLinkButton({super.key, required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final package = link.package;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              if (link.isExperience) _photo(package) else _logo(),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.isExperience
                          ? (package?.vendorName ?? '')
                          : '${link.partnerName} · opens their site',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: _slate),
                    ),
                    if (link.isExperience && (package?.priceLabel ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        package!.priceLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _line),
                ),
                child: Icon(
                  link.isExperience ? Icons.keyboard_arrow_right_rounded : Icons.north_east_rounded,
                  size: 15,
                  color: AppColors.brandGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Image.asset(
        'assets/images/${link.partner}_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.north_east_rounded, size: 18, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _photo(CityTourPackage? package) {
    final url = package?.photoUrl ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        width: 52,
        height: 52,
        child: url.isEmpty
            ? Container(
                color: AppColors.surface,
                child: const Icon(Icons.sailing_rounded, size: 22, color: AppColors.textTertiary),
              )
            : CachedNetworkImage(
                imageUrl: cityTourMediaUrl(url),
                fit: BoxFit.cover,
                memCacheWidth: 200,
                placeholder: (_, __) => Container(color: AppColors.surface),
                errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
              ),
      ),
    );
  }
}

/// The bar under a guide: "Start trip" ("Start Day 2" in a guide of
/// several days), and "Trip finished" once every step is done. While a trip
/// runs there is no bar: each step's circle marks it done.
class CityTourTripBar extends StatelessWidget {
  final CityTourTrip? trip;
  final CityTourSchedule? schedule;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onClose;

  /// "Start trip", or "Start Day 2" in a guide of several days.
  final String startLabel;

  /// Once finished: "Trip finished", or "Day 1 done" in a guide of several
  /// days.
  final String doneTitle;

  /// A finished day with a day after it: "Go to Day 2" in place of Close.
  final String? nextLabel;
  final VoidCallback? onNext;

  /// "Close", or "End guide" on the last day of several.
  final String closeLabel;

  const CityTourTripBar({
    super.key,
    required this.trip,
    required this.schedule,
    required this.busy,
    this.startLabel = 'Start trip',
    this.doneTitle = 'Trip finished',
    this.nextLabel,
    this.onNext,
    this.closeLabel = 'Close',
    required this.onStart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final trip = this.trip;
    final schedule = this.schedule;
    if (trip == null || schedule == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Plans your times from now. Tap each stop’s circle as you finish it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: busy ? null : onStart,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                startLabel,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    final took = (trip.finishedAt ?? DateTime.now()).difference(trip.startedAt).inMinutes;
    return Row(
      children: [
        const Icon(Icons.flag_rounded, size: 26, color: AppColors.brandGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                doneTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                'Took ${cityTourSpan(took)} · ${cityTourPace(schedule.behindMinutes).toLowerCase()}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (nextLabel != null && onNext != null)
          FilledButton(
            onPressed: busy ? null : onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nextLabel!, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          )
        else
          TextButton(
            onPressed: busy ? null : onClose,
            child: Text(closeLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

/// "9:00 AM – 6:55 PM · 6 places": a day at a glance.
String cityTourDayLine(BuildContext context, CityTourDay day) {
  final places = day.stops.length;
  final plan = cityTourDayPlan(day, DateTime.now());
  final first = day.steps.isEmpty ? null : plan[day.steps.first.id];
  final last = day.steps.isEmpty ? null : plan[day.steps.last.id];
  return [
    if (first != null && last != null)
      '${cityTourClock(context, first.start)} – ${cityTourClock(context, last.end)}',
    places == 1 ? '1 place' : '$places places',
  ].join(' · ');
}

/// "Plan your days", two ways. "Day based" asks how many days the traveller
/// has and takes the first ones; "Place based" lists each day's set of places
/// to tick, a day for each set. The two ways sit on a switch: a white pill
/// slides to the one picked, and a tap or a swipe on either side switches.
/// [onShow] gets the day ids in guide order.
class CityTourPlanPicker extends StatefulWidget {
  final List<CityTourDay> days;
  final List<String> initial;
  final ValueChanged<List<String>> onShow;

  const CityTourPlanPicker({
    super.key,
    required this.days,
    this.initial = const [],
    required this.onShow,
  });

  @override
  State<CityTourPlanPicker> createState() => _CityTourPlanPickerState();
}

enum _PlanWay { days, places }

class _CityTourPlanPickerState extends State<CityTourPlanPicker> {
  // Opened again from "Change": the way the plan was made, as far as it shows.
  late _PlanWay? _way = widget.initial.isEmpty
      ? null
      : (_firstDays(widget.initial) ? _PlanWay.days : _PlanWay.places);
  late int _count = _way == _PlanWay.days ? widget.initial.length : 0;
  late final Set<String> _picked = _way == _PlanWay.places ? <String>{...widget.initial} : <String>{};
  // How far a swipe on the switch has gone, to tell which way it went.
  double _swipe = 0;

  /// Whether [ids] are the guide's first days, in order.
  bool _firstDays(List<String> ids) {
    if (ids.length > widget.days.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (widget.days[i].id != ids[i]) return false;
    }
    return true;
  }

  List<String> get _chosen {
    if (_way == _PlanWay.days) return [for (final d in widget.days.take(_count)) d.id];
    if (_way == _PlanWay.places) {
      return [
        for (final d in widget.days)
          if (_picked.contains(d.id)) d.id,
      ];
    }
    return const [];
  }

  static const _question = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary);

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PLAN YOUR DAYS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppColors.brandGreen,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'How do you want to plan?',
            style: TextStyle(
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _waySwitch(),
          if (_way == _PlanWay.days) ...[
            const SizedBox(height: 18),
            const Text('How many days do you have?', style: _question),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.days.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _count = i + 1),
                    child: Container(
                      width: 44,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _count == i + 1 ? AppColors.brandGreen : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _count == i + 1 ? AppColors.brandGreen : AppColors.border),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _count == i + 1 ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_way == _PlanWay.places) ...[
            const SizedBox(height: 18),
            const Text('Pick the sets of places you want', style: _question),
            const SizedBox(height: 4),
            for (var i = 0; i < widget.days.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  final id = widget.days[i].id;
                  if (!_picked.remove(id)) _picked.add(id);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.surfaceVariant)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _picked.contains(widget.days[i].id)
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 22,
                        color: _picked.contains(widget.days[i].id) ? AppColors.brandGreen : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.days[i].title.isEmpty ? 'Places to see' : widget.days[i].title,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cityTourDayLine(context, widget.days[i]),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (_way != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: chosen.isEmpty ? null : () => widget.onShow(chosen),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  chosen.isNotEmpty
                      ? 'Show my ${chosen.length}-day plan'
                      : (_way == _PlanWay.days ? 'Pick your days' : 'Pick your places'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _pickWay(_PlanWay way) {
    if (_way != way) setState(() => _way = way);
  }

  static const _slide = Duration(milliseconds: 260);

  /// "Day based | Place based" as one switch: a grey track, and a white pill
  /// that slides under the way picked (none until one is). Both sides stay
  /// dark enough to read as tappable; a swipe either way switches too.
  Widget _waySwitch() {
    final way = _way;
    return GestureDetector(
      onHorizontalDragStart: (_) => _swipe = 0,
      onHorizontalDragUpdate: (d) => _swipe += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final speed = d.primaryVelocity ?? 0;
        if (_swipe > 24 || speed > 300) {
          _pickWay(_PlanWay.places);
        } else if (_swipe < -24 || speed < -300) {
          _pickWay(_PlanWay.days);
        }
      },
      child: Container(
        width: double.infinity,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE7EAEA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: way == _PlanWay.places ? Alignment.centerRight : Alignment.centerLeft,
              duration: _slide,
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: AnimatedOpacity(
                  opacity: way == null ? 0 : 1,
                  duration: _slide,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: const [
                        BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
                        BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: _waySide(_PlanWay.days, Icons.calendar_today_rounded, 'Day based')),
                Expanded(child: _waySide(_PlanWay.places, Icons.place_rounded, 'Place based')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One side of the switch: teal icon and black label when picked, dark
  /// grey when not.
  Widget _waySide(_PlanWay way, IconData icon, String label) {
    final on = _way == way;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickWay(way),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: on ? AppColors.brandGreen : AppColors.textSecondary),
            const SizedBox(width: 7),
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: _slide,
                // On top of the app's text style (its font), like a Text style.
                style: DefaultTextStyle.of(context).style.merge(TextStyle(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                  color: on ? AppColors.textPrimary : AppColors.textSecondary,
                )),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ring of how far a trip has come: "2/5" in the middle.
class CityTourProgressRing extends StatelessWidget {
  final int done;
  final int total;
  final double size;

  /// On the dark day card: a light track and a mint arc.
  final bool dark;

  const CityTourProgressRing({
    super.key,
    required this.done,
    required this.total,
    this.size = 44,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          share: total == 0 ? 0 : done / total,
          track: dark ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFE2E8F0),
          arc: dark ? const Color(0xFF5EEAD4) : _done,
          stroke: size * 0.1,
        ),
        child: Center(
          child: Text(
            '$done/$total',
            style: TextStyle(
              fontSize: size >= 40 ? 11.5 : 9,
              fontWeight: FontWeight.w900,
              color: dark ? Colors.white : _navy,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color track;
  final Color arc;
  final double stroke;

  const _RingPainter({required this.share, required this.track, required this.arc, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ring, 0, math.pi * 2, false, paint..color = track);
    if (share > 0) {
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * share.clamp(0.0, 1.0), false, paint..color = arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.track != track || old.arc != arc || old.stroke != stroke;
}

/// The traveller's days as small pills: "Day 1", "Day 2"… The one on screen
/// is filled in a dark to teal gradient, and the day a trip is on carries a
/// ring of its stops done. They scroll sideways when there are many.
class CityTourDayCards extends StatelessWidget {
  final List<CityTourDay> days;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// The day a trip is on, with its stops done and of how many.
  final String? tripDayId;
  final int stopsDone;
  final int stopsTotal;

  const CityTourDayCards({
    super.key,
    required this.days,
    required this.selectedId,
    required this.onSelect,
    this.tripDayId,
    this.stopsDone = 0,
    this.stopsTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _pill(days[i], i + 1),
          ],
        ],
      ),
    );
  }

  Widget _pill(CityTourDay day, int number) {
    final on = day.id == selectedId;
    final onTrip = day.id == tripDayId;
    return GestureDetector(
      onTap: () => onSelect(day.id),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.fromLTRB(onTrip ? 6 : 18, 6, 18, 6),
        decoration: BoxDecoration(
          color: on ? null : Colors.white,
          gradient: on
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F172A), Color(0xFF0B3B47), Color(0xFF007A7C)],
                  stops: [0.0, 0.6, 1.3],
                )
              : null,
          borderRadius: BorderRadius.circular(22),
          border: on ? null : Border.all(color: _line),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: AppColors.brandGreen.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onTrip) ...[
              CityTourProgressRing(done: stopsDone, total: stopsTotal, size: 32, dark: on),
              const SizedBox(width: 8),
            ],
            Text(
              'Day $number',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : _navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
