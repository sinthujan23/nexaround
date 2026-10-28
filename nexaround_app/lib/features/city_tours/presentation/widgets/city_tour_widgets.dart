import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart' as ll;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';

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

/// The stops on a map, joined in order. Inside the page it does not pan or
/// zoom (that would fight the page's scrolling); [onExpand] opens it full
/// screen, where [interactive] is set.
class CityTourMap extends StatelessWidget {
  final List<CityTourStep> stops;
  final bool interactive;
  final VoidCallback? onExpand;
  final void Function(CityTourStep stop)? onStopTap;

  const CityTourMap({
    super.key,
    required this.stops,
    this.interactive = false,
    this.onExpand,
    this.onStopTap,
  });

  /// Mapbox streets when the app has its token, else CARTO's free tiles: the
  /// same pair Neva's map and the manual-mode map use.
  static String get _tileUrl {
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

    final map = FlutterMap(
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 15,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(
                coordinates: points,
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
          urlTemplate: _tileUrl,
          subdomains: const ['a', 'b', 'c', 'd'],
          maxZoom: 19,
          userAgentPackageName: 'com.nexaround.app',
        ),
        if (points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: AppColors.brandGreen.withValues(alpha: 0.85),
                strokeWidth: 3,
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
        height: 200,
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

/// One step of the route: a numbered stop, or the ride to the next one, on a
/// grey line that joins them.
class CityTourStepTile extends StatelessWidget {
  final CityTourStep step;
  final bool isFirst;
  final bool isLast;
  final bool isLastStop;
  final void Function(CityTourLink link) onLinkTap;

  const CityTourStepTile({
    super.key,
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.isLastStop,
    required this.onLinkTap,
  });

  static const double _rail = 28;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (!(isFirst && isLast))
          Positioned(
            left: _rail / 2 - 1,
            top: isFirst ? _rail / 2 : 0,
            bottom: isLast ? null : 0,
            height: isLast ? _rail / 2 : null,
            width: 2,
            child: const ColoredBox(color: AppColors.border),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _rail,
                child: step.isStop ? CityTourStopBadge(step.number) : _modeBadge(),
              ),
              const SizedBox(width: 14),
              Expanded(child: step.isStop ? _stop() : _move()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeBadge() {
    return Container(
      width: _rail,
      height: _rail,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Icon(cityTourModeIcon(step.mode), size: 15, color: AppColors.textSecondary),
    );
  }

  Widget _stop() {
    final caption = isFirst ? 'START HERE' : (isLastStop ? 'LAST STOP' : null);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null) ...[
            Text(
              caption,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: AppColors.brandGreen,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            step.name,
            style: const TextStyle(
              fontSize: 17,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          if (step.timeHere.isNotEmpty || step.price.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (step.timeHere.isNotEmpty)
                  _meta(Icons.hourglass_bottom_rounded, step.timeHere),
                if (step.price.isNotEmpty)
                  _meta(Icons.confirmation_number_rounded, step.price),
              ],
            ),
          ],
          if (step.photoUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: CachedNetworkImage(
                  imageUrl: cityTourMediaUrl(step.photoUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 1080,
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                ),
              ),
            ),
          ],
          if (step.bodyMd.isNotEmpty) ...[
            const SizedBox(height: 10),
            ExperienceDescription(markdown: step.bodyMd),
          ],
          ..._links(12),
        ],
      ),
    );
  }

  Widget _move() {
    final extras = [
      if (step.duration.isNotEmpty) step.duration,
      if (step.cost.isNotEmpty) step.cost,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: step.modeLabel.isEmpty ? 'Walk' : step.modeLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              children: [
                if (extras.isNotEmpty)
                  TextSpan(
                    text: ' · ${extras.join(' · ')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
          if (step.directions.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              step.directions,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          if (step.bodyMd.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExperienceDescription(markdown: step.bodyMd),
          ],
          ..._links(10),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  List<Widget> _links(double gap) {
    if (step.links.isEmpty) return const [];
    return [
      SizedBox(height: gap),
      for (var i = 0; i < step.links.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        CityTourLinkButton(link: step.links[i], onTap: () => onLinkTap(step.links[i])),
      ],
    ];
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              if (link.isExperience) _photo(package) else _logo(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
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
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
              Icon(
                link.isExperience ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                size: link.isExperience ? 22 : 18,
                color: AppColors.textTertiary,
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Image.asset(
        'assets/images/${link.partner}_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _photo(CityTourPackage? package) {
    final url = package?.photoUrl ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
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
