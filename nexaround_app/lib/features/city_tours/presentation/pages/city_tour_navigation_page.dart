import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong2.dart' as ll;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_directions_service.dart' as directions;
import 'package:nexaround_app/core/services/permission_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour_navigation.dart';
import 'package:nexaround_app/features/city_tours/presentation/widgets/city_tour_widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const _navy = Color(0xFF0F172A);
const _slate = Color(0xFF64748B);

enum _Stage { starting, following, arrived, problem }

/// Live directions for a guide's ride, from where the traveller is to [destination].
///
/// A blue dot and the map follow the GPS. Walks, bikes and drives show the
/// next turn and get a new route when the traveller strays; public transport
/// shows the written steps instead (which line, where to get on and off), as
/// there are no turns to call out on a train. It needs the app open: the
/// screen stays on while it runs. Google is paid per route, so a route is asked
/// for once at the start and again only on straying, up to [_maxNewRoutes].
class CityTourNavigationPage extends StatefulWidget {
  final CityTourStep ride;
  final CityTourStep destination;

  const CityTourNavigationPage({super.key, required this.ride, required this.destination});

  @override
  State<CityTourNavigationPage> createState() => _CityTourNavigationPageState();
}

class _CityTourNavigationPageState extends State<CityTourNavigationPage> {
  // Further than this the traveller isn't on this ride: no route is bought.
  static const double _tooFarMetres = 150000;
  // A GPS fix worse than this moves the dot but decides nothing.
  static const double _worstFixMetres = 60;
  // This many fixes in a row away from the route count as straying.
  static const int _strayFixesNeeded = 3;
  static const Duration _newRouteGap = Duration(seconds: 20);
  static const int _maxNewRoutes = 6;

  final MapController _map = MapController();
  StreamSubscription<geo.Position>? _positions;
  bool _mapReady = false;

  _Stage _stage = _Stage.starting;
  String _problem = '';
  bool _canRetry = true;
  bool _offerLocationSettings = false;

  directions.WalkingRoute? _route;
  CityTourRouteLine? _line;
  List<Polyline> _routeLines = const [];

  ll.LatLng? _here;
  double _along = 0;
  bool _following = true;
  bool _gettingNewRoute = false;
  int _strayFixes = 0;
  int _newRoutes = 0;
  DateTime? _lastNewRoute;

  String get _mode => widget.ride.directionsMode ?? 'walking';
  bool get _transit => _mode == 'transit';
  bool get _onFoot => _mode == 'walking';
  double get _offRouteMetres => _onFoot ? 35 : 70;
  double get _arriveMetres => _onFoot ? 25 : 60;
  double get _zoom => _onFoot ? 17.5 : (_transit ? 14.5 : 16);
  ll.LatLng get _target => ll.LatLng(widget.destination.lat!, widget.destination.lng!);

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _positions?.cancel();
    _keepScreenOn(false);
    _map.dispose();
    super.dispose();
  }

  void _keepScreenOn(bool on) {
    WakelockPlus.toggle(enable: on).catchError((_) {});
  }

  void _fail(String message, {bool canRetry = true, bool offerLocationSettings = false}) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.problem;
      _problem = message;
      _canRetry = canRetry;
      _offerLocationSettings = offerLocationSettings;
    });
  }

  void _retry() {
    setState(() => _stage = _Stage.starting);
    _begin();
  }

  Future<void> _begin() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      _fail('Turn on location on your phone to start.', offerLocationSettings: true);
      return;
    }
    if (!await PermissionService.requestLocationPermission()) {
      _fail('NexAround needs your location to guide you.');
      return;
    }
    final fix = await _currentFix();
    if (!mounted) return;
    if (fix == null) {
      _fail("We couldn't find your location. Please try again.");
      return;
    }
    final here = ll.LatLng(fix.latitude, fix.longitude);
    final away = cityTourMetres(here, _target);
    if (away > _tooFarMetres) {
      _fail(
        "You're ${cityTourDistanceText(away)} from ${widget.destination.name}. Start this when you're nearby.",
        canRetry: false,
      );
      return;
    }
    final route = await _fetchRoute(here);
    if (!mounted) return;
    if (route == null) {
      _fail("We couldn't find a route from where you are. Please try again.");
      return;
    }
    setState(() {
      _useRoute(route);
      _here = here;
      _stage = _Stage.following;
    });
    _follow(_zoom);
    _keepScreenOn(true);
    _positions = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(_onFix, onError: (Object _) {});
  }

  Future<geo.Position?> _currentFix() async {
    try {
      return await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      try {
        return await geo.Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<directions.WalkingRoute?> _fetchRoute(ll.LatLng from) async {
    final route = await directions.GoogleDirectionsService.getWalkingRoute(
      originLat: from.latitude,
      originLng: from.longitude,
      destLat: _target.latitude,
      destLng: _target.longitude,
      mode: _mode,
      exactOrigin: true,
    );
    return route == null || route.steps.isEmpty ? null : route;
  }

  void _useRoute(directions.WalkingRoute route) {
    final line = CityTourRouteLine([
      for (final step in route.steps)
        [for (final p in step.polylinePoints) ll.LatLng(p.latitude, p.longitude)],
    ]);
    _route = route;
    _line = line;
    _along = 0;
    _strayFixes = 0;
    _routeLines = [
      Polyline(points: line.points, color: AppColors.brandGreen, strokeWidth: 5),
    ];
  }

  void _onFix(geo.Position fix) {
    final line = _line;
    if (!mounted || line == null || _stage != _Stage.following) return;
    final here = ll.LatLng(fix.latitude, fix.longitude);
    final good = fix.accuracy <= _worstFixMetres;
    final spot = line.locate(here, from: _along);
    final onRoute = spot.off <= _offRouteMetres + math.min(fix.accuracy, 30);
    setState(() {
      _here = here;
      if (good && onRoute) _along = spot.along;
    });
    if (_following) _follow(_mapReady ? _map.camera.zoom : _zoom);
    if (!good) return;

    final nearStop = cityTourMetres(here, _target) <= _arriveMetres;
    final endOfRoute = onRoute && line.length - spot.along <= 20;
    if (nearStop || endOfRoute) {
      _arrive();
      return;
    }
    if (_transit) return;
    _strayFixes = onRoute ? 0 : _strayFixes + 1;
    if (_strayFixes >= _strayFixesNeeded) _getNewRoute(here);
  }

  Future<void> _getNewRoute(ll.LatLng here) async {
    final last = _lastNewRoute;
    final now = DateTime.now();
    if (_gettingNewRoute || _newRoutes >= _maxNewRoutes) return;
    if (last != null && now.difference(last) < _newRouteGap) return;
    _newRoutes++;
    _lastNewRoute = now;
    setState(() => _gettingNewRoute = true);
    final route = await _fetchRoute(here);
    if (!mounted) return;
    setState(() {
      _gettingNewRoute = false;
      // On failure the old route stays, and the next stray fixes try again.
      if (route != null) _useRoute(route);
    });
  }

  void _arrive() {
    _positions?.cancel();
    _positions = null;
    _keepScreenOn(false);
    setState(() => _stage = _Stage.arrived);
  }

  void _onMapReady() {
    _mapReady = true;
    if (_here != null) _follow(_zoom);
  }

  void _follow(double zoom) {
    final here = _here;
    if (_mapReady && here != null) _map.move(here, zoom);
  }

  // A drag or pinch lets the traveller look around; the button brings them back.
  void _onCameraMoved(MapCamera camera, bool hasGesture) {
    if (hasGesture && _following) setState(() => _following = false);
  }

  void _recentre() {
    setState(() => _following = true);
    _follow(_zoom);
  }

  void _close() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final here = _here;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _target,
                initialZoom: 15,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: _onMapReady,
                onPositionChanged: _onCameraMoved,
              ),
              children: [
                TileLayer(
                  urlTemplate: CityTourMap.tileUrl,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  maxZoom: 19,
                  userAgentPackageName: 'com.nexaround.app',
                ),
                if (_routeLines.isNotEmpty) PolylineLayer(polylines: _routeLines),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _target,
                      width: 34,
                      height: 34,
                      child: CityTourStopBadge(widget.destination.number, size: 32),
                    ),
                    if (here != null)
                      Marker(point: here, width: 24, height: 24, child: const _BlueDot()),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_stage == _Stage.following && !_transit) _turnCard(),
                  if (_gettingNewRoute) ...[const SizedBox(height: 8), const _NewRouteChip()],
                  const Spacer(),
                  if (_stage == _Stage.following && !_following) ...[
                    Align(alignment: Alignment.centerRight, child: _RecentreButton(onTap: _recentre)),
                    const SizedBox(height: 10),
                  ],
                  _bottomCard(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The next thing to do, and how far off it is.
  Widget _turnCard() {
    final route = _route;
    final line = _line;
    if (route == null || line == null) return const SizedBox.shrink();
    final steps = route.steps;
    final current = line.stepAt(_along);
    // At the very start, the first step ("Head north…"); then the one after
    // the step being walked, which begins with the next turn.
    final next = current == 0 && _along < 20 ? 0 : current + 1;
    final IconData icon;
    final String text;
    final double metres;
    if (next >= steps.length) {
      icon = Icons.flag_rounded;
      text = 'Arrive at ${widget.destination.name}';
      metres = line.length - _along;
    } else {
      icon = next == 0 ? Icons.navigation_rounded : _turnIcon(steps[next].maneuver);
      text = steps[next].instruction;
      metres = line.stepEnds[next == 0 ? 0 : next - 1] - _along;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 38, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cityTourDistanceText(math.max(0.0, metres)),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomCard(BuildContext context) {
    switch (_stage) {
      case _Stage.starting:
        return _Card(
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Finding your route…',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _navy),
                ),
              ),
              TextButton(onPressed: _close, child: const Text('Close')),
            ],
          ),
        );
      case _Stage.problem:
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.location_off_rounded, size: 30, color: _slate),
              const SizedBox(height: 10),
              Text(
                _problem,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600, color: _navy),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _close, child: const Text('Close')),
                  if (_offerLocationSettings)
                    TextButton(
                      onPressed: geo.Geolocator.openLocationSettings,
                      child: const Text('Open settings'),
                    ),
                  if (_canRetry) ...[
                    const SizedBox(width: 6),
                    _PrimaryButton(label: 'Try again', onTap: _retry),
                  ],
                ],
              ),
            ],
          ),
        );
      case _Stage.arrived:
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_rounded, size: 36, color: AppColors.brandGreen),
              const SizedBox(height: 8),
              const Text(
                "You've arrived",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _navy),
              ),
              const SizedBox(height: 2),
              Text(
                widget.destination.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: _slate),
              ),
              const SizedBox(height: 14),
              _PrimaryButton(label: 'Done', onTap: _close),
            ],
          ),
        );
      case _Stage.following:
        return _Card(child: _followingCard(context));
    }
  }

  Widget _followingCard(BuildContext context) {
    final route = _route;
    final line = _line;
    if (route == null || line == null) return const SizedBox.shrink();
    final left = math.max(0.0, line.length - _along);
    final share = line.length == 0 ? 0.0 : left / line.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cityTourTimeText(route.totalDurationS * share)} · ${cityTourDistanceText(left)} left',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _slate),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _close,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
              child: const Text('End', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (_transit) ...[
          const Divider(height: 18, color: Color(0xFFE5E9EF)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.36),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: route.steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _TransitRow(step: route.steps[i]),
            ),
          ),
        ],
      ],
    );
  }
}

IconData _turnIcon(String? maneuver) {
  switch (maneuver) {
    case 'turn-left':
      return Icons.turn_left_rounded;
    case 'turn-right':
      return Icons.turn_right_rounded;
    case 'turn-slight-left':
      return Icons.turn_slight_left_rounded;
    case 'turn-slight-right':
      return Icons.turn_slight_right_rounded;
    case 'turn-sharp-left':
      return Icons.turn_sharp_left_rounded;
    case 'turn-sharp-right':
      return Icons.turn_sharp_right_rounded;
    case 'uturn-left':
      return Icons.u_turn_left_rounded;
    case 'uturn-right':
      return Icons.u_turn_right_rounded;
    case 'roundabout-left':
      return Icons.roundabout_left_rounded;
    case 'roundabout-right':
      return Icons.roundabout_right_rounded;
    case 'fork-left':
      return Icons.fork_left_rounded;
    case 'fork-right':
      return Icons.fork_right_rounded;
    case 'ramp-left':
      return Icons.ramp_left_rounded;
    case 'ramp-right':
      return Icons.ramp_right_rounded;
    case 'merge':
      return Icons.merge_rounded;
    default:
      return Icons.straight_rounded;
  }
}

IconData _vehicleIcon(String type) {
  switch (type) {
    case 'SUBWAY':
    case 'METRO_RAIL':
    case 'MONORAIL':
      return Icons.subway_rounded;
    case 'TRAM':
    case 'CABLE_CAR':
    case 'FUNICULAR':
    case 'GONDOLA_LIFT':
      return Icons.tram_rounded;
    case 'RAIL':
    case 'HEAVY_RAIL':
    case 'COMMUTER_TRAIN':
    case 'HIGH_SPEED_TRAIN':
    case 'LONG_DISTANCE_TRAIN':
      return Icons.train_rounded;
    case 'FERRY':
      return Icons.directions_boat_rounded;
    default:
      return Icons.directions_bus_rounded;
  }
}

/// A white rounded panel over the map.
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    );
  }
}

/// The traveller on the map.
class _BlueDot extends StatelessWidget {
  const _BlueDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6),
        ],
      ),
    );
  }
}

class _NewRouteChip extends StatelessWidget {
  const _NewRouteChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Text(
          'Finding a new route…',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navy),
        ),
      ),
    );
  }
}

/// Puts the map back on the traveller after they moved it.
class _RecentreButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RecentreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.my_location_rounded, size: 22, color: AppColors.brandGreen),
        ),
      ),
    );
  }
}

/// A line of a public transport route: a walk, or a ride with where to get on
/// and off.
class _TransitRow extends StatelessWidget {
  final directions.RouteStep step;

  const _TransitRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final transit = step.transit;
    final String title;
    final List<String> lines;
    if (transit == null) {
      title = step.instruction;
      lines = ['${step.distanceText} · ${step.durationText}'];
    } else {
      final vehicle = [transit.vehicleName, transit.lineName].where((s) => s.isNotEmpty).join(' ');
      title = transit.headsign.isEmpty ? vehicle : '$vehicle towards ${transit.headsign}';
      final stops = transit.stopCount == 1 ? '1 stop' : '${transit.stopCount} stops';
      lines = [
        'Get on at ${transit.departureStop}',
        'Get off at ${transit.arrivalStop}',
        '$stops · ${step.durationText}',
      ];
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          transit == null ? Icons.directions_walk_rounded : _vehicleIcon(transit.vehicleType),
          size: 22,
          color: AppColors.brandGreen,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w700, color: _navy),
              ),
              for (final line in lines)
                Text(line, style: const TextStyle(fontSize: 12.5, height: 1.4, color: _slate)),
            ],
          ),
        ),
      ],
    );
  }
}
