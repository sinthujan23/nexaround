import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_link_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';
import 'package:url_launcher/url_launcher.dart';

/// One guide: the cover, what it is, the stops on a map, then the route step
/// by step with its partner buttons. Opened from a list with the guide's
/// card, which draws the header while the rest loads.
class CityTourPage extends StatefulWidget {
  final CityTourCard card;

  const CityTourPage({super.key, required this.card});

  @override
  State<CityTourPage> createState() => _CityTourPageState();
}

class _CityTourPageState extends State<CityTourPage> {
  // The cover's height, as a share of the screen width.
  static const double _heroFraction = 0.62;

  final _service = CityToursService();
  final ScrollController _scroll = ScrollController();
  CityTour? _tour;
  String? _error;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _tour = _service.cachedTour(widget.card.id);
    _fetch();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapseAt =
        MediaQuery.of(context).size.width * _heroFraction - kToolbarHeight - 24;
    final collapsed = _scroll.offset > collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  Future<void> _fetch() async {
    try {
      final tour = await _service.getTour(widget.card.id);
      if (!mounted) return;
      setState(() {
        _tour = tour;
        _error = null;
      });
    } catch (e) {
      if (!mounted || _tour != null) return;
      setState(() => _error = userMessageFor(e, action: 'load this guide'));
    }
  }

  Future<void> _openLink(CityTourLink link) async {
    final package = link.package;
    if (link.isExperience && package != null) {
      unawaited(_service.recordTap(widget.card.id, link.id));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ExperienceLinkPage(packageId: package.id)),
      );
      return;
    }
    final uri = Uri.tryParse(link.url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${link.partnerName}.')),
      );
    }
  }

  void _openMap(CityTour tour) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CityTourMapPage(tour: tour)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _tour?.card ?? widget.card;
    final width = MediaQuery.of(context).size.width;
    final place = [card.city, card.country].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: width * _heroFraction,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            centerTitle: false,
            titleSpacing: 4,
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: card.coverUrl.isEmpty
                  ? Container(color: AppColors.surfaceVariant)
                  : CachedNetworkImage(
                      imageUrl: cityTourMediaUrl(card.coverUrl),
                      fit: BoxFit.cover,
                      memCacheWidth: 1440,
                      placeholder: (_, __) => Container(color: AppColors.surface),
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (place.isNotEmpty)
                    Text(
                      place.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    card.title,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (card.summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.summary,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: cityTourFacts(card)),
                ],
              ),
            ),
          ),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    final tour = _tour;
    if (tour == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: _error == null
                ? const CircularProgressIndicator(color: AppColors.brandGreen)
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _fetch();
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ];
    }

    final stops = tour.stops;
    final lastStopId = stops.isEmpty ? null : stops.last.id;
    final hasPins = stops.any((s) => s.hasPin);
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 32 + MediaQuery.of(context).padding.bottom),
        sliver: SliverList.list(
          children: [
            if (hasPins)
              CityTourMap(stops: stops, onExpand: () => _openMap(tour)),
            if (tour.introMd.isNotEmpty) ...[
              const SizedBox(height: 20),
              ExperienceDescription(markdown: tour.introMd),
            ],
            const SizedBox(height: 24),
            const Text(
              'The route',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < tour.steps.length; i++)
              CityTourStepTile(
                step: tour.steps[i],
                isFirst: i == 0,
                isLast: i == tour.steps.length - 1,
                isLastStop: stops.length > 1 && tour.steps[i].id == lastStopId,
                onLinkTap: _openLink,
              ),
          ],
        ),
      ),
    ];
  }
}

/// The guide's map full screen: pan, zoom, and tap a stop for its name.
class _CityTourMapPage extends StatefulWidget {
  final CityTour tour;

  const _CityTourMapPage({required this.tour});

  @override
  State<_CityTourMapPage> createState() => _CityTourMapPageState();
}

class _CityTourMapPageState extends State<_CityTourMapPage> {
  CityTourStep? _picked;

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          widget.tour.card.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CityTourMap(
              stops: widget.tour.stops,
              interactive: true,
              onStopTap: (stop) => setState(() => _picked = stop),
            ),
          ),
          if (picked != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: Material(
                color: Colors.white,
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CityTourStopBadge(picked.number),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          picked.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => setState(() => _picked = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
