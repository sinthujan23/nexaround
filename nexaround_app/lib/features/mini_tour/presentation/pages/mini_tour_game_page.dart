import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/mini_tour/data/mini_tour_repository.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:url_launcher/url_launcher.dart';

/// A gamified "Mini Tour": real nearby places are dropped onto a Mapbox map as
/// flags 🚩 with a checkered finish flag 🏁 on the last stop. The map tracks the
/// user live; reaching a stop (or checking in) plants the flag ✅. Visiting every
/// stop finishes the tour and awards Explorer XP + Places Visited.
class MiniTourGamePage extends StatefulWidget {
  /// Optional tour center. When null the tour is built around the user's live
  /// GPS location; when set (e.g. picked on the map) it's built around there.
  final double? startLat;
  final double? startLng;
  final String? areaName;
  final List<AttractionEntity>? preFetchedPlaces;

  const MiniTourGamePage({
    super.key,
    this.startLat,
    this.startLng,
    this.areaName,
    this.preFetchedPlaces,
  });

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

  // Intro animation coordination: both map and stops must be ready.
  bool _mapReady = false;
  bool _stopsReady = false;
  bool _introPlayed = false;

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
    _rotationTimer?.cancel();
    super.dispose();
  }

  // ── Setup: location + nearby stops ───────────────────────────────────────
  Future<void> _setup() async {
    try {
      final bool chosen = widget.startLat != null && widget.startLng != null;
      double centerLat, centerLng;

      if (chosen) {
        // Build around the picked location. Permission is best-effort — the
        // live puck/auto-check-in only matter if the user is actually there.
        centerLat = widget.startLat!;
        centerLng = widget.startLng!;
        var perm = await geo.Geolocator.checkPermission();
        if (perm == geo.LocationPermission.denied) {
          await geo.Geolocator.requestPermission();
        }
      } else {
        var perm = await geo.Geolocator.checkPermission();
        if (perm == geo.LocationPermission.denied) {
          perm = await geo.Geolocator.requestPermission();
        }
        if (perm == geo.LocationPermission.denied ||
            perm == geo.LocationPermission.deniedForever) {
          _fail('Location permission is needed to build a tour near you.');
          return;
        }
        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
        ).timeout(const Duration(seconds: 12));
        centerLat = pos.latitude;
        centerLng = pos.longitude;
      }

      // Seed the "user" position with the tour center so the map frames the
      // area and distances render; the live GPS stream overwrites it later.
      _userLat = centerLat;
      _userLng = centerLng;

      if (widget.areaName != null && widget.areaName!.isNotEmpty) {
        _area = widget.areaName!;
      } else {
        try {
          final n = await GooglePlacesService.reverseGeocode(centerLat, centerLng);
          if (n.isNotEmpty && n != 'Nearby') _area = n;
        } catch (_) {}
      }

      // Fetch famous tourist attractions within 2–3 km if not pre-fetched.
      final List<AttractionEntity> places;
      if (widget.preFetchedPlaces != null && widget.preFetchedPlaces!.isNotEmpty) {
        places = widget.preFetchedPlaces!;
      } else {
        places = await GooglePlacesService.fetchNearbyPlaces(
          latitude: centerLat,
          longitude: centerLng,
          radius: 3000,
          categoryName: 'Attractions',
        );
      }

      // Filter out private residences and personal markers to keep only public/walkable spots
      bool isPublicSpot(AttractionEntity place) {
        final name = place.name.toLowerCase();
        final desc = (place.description ?? '').toLowerCase();
        final tags = place.tags.map((t) => t.toLowerCase()).toList();
        
        final privateKeywords = [
          'home', 'house', 'residence', "'s place", 'my place', 'my home', 
          'private', 'personal', 'apartment', 'flat', 'villa'
        ];
        
        for (final keyword in privateKeywords) {
          if (name.contains(keyword)) {
            if (name.contains('museum') || name.contains('historic') || name.contains('heritage') || name.contains('public')) {
              continue;
            }
            return false;
          }
        }
        
        if (tags.any((t) => t.contains('home') || t.contains('private') || t.contains('residential') || t.contains('personal'))) {
          return false;
        }
        
        return true;
      }

      // Filter places within 3 km and prefer those with known distance/rating.
      final usable = places
          .where((p) => p.distanceM != null && p.distanceM! <= 3000 && isPublicSpot(p))
          .toList()
        ..sort((a, b) {
          // Primary: sort by rating (highest first for famous spots)
          if (b.rating != a.rating) return b.rating.compareTo(a.rating);
          // Secondary: closer distance
          return a.distanceM!.compareTo(b.distanceM!);
        });

      if (usable.length < 3) {
        _fail('Not enough famous public spots found within 3 km. Try a different area.');
        return;
      }

      // Nearest Neighbor Route Optimization
      // Starts from the user's initial GPS location (centerLat, centerLng)
      final List<_TourStop> optimizedStops = [];
      final List<_TourStop> remaining = usable
          .take(_maxStops)
          .map((p) => _TourStop(name: p.name, lat: p.latitude, lng: p.longitude))
          .toList();

      double currentLat = centerLat;
      double currentLng = centerLng;

      while (remaining.isNotEmpty) {
        remaining.sort((a, b) =>
            _haversine(currentLat, currentLng, a.lat, a.lng)
                .compareTo(_haversine(currentLat, currentLng, b.lat, b.lng)));
        final nextStop = remaining.removeAt(0);
        optimizedStops.add(nextStop);
        currentLat = nextStop.lat;
        currentLng = nextStop.lng;
      }

      _stops = optimizedStops;

      if (!mounted) return;
      setState(() => _phase = _Phase.playing);
      _stopsReady = true;
      _maybePlayIntro();
      _startRotationTimer();
    } catch (e) {
      _fail('Could not start the tour: $e');
    }
  }

  Timer? _rotationTimer;

  void _startRotationTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (!mounted || _map == null || _stops.isEmpty || _phase != _Phase.playing) return;
      
      // Find the next unvisited stop to highlight/orient to
      final nextIndex = _stops.indexWhere((s) => !s.visited);
      if (nextIndex == -1) return;
      final target = _stops[nextIndex];

      if (_userLat == null || _userLng == null) return;

      // Gentle overview zoom out showing user and target
      final lats = [_userLat!, target.lat];
      final lngs = [_userLng!, target.lng];
      final minLat = lats.reduce(math.min);
      final maxLat = lats.reduce(math.max);
      final minLng = lngs.reduce(math.min);
      final maxLng = lngs.reduce(math.max);

      final overviewCamera = await _map!.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
          southwest: mapbox.Point(coordinates: mapbox.Position(minLng, minLat)),
          northeast: mapbox.Point(coordinates: mapbox.Position(maxLng, maxLat)),
          infiniteBounds: false,
        ),
        mapbox.MbxEdgeInsets(top: 120, left: 60, bottom: 300, right: 60),
        null,
        null,
        14.5,
        null,
      );

      if (!mounted) return;

      // 1. Zoom out dynamically
      await _map!.flyTo(
        overviewCamera,
        mapbox.MapAnimationOptions(duration: 2000),
      );

      // Hold overview briefly
      await Future.delayed(const Duration(milliseconds: 3000));
      if (!mounted) return;

      // Calculate bearing towards the destination to rotate map
      final dLon = (target.lng - _userLng!) * math.pi / 180;
      final lat1 = _userLat! * math.pi / 180;
      final lat2 = target.lat * math.pi / 180;
      final y = math.sin(dLon) * math.cos(lat2);
      final x = math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
      final brng = (math.atan2(y, x) * 180 / math.pi + 360) % 360;

      // 2. Zoom back in, oriented towards target stop
      await _map!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(_userLng!, _userLat!)),
          zoom: 16.0,
          pitch: 35.0, // slight perspective angle for engagement
          bearing: brng,
        ),
        mapbox.MapAnimationOptions(duration: 2000),
      );
    });
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
  String _emoji(int i, _TourStop s) {
    if (s.visited) return '✅';
    if (_isFinal(i)) return '🏁';
    return '${i + 1}';
  }

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
      pulsingColor: AppColors.brandGreen.toARGB32(),
      showAccuracyRing: true,
    ));
    map.compass.updateSettings(mapbox.CompassSettings(enabled: false));
    map.logo.updateSettings(mapbox.LogoSettings(enabled: false));
    map.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
    map.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));

    _markers = await map.annotations.createPointAnnotationManager();
    await _refreshMarkers();
    _startTracking();
    _updateRouteLine();
    // Mark map ready; intro animation (zoom-out → zoom-in) fires once stops
    // are also loaded. If they already are, it fires immediately.
    _mapReady = true;
    _maybePlayIntro();
  }

  /// Fires the intro animation as soon as both the map and the stops are ready.
  void _maybePlayIntro() {
    if (_mapReady && _stopsReady && !_introPlayed) {
      _introPlayed = true;
      _playIntroAnimation();
    }
  }

  /// Cinematic intro:
  ///   1. Zoom out to a bounding-box overview of all flag stops.
  ///   2. Pause so the user can see the full route.
  ///   3. Fly back down to the user's live GPS position.
  Future<void> _playIntroAnimation() async {
    if (_map == null || _stops.isEmpty || _userLat == null || _userLng == null) {
      _recenter();
      return;
    }

    // Build bounding box: user position + all stop positions.
    final lats = [_userLat!, ..._stops.map((s) => s.lat)];
    final lngs = [_userLng!, ..._stops.map((s) => s.lng)];
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    // Ask Mapbox for the exact camera that fits all points with padding.
    final overviewCamera = await _map!.cameraForCoordinateBounds(
      mapbox.CoordinateBounds(
        southwest: mapbox.Point(coordinates: mapbox.Position(minLng, minLat)),
        northeast: mapbox.Point(coordinates: mapbox.Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      // Generous padding: extra bottom for the stops panel, top for status bar.
      mapbox.MbxEdgeInsets(top: 100, left: 60, bottom: 280, right: 60),
      null, // bearing
      null, // pitch
      13.5, // max zoom so we don't zoom in past a useful overview level
      null, // offset
    );

    if (!mounted) return;

    // Step 1 – zoom OUT to show all flags.
    await _map!.flyTo(
      overviewCamera,
      mapbox.MapAnimationOptions(duration: 1800),
    );

    // Hold the overview so the user can read the flag layout.
    await Future.delayed(const Duration(milliseconds: 2200));

    if (!mounted) return;

    // Step 2 – zoom back IN to the user's position.
    await _map!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
            coordinates: mapbox.Position(_userLng!, _userLat!)),
        zoom: 15.5,
        pitch: 0,
        bearing: 0,
      ),
      mapbox.MapAnimationOptions(duration: 1600),
    );
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
      _updateRouteLine();
      setState(() {}); // refresh live distances in the panel
      if (changed) {
        _refreshMarkers();
        if (_allVisited) _finish();
      }
    });
  }

  mapbox.PolylineAnnotationManager? _polylineManager;

  Future<void> _updateRouteLine() async {
    if (_map == null || _userLat == null || _userLng == null || _stops.isEmpty) return;

    final nextIndex = _stops.indexWhere((s) => !s.visited);
    if (nextIndex == -1) {
      await _polylineManager?.deleteAll();
      return;
    }
    final activeTarget = _stops[nextIndex];

    try {
      final routeData = await GooglePlacesService.getDirections(
        originLat: _userLat!,
        originLng: _userLng!,
        destLat: activeTarget.lat,
        destLng: activeTarget.lng,
        profile: 'walking',
      );

      if (routeData == null || !mounted) return;

      final List<LatLng> polylinePoints = (routeData['polyline'] as List?)?.cast<LatLng>() ?? [];
      if (polylinePoints.isEmpty) return;

      if (_polylineManager == null) {
        _polylineManager = await _map!.annotations.createPolylineAnnotationManager();
      }

      await _polylineManager!.deleteAll();

      final List<mapbox.Position> coordinates = polylinePoints
          .map((pt) => mapbox.Position(pt.longitude, pt.latitude))
          .toList();

      await _polylineManager!.create(mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: coordinates),
        lineColor: AppColors.brandGreen.toARGB32(),
        lineWidth: 5.0,
        lineOpacity: 0.85,
      ));
    } catch (e) {
      debugPrint('Error updating navigation route line: $e');
    }
  }

  Future<void> _refreshMarkers() async {
    if (_markers == null) return;
    await _markers!.deleteAll();
    final opts = <mapbox.PointAnnotationOptions>[];
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      final icon = await _markerImage(_emoji(i, s));
      opts.add(mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(s.lng, s.lat)),
        image: icon,
        iconSize: 0.8,
        textField: s.name,
        textSize: 12.0,
        textOffset: [0.0, 1.7],
        textAnchor: mapbox.TextAnchor.TOP,
        textColor: Colors.white.toARGB32(),
        textHaloColor: Colors.black.toARGB32(),
        textHaloWidth: 1.6,
      ));
    }
    await _markers!.createMulti(opts);
  }

  /// Mapbox's label font has no color-emoji glyphs, so a 🚩/🏁/✅ set via
  /// `textField` renders blank. We instead paint the emoji into a small PNG
  /// with Flutter's text engine (which supports emoji) and attach it as the
  /// marker `image`. Cached per-emoji since there are only three.
  final Map<String, Uint8List> _iconCache = {};

  Future<Uint8List> _markerImage(String emoji) async {
    final cached = _iconCache[emoji];
    if (cached != null) return cached;

    const double size = 96;
    const double radius = 38;
    const Offset center = Offset(48, 48);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Soft drop shadow.
    canvas.drawCircle(
      const Offset(48, 51),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // White disc + colored ring (red for unvisited index numbers, brandGreen for visited/checkered flags)
    final isNumber = RegExp(r'^\d+$').hasMatch(emoji);
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = isNumber ? Colors.red : AppColors.brandGreen,
    );

    // Draw text index or emoji centered
    if (isNumber) {
      // Draw flag emoji 🚩 slightly left-offset
      final flagPainter = TextPainter(
        text: const TextSpan(
          text: '🚩',
          style: TextStyle(fontSize: 28),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      flagPainter.paint(canvas, const Offset(14, 28));

      // Draw number index slightly right-offset, bold
      final numPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.red,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numPainter.paint(canvas, const Offset(52, 32));
    } else {
      final isEmoji = emoji == '✅' || emoji == '🏁';
      final tp = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(
            fontSize: isEmoji ? 44 : 40,
            fontWeight: FontWeight.w900,
            color: isEmoji ? AppColors.brandGreen : Colors.red,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2 - (isEmoji ? 0 : 2)));
    }

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    _iconCache[emoji] = bytes;
    return bytes;
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
    final placeNames = _stops.map((s) => s.name).toList();
    // Save to the backend (syncs across devices); fall back to local storage
    // if offline so the record is never lost.
    try {
      await MiniTourRepository().saveMiniTour(
        area: _area,
        placeNames: placeNames,
        xp: xp,
      );
    } catch (_) {
      await CacheService.addMiniTourHistory(
        area: _area,
        placeNames: placeNames,
        xp: xp,
      );
    }
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
          Text('Finding famous spots near you…', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Discovering top tourist attractions within 3 km', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
    // Determine current active (unvisited) stop
    final nextIndex = _stops.indexWhere((s) => !s.visited);
    final _TourStop? activeStop = nextIndex != -1 ? _stops[nextIndex] : null;
    final double? activeDist = activeStop != null ? _distanceTo(activeStop) : null;
    final activeDistLabel = activeDist == null
        ? '—'
        : (activeDist < 1000 ? '${activeDist.toInt()} m' : '${(activeDist / 1000).toStringAsFixed(1)} km');
    final activeMinLabel = activeDist == null ? '1' : '${(activeDist / 80).round().clamp(1, 40)}';

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
        
        // Active Navigation HUD Overlay
        if (activeStop != null)
          Positioned(
            top: 124,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_walk_rounded,
                      color: AppColors.brandGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXT: ${activeStop.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppColors.brandGreen,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$activeDistLabel away · $activeMinLabel min walk',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Compass dynamic guide indicator pointing to target
                  Transform.rotate(
                    angle: () {
                      if (_userLat == null || _userLng == null) return 0.0;
                      final dLon = (activeStop.lng - _userLng!) * math.pi / 180;
                      final lat1 = _userLat! * math.pi / 180;
                      final lat2 = activeStop.lat * math.pi / 180;
                      final y = math.sin(dLon) * math.cos(lat2);
                      final x = math.cos(lat1) * math.sin(lat2) -
                          math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
                      return math.atan2(y, x);
                    }(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Colors.black12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: Colors.black54,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().slideY(begin: -0.2, end: 0).fade(),
          ),

        Positioned(
          right: 16,
          bottom: 296,
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
                      'Walk · $_area',
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
            const Text('WALK STOPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.black54)),
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
        if (!s.visited) ...[
          IconButton(
            onPressed: () async {
              final url = Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${s.lat},${s.lng}&travelmode=walking',
              );
              try {
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not launch directions map.')),
                    );
                  }
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error launching navigation.')),
                  );
                }
              }
            },
            icon: const Icon(Icons.directions_walk_rounded, color: AppColors.brandGreen, size: 20),
            tooltip: 'Navigate to stop',
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => _checkIn(i),
            style: TextButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Check in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ] else
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
            const Text('Walk Complete!', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))
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
