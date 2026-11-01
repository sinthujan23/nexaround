import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
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

const _navy = Color(0xFF0F172A);
const _page = Color(0xFFF7F8FA);
const _slate = Color(0xFF64748B);

/// One guide: the cover with its title and a card of its numbers, what it
/// is, the stops on a map, then the route as cards: a card for each stop
/// and a pill on a dashed line for each walk, ride or break. Opened from a
/// list with the guide's card, which draws the header while the rest loads.
///
/// A guide of several days first asks the traveller for their plan: how many
/// days they have (the first ones), or which days' places they want. The
/// plan is kept on the device; the days then show as cards to swipe.
///
/// A signed-in traveller can start a day's trip: every step gets a planned
/// time and the times after it move as steps are marked (the server pushes a
/// reminder when a step runs over). As in Odyssey, a tap on the step in
/// hand's circle marks it done: finished stops shrink to slim green cards
/// (the last one marked keeps an Undo), the stop in hand stays open with its
/// Skip, and the stops to come wait closed. Each mark scrolls the page on to
/// the next. Scrolled into, any open stop keeps its circle and name pinned
/// under the bar at the top.
class CityTourPage extends StatefulWidget {
  final CityTourCard card;

  const CityTourPage({super.key, required this.card});

  @override
  State<CityTourPage> createState() => _CityTourPageState();
}

class _CityTourPageState extends State<CityTourPage> {
  // The cover's photo, as a share of the screen width; the stats card sits
  // half on it.
  static const double _photoFraction = 0.86;

  final _service = CityToursService();
  final ScrollController _scroll = ScrollController();
  CityTour? _tour;
  String? _error;
  bool _collapsed = false;

  CityTourTrip? _trip;
  bool _tripBusy = false;

  // The days the traveller picked (null: not yet), and the day on screen.
  List<String>? _plan;
  String? _dayId;
  // Redraws the times while a trip runs: a step running over pushes the rest on.
  Timer? _tick;
  // Each step on screen, to scroll to the step in hand after a mark.
  final Map<String, GlobalKey> _stepKeys = {};
  // Steps the traveller opened or closed against their usual state.
  final Set<String> _flipped = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _tour = _service.cachedTour(widget.card.id);
    _plan = _service.savedPlan(widget.card.id);
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

  /// The cover's height under the status bar: the photo, and half the
  /// stats card below it.
  double _coverHeight(double width, CityTourCard card) =>
      width * _photoFraction + (CityTourStatsCard.shows(card) ? CityTourStatsCard.heightFor(context) / 2 : 0);

  void _onScroll() {
    final card = _tour?.card ?? widget.card;
    final collapseAt =
        _coverHeight(MediaQuery.of(context).size.width, card) - kToolbarHeight - 24;
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

  Future<void> _startTrip(CityTourDay day) async {
    if (!CacheService.isLoggedIn()) {
      _say('Sign in to start a trip.');
      return;
    }
    final running = _trip;
    if (running != null && !running.isFinished && running.dayId != day.id) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start this day instead?'),
          content: const Text('The trip you are on now ends.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start this day'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await _tripChange(() async {
      final trip = await _service.startTrip(widget.card.id, dayId: day.id);
      if (mounted) {
        setState(() {
          _trip = trip;
          _dayId = day.id;
          _flipped.clear();
        });
      }
    }, 'start the trip');
  }

  void _showPlan(List<String> dayIds) {
    setState(() {
      _plan = dayIds;
      _dayId = dayIds.first;
    });
    unawaited(_service.savePlan(widget.card.id, dayIds));
  }

  /// The traveller's days the guide still has, in their order; a guide of one
  /// day is just that day.
  List<CityTourDay> _planDays(CityTour tour) {
    if (!tour.hasDays) return tour.days;
    return [
      for (final id in _plan ?? const <String>[])
        if (tour.dayById(id) != null) tour.dayById(id)!,
    ];
  }

  /// The day on screen: the one picked, else the running trip's, else the first.
  CityTourDay? _shownDay(List<CityTourDay> days) {
    if (days.isEmpty) return null;
    final trip = _trip;
    for (final id in [_dayId, if (trip != null && !trip.isFinished) trip.dayId]) {
      for (final d in days) {
        if (d.id == id) return d;
      }
    }
    return days.first;
  }

  /// Whether the trip is on this day (one from before days follows the first).
  bool _tripOn(CityTour tour, CityTourDay day) {
    final trip = _trip;
    if (trip == null) return false;
    return trip.dayId == day.id || (trip.dayId.isEmpty && day.id == tour.days.first.id);
  }

  /// Marks the step in hand done, or skips it with [skip].
  Future<void> _markDone(CityTourStep step, DateTime at, {bool skip = false}) async {
    if (_tripBusy) return;
    setState(() => _tripBusy = true);
    try {
      final trip = await _service.markDone(widget.card.id, step.id, at, skip: skip);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _flipped.clear();
      });
      _revealCurrent(trip);
      _say(
        trip.isFinished
            ? 'Trip finished. Well done!'
            : (skip ? 'Skipped. Times updated.' : 'Marked done. Times updated.'),
        action: SnackBarAction(label: 'Undo', onPressed: _undo),
      );
    } catch (e) {
      // Tried again with the same time, so a dropped signal costs nothing.
      if (mounted) {
        _say(
          userMessageFor(e, action: skip ? 'skip this' : 'mark this done'),
          action: SnackBarAction(label: 'Try again', onPressed: () => _markDone(step, at, skip: skip)),
        );
      }
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  /// Scrolls the step in hand up under the bar at the top, once it is drawn.
  void _revealCurrent(CityTourTrip trip) {
    final tour = _tour;
    if (tour == null || trip.isFinished) return;
    // A trip from before days follows the first day.
    final day = tour.dayById(trip.dayId) ?? (tour.days.isEmpty ? null : tour.days.first);
    if (day == null) return;
    final next = trip.schedule(day.steps, DateTime.now()).current;
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _stepKeys[next.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached || !_scroll.hasClients) return;
      final top = MediaQuery.of(context).padding.top + kToolbarHeight + 16;
      final position = _scroll.position;
      final target = position.pixels + box.localToGlobal(Offset.zero).dy - top;
      _scroll.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _undo() async {
    await _tripChange(() async {
      final trip = await _service.undoDone(widget.card.id);
      if (mounted) {
        setState(() {
          _trip = trip;
          _flipped.clear();
        });
      }
    }, 'undo that');
  }

  /// A tap on a step's circle. On the step in hand it marks it done; on the
  /// last step marked it offers to undo it; anywhere else it says why not.
  Future<void> _tapTick(
    CityTour tour,
    CityTourDay day,
    CityTourStep step,
    CityTourSchedule? schedule,
    String? lastMarkedId,
  ) async {
    if (_tripBusy) return;
    if (schedule == null) {
      if (!CacheService.isLoggedIn()) {
        _say('Sign in to start a trip, then tick each stop as you finish it.');
        return;
      }
      final which = tour.hasDays ? 'Day ${_planDays(tour).indexOf(day) + 1}' : 'the trip';
      _say(
        'Start $which first, then tick each stop as you finish it.',
        action: SnackBarAction(label: 'Start', onPressed: () => _startTrip(day)),
      );
      return;
    }
    final time = schedule.times[step.id];
    if (time == null) return;
    if (time.isCurrent) {
      await _markDone(step, DateTime.now());
      return;
    }
    if (time.isDone) {
      if (step.id != lastMarkedId) {
        _say('Only the last step you marked can be undone.');
        return;
      }
      final undo = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not done yet?'),
          content: Text('“${_stepTitle(day, step)}” goes back to being the step in hand.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Undo'),
            ),
          ],
        ),
      );
      if (undo == true) await _undo();
      return;
    }
    final current = schedule.current;
    if (current != null) _say('Finish or skip “${_stepTitle(day, current)}” first.');
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
      if (mounted) {
        setState(() {
          _trip = null;
          _flipped.clear();
        });
      }
    }, 'end the trip');
  }

  /// A stop's name, a break's, or the ride and where it goes: "Metro to Louvre".
  String _stepTitle(CityTourDay day, CityTourStep step) {
    if (step.isStop) return step.name;
    if (step.isBreak) return step.breakTitle.isEmpty ? 'Break' : step.breakTitle;
    final how = step.modeLabel.isEmpty ? 'Walk' : step.modeLabel;
    final index = day.steps.indexOf(step);
    final next = day.steps.skip(index + 1).where((s) => s.isStop).firstOrNull;
    return next == null ? how : '$how to ${next.name}';
  }

  /// Whether a step's card is open: with no trip every stop is; on a trip
  /// only the step in hand. A tap flips it.
  bool _isOpen(CityTourStep step, CityTourStepState state) {
    final usual = state == CityTourStepState.current || (step.isStop && state == CityTourStepState.plain);
    return _flipped.contains(step.id) ? !usual : usual;
  }

  void _flip(String stepId) {
    setState(() => _flipped.contains(stepId) ? _flipped.remove(stepId) : _flipped.add(stepId));
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

  void _openMap(String title, CityTourDay day) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CityTourMapPage(title: title, stops: day.stops)),
    );
  }

  /// A round button on the cover: frosted glass on the photo, plain grey
  /// once the bar has collapsed.
  Widget _barButton({required IconData icon, required VoidCallback? onTap, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: _collapsed ? const Color(0xFFF1F5F9) : Colors.white.withValues(alpha: 0.18),
        shape: CircleBorder(
          side: _collapsed ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child ??
            IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(icon, color: _collapsed ? _navy : Colors.white, size: 20),
              onPressed: onTap,
            ),
      ),
    );
  }

  Widget _cover(CityTourCard card) {
    final place = [card.city, card.country].where((s) => s.isNotEmpty).join(' · ');
    final stats = CityTourStatsCard.shows(card);
    final statsHeight = CityTourStatsCard.heightFor(context);
    final half = statsHeight / 2;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _page),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: stats ? half : 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (card.coverUrl.isEmpty)
                Container(color: AppColors.surfaceVariant)
              else
                CachedNetworkImage(
                  imageUrl: cityTourMediaUrl(card.coverUrl),
                  fit: BoxFit.cover,
                  memCacheWidth: 1440,
                  placeholder: (_, __) => Container(color: AppColors.surface),
                  errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73020617), Color(0x00020617), Color(0x00020617), Color(0xE0020617)],
                    stops: [0.0, 0.28, 0.45, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: stats ? half + 14 : 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (place.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              place,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      card.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (stats)
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            height: statsHeight,
            child: CityTourStatsCard(card: card),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _tour?.card ?? widget.card;
    final width = MediaQuery.of(context).size.width;
    final tour = _tour;
    final trip = _trip;
    final days = tour == null ? const <CityTourDay>[] : _planDays(tour);
    final day = _shownDay(days);
    final dayTrip = tour != null && day != null && _tripOn(tour, day) ? trip : null;
    final schedule = day == null ? null : dayTrip?.schedule(day.steps, DateTime.now());
    final number = day == null ? 0 : days.indexOf(day) + 1;
    final running = dayTrip != null && !dayTrip.isFinished;

    // The stops on screen that are open, for the pinned header.
    final pins = <_Pin>[];
    if (day != null) {
      for (final step in day.steps) {
        if (!step.isStop) continue;
        final state = cityTourStepState(schedule?.times[step.id]);
        if (!_isOpen(step, state)) continue;
        pins.add(_Pin(_stepKeys.putIfAbsent(step.id, GlobalKey.new), step, state));
      }
    }
    final stops = day?.stops ?? const <CityTourStep>[];
    final stopsDone = schedule == null
        ? 0
        : stops.where((s) => schedule.times[s.id]?.isDone ?? false).length;

    return Scaffold(
      backgroundColor: _page,
      bottomNavigationBar: tour == null || day == null || day.steps.isEmpty || running
          ? null
          : CityTourTripBar(
              trip: dayTrip,
              schedule: schedule,
              busy: _tripBusy,
              startLabel: tour.hasDays ? 'Start Day $number' : 'Start trip',
              onStart: () => _startTrip(day),
              onClose: _closeTrip,
            ),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: _coverHeight(width, card),
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                systemOverlayStyle: _collapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
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
                leading: _barButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                actions: [
                  if (trip != null && !trip.isFinished)
                    _barButton(
                      icon: Icons.more_horiz_rounded,
                      onTap: null,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: _collapsed ? _navy : Colors.white,
                          size: 22,
                        ),
                        onSelected: (_) => _endTrip(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'end', child: Text('End trip')),
                        ],
                      ),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(background: _cover(card)),
              ),
              if (card.summary.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      card.summary,
                      style: const TextStyle(fontSize: 14.5, height: 1.5, color: Color(0xFF475569)),
                    ),
                  ),
                ),
              ..._body(days, day, schedule),
            ],
          ),
          if (tour != null && day != null && pins.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              left: 0,
              right: 0,
              child: _PinnedStep(
                scroll: _scroll,
                pins: pins,
                times: schedule?.times ?? cityTourDayPlan(day, DateTime.now()),
                progress: schedule == null ? null : (stopsDone, stops.length),
                onTick: (step) => _tapTick(tour, day, step, schedule, _lastMarked(day, schedule)),
              ),
            ),
        ],
      ),
    );
  }

  /// The last step marked done or skipped on the day, which Undo takes back.
  String? _lastMarked(CityTourDay day, CityTourSchedule? schedule) {
    if (schedule == null) return null;
    String? last;
    for (final step in day.steps) {
      if (schedule.times[step.id]?.isDone ?? false) last = step.id;
    }
    return last;
  }

  /// A small grey heading over a part of the page, with a teal link.
  Widget _heading(String text, {String? link, IconData? icon, VoidCallback? onTap, String? note}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: _slate),
          ),
        ),
        if (note != null)
          Text(note, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _slate)),
        if (link != null)
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: AppColors.brandGreen),
                  const SizedBox(width: 4),
                ],
                Text(
                  link,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brandGreen),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _body(List<CityTourDay> days, CityTourDay? day, CityTourSchedule? schedule) {
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

    final children = <Widget>[
      if (tour.introMd.isNotEmpty) ...[
        ExperienceDescription(markdown: tour.introMd),
        const SizedBox(height: 20),
      ],
    ];
    if (day == null) {
      if (tour.hasDays) {
        children.add(CityTourPlanPicker(days: tour.days, initial: _plan ?? const [], onShow: _showPlan));
      }
    } else {
      final number = days.indexOf(day) + 1;
      final stops = day.stops;
      final stopsDone = schedule == null
          ? 0
          : stops.where((s) => schedule.times[s.id]?.isDone ?? false).length;
      final pace = schedule == null
          ? ''
          : (_trip?.isFinished ?? false)
              ? 'finished'
              : cityTourPace(schedule.behindMinutes).toLowerCase();
      if (tour.hasDays) {
        children.addAll([
          _heading(
            'YOUR PLAN · ${days.length} DAY${days.length == 1 ? '' : 'S'}',
            link: 'Change',
            icon: Icons.tune_rounded,
            onTap: () => setState(() => _plan = null),
          ),
          const SizedBox(height: 10),
          CityTourDayCards(
            days: days,
            selectedId: day.id,
            onSelect: (id) => setState(() {
              _dayId = id;
              _flipped.clear();
            }),
            tripDayId: schedule == null ? null : day.id,
            stopsDone: stopsDone,
            stopsTotal: stops.length,
            pace: pace,
          ),
          const SizedBox(height: 20),
          _heading(
            'DAY $number · STOPS',
            note: schedule == null ? null : '$stopsDone of ${stops.length} done',
          ),
          const SizedBox(height: 12),
        ]);
      } else {
        children.addAll([
          _heading(
            'THE ROUTE',
            note: schedule == null
                ? null
                : ['$stopsDone of ${stops.length} done', if (pace.isNotEmpty) pace].join(' · '),
          ),
          const SizedBox(height: 12),
        ]);
      }
      if (stops.any((s) => s.hasPin)) {
        children.addAll([
          CityTourMap(
            key: ValueKey(day.id),
            stops: stops,
            onExpand: () => _openMap(tour.hasDays && day.title.isNotEmpty ? day.title : tour.card.title, day),
          ),
          const SizedBox(height: 14),
        ]);
      }
      // A day someone is on shows the trip's times; any other its plan.
      final times = schedule?.times ?? cityTourDayPlan(day, DateTime.now());
      final lastMarked = _lastMarked(day, schedule);
      final lastStopId = stops.length > 1 ? stops.last.id : null;
      for (var i = 0; i < day.steps.length; i++) {
        final step = day.steps[i];
        final state = cityTourStepState(schedule?.times[step.id]);
        final key = _stepKeys.putIfAbsent(step.id, GlobalKey.new);
        void tick() => _tapTick(tour, day, step, schedule, lastMarked);
        if (i > 0 && step.isStop && day.steps[i - 1].isStop) children.add(const SizedBox(height: 12));
        children.add(step.isStop
            ? CityTourStopCard(
                key: key,
                step: step,
                time: times[step.id],
                state: state,
                open: _isOpen(step, state),
                caption: state != CityTourStepState.plain
                    ? null
                    : i == 0
                        ? 'START HERE'
                        : (step.id == lastStopId ? 'LAST STOP' : null),
                canUndo: step.id == lastMarked,
                onTick: tick,
                onToggle: schedule == null ? null : () => _flip(step.id),
                onUndo: _undo,
                onSkip: () => _markDone(step, DateTime.now(), skip: true),
                onLinkTap: _openLink,
              )
            : CityTourLegPill(
                key: key,
                step: step,
                time: times[step.id],
                state: state,
                open: _isOpen(step, state),
                canUndo: step.id == lastMarked,
                onTick: tick,
                onToggle: () => _flip(step.id),
                onUndo: _undo,
                onSkip: () => _markDone(step, DateTime.now(), skip: true),
                onLinkTap: _openLink,
              ));
      }
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 32 + MediaQuery.of(context).padding.bottom),
        // Built all at once, not as they scroll in, so the step in hand can
        // be found and scrolled to (_revealCurrent).
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ];
  }
}

/// An open stop's card, which can pin its header under the bar.
class _Pin {
  final GlobalKey key;
  final CityTourStep step;
  final CityTourStepState state;

  const _Pin(this.key, this.step, this.state);
}

/// The open stop the traveller is scrolling through: its circle, photo, name
/// and times held under the bar at the top, with the day's progress ring.
/// The card's end pushes it away, and the next open stop takes its place.
class _PinnedStep extends StatefulWidget {
  final ScrollController scroll;
  final List<_Pin> pins;
  final Map<String, CityTourStepTime> times;

  /// The day's stops done, of how many, while a trip is on it.
  final (int, int)? progress;
  final void Function(CityTourStep step) onTick;

  const _PinnedStep({
    required this.scroll,
    required this.pins,
    required this.times,
    required this.progress,
    required this.onTick,
  });

  @override
  State<_PinnedStep> createState() => _PinnedStepState();
}

class _PinnedStepState extends State<_PinnedStep> {
  static const double _height = 68;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_moved);
    WidgetsBinding.instance.addPostFrameCallback((_) => _moved());
  }

  @override
  void didUpdateWidget(_PinnedStep old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_moved);
      widget.scroll.addListener(_moved);
    }
    // The cards may move once this frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _moved());
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scroll.hasClients) return const SizedBox.shrink();
    final edge = MediaQuery.of(context).padding.top + kToolbarHeight;
    for (final pin in widget.pins) {
      final box = pin.key.currentContext?.findRenderObject();
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (box is! RenderBox || !box.hasSize || viewport == null) continue;
      // Where the card sits in the list, less how far the list has scrolled:
      // right for this frame, where its painted place would be a frame behind.
      final top = viewport.getOffsetToReveal(box, 0).offset - widget.scroll.offset;
      final end = top + box.size.height;
      if (top >= edge || end <= edge) continue;
      return ClipRect(
        child: Transform.translate(
          offset: Offset(0, math.min(0.0, end - edge - _height)),
          child: _card(context, pin),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _card(BuildContext context, _Pin pin) {
    final step = pin.step;
    final span = cityTourStepSpan(context, step, widget.times[step.id]);
    final progress = widget.progress;
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E9EF)),
            boxShadow: [
              BoxShadow(color: _navy.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              CityTourTick(step: step, state: pin.state, size: 30, onTap: () => widget.onTick(step)),
              const SizedBox(width: 10),
              if (step.photoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CachedNetworkImage(
                      imageUrl: cityTourMediaUrl(step.photoUrl),
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      placeholder: (_, __) => Container(color: AppColors.surface),
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      step.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    if (span != null)
                      Text(span, style: const TextStyle(fontSize: 11.5, color: _slate)),
                  ],
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                CityTourProgressRing(done: progress.$1, total: progress.$2, size: 34),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A day's map full screen: pan, zoom, and tap a stop for its name.
class _CityTourMapPage extends StatefulWidget {
  final String title;
  final List<CityTourStep> stops;

  const _CityTourMapPage({required this.title, required this.stops});

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
          widget.title,
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
              stops: widget.stops,
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
