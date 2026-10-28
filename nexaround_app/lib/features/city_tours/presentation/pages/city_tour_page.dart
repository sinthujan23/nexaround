import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/city_tours/data/city_tours_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour_trip.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_link_page.dart';
import 'package:nexaround_app/features/experiences/presentation/widgets/experience_description.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a guide from its id alone (a trip reminder): from the device's copy
/// when there is one, else after loading it.
Future<void> openCityTourById(BuildContext context, String tourId) async {
  final service = CityToursService();
  var tour = service.cachedTour(tourId);
  if (tour == null) {
    try {
      tour = await service.getTour(tourId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessageFor(e, action: 'open this guide'))),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CityTourPage(card: tour!.card)),
  );
}

/// One guide: the cover, what it is, the stops on a map, then the route step
/// by step with its partner buttons. Opened from a list with the guide's
/// card, which draws the header while the rest loads.
///
/// A signed-in traveller can start a trip: every step gets a planned time,
/// the bar at the bottom asks them to mark the step in hand done, and the
/// times after it move to match (the server pushes a reminder when a step
/// runs over).
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

  CityTourTrip? _trip;
  bool _tripBusy = false;
  // Redraws the times while a trip runs: a step running over pushes the rest on.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _tour = _service.cachedTour(widget.card.id);
    _fetch();
    if (CacheService.isLoggedIn()) {
      _trip = _service.cachedTrip(widget.card.id);
      _loadTrip();
    }
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      final trip = _trip;
      if (mounted && trip != null && !trip.isFinished) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
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

  Future<void> _loadTrip() async {
    try {
      final trip = await _service.getTrip(widget.card.id);
      if (mounted) setState(() => _trip = trip);
    } catch (e) {
      // The device's copy stays on screen.
      debugPrint('City tour trip not loaded: $e');
    }
  }

  void _say(String text, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Runs one trip change, one at a time; a failure is said, not thrown.
  Future<bool> _tripChange(Future<void> Function() change, String action) async {
    if (_tripBusy) return false;
    setState(() => _tripBusy = true);
    try {
      await change();
      return true;
    } catch (e) {
      if (mounted) _say(userMessageFor(e, action: action));
      return false;
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  Future<void> _startTrip() async {
    if (!CacheService.isLoggedIn()) {
      _say('Sign in to start a trip.');
      return;
    }
    await _tripChange(() async {
      final trip = await _service.startTrip(widget.card.id);
      if (mounted) setState(() => _trip = trip);
    }, 'start the trip');
  }

  Future<void> _markDone(CityTourStep step, DateTime at) async {
    if (_tripBusy) return;
    setState(() => _tripBusy = true);
    try {
      final trip = await _service.markDone(widget.card.id, step.id, at);
      if (!mounted) return;
      setState(() => _trip = trip);
      _say(
        trip.isFinished ? 'Trip finished. Well done!' : 'Marked done. Times updated.',
        action: SnackBarAction(label: 'Undo', onPressed: _undo),
      );
    } catch (e) {
      // Tried again with the same time, so a dropped signal costs nothing.
      if (mounted) {
        _say(
          userMessageFor(e, action: 'mark this done'),
          action: SnackBarAction(label: 'Try again', onPressed: () => _markDone(step, at)),
        );
      }
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  Future<void> _undo() async {
    await _tripChange(() async {
      final trip = await _service.undoDone(widget.card.id);
      if (mounted) setState(() => _trip = trip);
    }, 'undo that');
  }

  Future<void> _endTrip() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this trip?'),
        content: const Text('You can start the guide again any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End trip'),
          ),
        ],
      ),
    );
    if (end == true) await _closeTrip();
  }

  Future<void> _closeTrip() async {
    await _tripChange(() async {
      await _service.endTrip(widget.card.id);
      if (mounted) setState(() => _trip = null);
    }, 'end the trip');
  }

  /// A stop's name, or the ride and where it goes: "Metro to Louvre".
  String _stepTitle(CityTour tour, CityTourStep step) {
    if (step.isStop) return step.name;
    final how = step.modeLabel.isEmpty ? 'Walk' : step.modeLabel;
    final index = tour.steps.indexOf(step);
    final next = tour.steps.skip(index + 1).where((s) => s.isStop).firstOrNull;
    return next == null ? how : '$how to ${next.name}';
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
    final tour = _tour;
    final trip = _trip;
    final schedule = tour == null || trip == null ? null : trip.schedule(tour.steps, DateTime.now());
    final current = schedule?.current;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: tour == null || tour.steps.isEmpty
          ? null
          : CityTourTripBar(
              trip: trip,
              schedule: schedule,
              currentTitle: current == null ? '' : _stepTitle(tour, current),
              busy: _tripBusy,
              onStart: _startTrip,
              onMarkDone: () {
                if (current != null) _markDone(current, DateTime.now());
              },
              onClose: _closeTrip,
            ),
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
            actions: [
              if (trip != null && !trip.isFinished)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: const CircleBorder(),
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textPrimary, size: 20),
                      onSelected: (_) => _endTrip(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'end', child: Text('End trip')),
                      ],
                    ),
                  ),
                ),
            ],
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
          ..._body(schedule),
        ],
      ),
    );
  }

  List<Widget> _body(CityTourSchedule? schedule) {
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
                time: schedule?.times[tour.steps[i].id],
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
