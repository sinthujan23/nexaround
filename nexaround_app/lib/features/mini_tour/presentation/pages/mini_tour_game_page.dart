import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';

/// A gamified "Mini Tour": real nearby places are dropped onto a Mapbox map as
/// flags 🚩 with a checkered finish flag 🏁 on the last stop. The map tracks the
/// user live; reaching a stop (or checking in) plants the flag ✅. Visiting every
/// stop finishes the tour and awards Explorer XP + Places Visited.
class MiniTourGamePage extends StatefulWidget {
  const MiniTourGamePage({super.key});

  @override
  State<MiniTourGamePage> createState() => _MiniTourGamePageState();
}

enum _Phase { loading, playing, finished, error }

class _TourStop {
  final String name;
  final double lat;
  final double lng;
  bool visited;
  _TourStop({required this.name, required this.lat, required this.lng, this.visited = false});
}

class _MiniTourGamePageState extends State<MiniTourGamePage> {
  static const double _checkInRadiusM = 50; // auto check-in distance
  static const int _maxStops = 5;
  static const int _xpPerStop = 20;

  _Phase _phase = _Phase.loading;
  String _error = '';
  String _area = 'your area';
  List<_TourStop> _stops = [];

  mapbox.MapboxMap? _map;
  mapbox.PointAnnotationManager? _markers;
  StreamSubscription<geo.Position>? _posSub;
  double? _userLat;
  double? _userLng;

  // Reward summary, shown on the finish screen.
  int _xpEarned = 0;
  bool _leveledUp = false;
  int _newLevel = 1;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  // ── Setup: location + nearby stops ───────────────────────────────────────
  Future<void> _setup() async {
    try {
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied || perm == geo.LocationPermission.deniedForever) {
        _fail('Location permission is needed to build a tour near you.');
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      _userLat = pos.latitude;
      _userLng = pos.longitude;

      try {
        final n = await GooglePlacesService.reverseGeocode(pos.latitude, pos.longitude);
        if (n.isNotEmpty && n != 'Nearby') _area = n;
      } catch (_) {}

      final places = await GooglePlacesService.fetchNearbyPlaces(
        latitude: pos.latitude,
        longitude: pos.longitude,
        radius: 1500,
      );
      final usable = places.where((p) => p.distanceM != null).toList()
        ..sort((a, b) => a.distanceM!.compareTo(b.distanceM!));

      if (usable.length < 3) {
        _fail('Not enough places nearby to build a tour. Try again from a busier spot.');
        return;
      }

      _stops = usable
          .take(_maxStops)
          .map((p) => _TourStop(name: p.name, lat: p.latitude, lng: p.longitude))
          .toList();

      if (!mounted) return;
      setState(() => _phase = _Phase.playing);
    } catch (e) {
      _fail('Could not start the tour: $e');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = msg;
    });
  }

  // ── Game state helpers ───────────────────────────────────────────────────
  bool get _allVisited => _stops.isNotEmpty && _stops.every((s) => s.visited);
  int get _visitedCount => _stops.where((s) => s.visited).length;
  bool _isFinal(int i) => i == _stops.length - 1;
  String _emoji(int i, _TourStop s) => s.visited ? '✅' : (_isFinal(i) ? '🏁' : '🚩');

  double? _distanceTo(_TourStop s) {
    if (_userLat == null || _userLng == null) return null;
    return _haversine(_userLat!, _userLng!, s.lat, s.lng);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Map ──────────────────────────────────────────────────────────────────
  Future<void> _onMapCreated(mapbox.MapboxMap map) async {
    _map = map;
    map.location.updateSettings(mapbox.LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
      pulsingColor: AppColors.primary.toARGB32(),
      showAccuracyRing: true,
    ));
    map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
    map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
    map.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
    map.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));

    _markers = await map.annotations.createPointAnnotationManager();
    await _refreshMarkers();
    _recenter();
    _startTracking();
  }

  void _startTracking() {
    _posSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      bool changed = false;
      for (final s in _stops) {
        if (!s.visited && _haversine(pos.latitude, pos.longitude, s.lat, s.lng) <= _checkInRadiusM) {
          s.visited = true;
          changed = true;
        }
      }
      setState(() {}); // refresh live distances in the panel
      if (changed) {
        _refreshMarkers();
        if (_allVisited) _finish();
      }
    });
  }

  Future<void> _refreshMarkers() async {
    if (_markers == null) return;
    await _markers!.deleteAll();
    final opts = <mapbox.PointAnnotationOptions>[];
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      opts.add(mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(s.lng, s.lat)),
        textField: '${_emoji(i, s)}\n${s.name}',
        textSize: 15.0,
        textOffset: [0.0, 0.0],
        textColor: Colors.white.toARGB32(),
        textHaloColor: Colors.black.toARGB32(),
        textHaloWidth: 1.6,
      ));
    }
    await _markers!.createMulti(opts);
  }

  void _recenter() {
    if (_map == null || _userLat == null || _userLng == null) return;
    _map!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(_userLng!, _userLat!)),
        zoom: 15.5,
        pitch: 0,
        bearing: 0,
      ),
      mapbox.MapAnimationOptions(duration: 1400),
    );
  }

  void _checkIn(int i) {
    if (_stops[i].visited) return;
    setState(() => _stops[i].visited = true);
    _refreshMarkers();
    if (_allVisited) _finish();
  }

  Future<void> _finish() async {
    await _posSub?.cancel();
    final xp = _stops.length * _xpPerStop;
    final leveled = await CacheService.addExploration(placesVisited: _stops.length, xp: xp);
    if (!mounted) return;
    setState(() {
      _xpEarned = xp;
      _leveledUp = leveled;
      _newLevel = CacheService.getExplorerLevel();
      _phase = _Phase.finished;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_phase) {
        _Phase.loading => _buildLoading(),
        _Phase.error => _buildError(),
        _Phase.playing => _buildGame(),
        _Phase.finished => _buildFinished(),
      },
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 20),
          Text('Scouting a tour near you…', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore_off_rounded, color: Colors.white38, size: 56),
            const SizedBox(height: 20),
            Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _phase = _Phase.loading);
                    _setup();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    return Stack(
      children: [
        mapbox.MapWidget(
          key: const ValueKey('mini_tour_map'),
          onMapCreated: _onMapCreated,
          styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
          cameraOptions: mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(_userLng ?? 0, _userLat ?? 0)),
            zoom: 15.0,
          ),
        ),
        _buildTopBar(),
        Positioned(
          right: 16,
          bottom: 250,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            backgroundColor: Colors.white,
            onPressed: _recenter,
            child: const Icon(Icons.my_location_rounded, color: Colors.black),
          ),
        ),
        _buildStopsPanel(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(100)),
              child: Row(
                children: [
                  const Text('🚩', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mini Tour · $_area',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('$_visitedCount/${_stops.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopsPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
            ).animate().fade(),
            const Text('TOUR STOPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.black54)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _buildStopRow(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopRow(int i) {
    final s = _stops[i];
    final dist = _distanceTo(s);
    final distLabel = dist == null
        ? '—'
        : (dist < 1000 ? '${dist.toInt()} m' : '${(dist / 1000).toStringAsFixed(1)} km');

    return Row(
      children: [
        Text(_emoji(i, s), style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: s.visited ? Colors.black38 : Colors.black,
                  decoration: s.visited ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                s.visited ? 'Visited' : '$distLabel away${_isFinal(i) ? ' · FINISH' : ''}',
                style: TextStyle(fontSize: 12, color: s.visited ? AppColors.neonGreen : Colors.black54, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (!s.visited)
          TextButton(
            onPressed: () => _checkIn(i),
            style: TextButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Check in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          )
        else
          const Icon(Icons.check_circle_rounded, color: AppColors.neonGreen),
      ],
    );
  }

  Widget _buildFinished() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏁', style: TextStyle(fontSize: 72)).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),
            const SizedBox(height: 16),
            const Text('Tour Complete!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))
                .animate().fade(delay: 200.ms),
            const SizedBox(height: 24),
            _rewardChip('+$_xpEarned XP', Icons.bolt_rounded),
            const SizedBox(height: 10),
            _rewardChip('+${_stops.length} Places Visited', Icons.place_rounded),
            if (_leveledUp) ...[
              const SizedBox(height: 10),
              _rewardChip('Level Up · Explorer Level $_newLevel', Icons.diamond_rounded),
            ],
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.ratingGold, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    ).animate().fade(delay: 350.ms).slideY(begin: 0.2, end: 0);
  }
}
