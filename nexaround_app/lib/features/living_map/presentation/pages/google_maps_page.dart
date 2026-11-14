import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';

class GoogleMapsPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String? destinationName;
  final bool fromSmartMap;

  const GoogleMapsPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.destinationName,
    this.fromSmartMap = false,
  });

  @override
  State<GoogleMapsPage> createState() => _GoogleMapsPageState();
}

class _GoogleMapsPageState extends State<GoogleMapsPage>
    with TickerProviderStateMixin {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  double? _userLat;
  double? _userLng;

  // Route info
  String _duration = '--';
  String _distance = '--';
  bool _routeLoaded = false;

  // Map style
  MapType _mapType = MapType.normal;

  // Travel mode for routing (Mapbox/Google profile: driving | walking)
  String _travelMode = 'driving';

  // Live navigation (Google-Maps-style follow mode)
  bool _isNavigating = false;
  bool _arrived = false;
  double _navBearing = 0;
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _walkIcon;
  bool _assetPuck = false; // true when real PNG markers are bundled
  StreamSubscription<geo.Position>? _navSub;
  StreamSubscription<CompassEvent>? _compassSub;
  double _routeDistanceM = 0;
  double _routeDurationSec = 0;
  double _remainingDistanceM = 0;
  double _remainingDurationSec = 0;

  // Current location label shown in the top bar.
  String _currentLocationName = 'Locating...';

  // A steadier map (client report 2026-11-14: "the pin is elsewhere and the
  // map keeps jumping, it doesn't stay still").
  bool _didInitialFit = false; // the route is fitted to the screen only once
  bool _followUser = true; // navigation camera follows until the user drags
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);

  // Navigation along the drawn route (client video 2026-11-14).
  List<Map<String, dynamic>> _steps = []; // Google's turn-by-turn steps
  List<double> _routeCum = []; // metres from the route start to each point
  double _routeLengthM = 0; // length of the drawn line
  double _progressM = 0; // how far along the line the user is
  LatLng? _snapped; // the user drawn on the line when within 30 m of it
  int _offRouteCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);

  // Destination
  late double _destLat;
  late double _destLng;
  String? _destName;

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounceTimer;

  // Animation
  late AnimationController _fabAnimController;
  late Animation<double> _fabAnim;

  @override
  void initState() {
    super.initState();
    _destLat = widget.initialLat;
    _destLng = widget.initialLng;
    _destName = widget.destinationName;
    _searchController = TextEditingController(text: widget.destinationName ?? '');
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fabAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.easeOutBack,
    );

    // Initialize Android Google Maps renderer for compatibility
    final GoogleMapsFlutterPlatform mapsImplementation =
        GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      try {
        mapsImplementation.useAndroidViewSurface = true;
        mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
      } catch (_) {}
    }

    _init();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _navSub?.cancel();
    _compassSub?.cancel();
    _fabAnimController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  static BitmapDescriptor? _cachedCarIcon;
  static BitmapDescriptor? _cachedWalkIcon;

  Future<void> _init() async {
    // 1. The phone's last known position, but only when it is fresh and
    //    precise. An old fix put the route start in the wrong place, and the
    //    map jumped when the real GPS position arrived a moment later.
    try {
      final lastPos = await geo.Geolocator.getLastKnownPosition();
      final DateTime? fixedAt = lastPos?.timestamp;
      if (lastPos != null &&
          mounted &&
          fixedAt != null &&
          DateTime.now().difference(fixedAt).inMinutes < 2 &&
          lastPos.accuracy <= 100) {
        setState(() {
          _userLat = lastPos.latitude;
          _userLng = lastPos.longitude;
        });
      }
    } catch (_) {}

    // Never stand in for the user with the destination or an old location:
    // without a fresh fix the route simply waits for the real GPS position
    // (_refreshHighAccuracyLocation below).
    if (_destLat != 0.0 && _destLng != 0.0) {
      _addDestinationMarker();
      if (_userLat != null && _userLng != null) _fetchRoute();
    }
    _fabAnimController.forward();

    // 2. Load icons and precision location concurrently in background
    _ensureVehicleIcons().then((_) {
      if (mounted) _addUserMarker();
    });
    _refreshHighAccuracyLocation();

    // No compass before navigation: the phone's own blue dot already shows
    // where you face, and our pin is only drawn while navigating.
  }

  Future<void> _refreshHighAccuracyLocation() async {
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      if (mounted) {
        final prevLat = _userLat ?? 0.0;
        final prevLng = _userLng ?? 0.0;
        final distMoved = _haversine(prevLat, prevLng, pos.latitude, pos.longitude);

        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
        _addUserMarker();

        if (!_isNavigating && !_routeLoaded && _destLat != 0.0 && _destLng != 0.0) {
          // First real position: draw the route and fit it once.
          _fetchRoute(fitCamera: !_didInitialFit);
        }
        // Only reverse geocode if moved > 50m to conserve API costs
        if (distMoved > 50) {
          _resolveCurrentLocationName(pos.latitude, pos.longitude);
          if (!_isNavigating && _routeLoaded && _destLat != 0.0 && _destLng != 0.0) {
            // Redraw the line from the real position, but leave the camera
            // where it is.
            _fetchRoute(fitCamera: false);
          }
        }
      }
    } catch (_) {
      // No GPS fix: keep showing the destination rather than pretending the
      // user is at an old location.
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<void> _resolveCurrentLocationName(double lat, double lng) async {
    try {
      final name = await GooglePlacesService.reverseGeocode(lat, lng);
      if (mounted && name.isNotEmpty) {
        setState(() => _currentLocationName = name.split(',').first);
      }
    } catch (_) {
      /* keep 'Locating...' */
    }
  }

  void _addUserMarker() {
    if (!_isNavigating) {
      // Before navigation the phone's own blue dot shows where you are. A
      // second pin of ours could sit on an older position ("the pin is
      // elsewhere"), so none is drawn.
      if (_markers.any((m) => m.markerId.value == 'user')) {
        setState(() => _markers.removeWhere((m) => m.markerId.value == 'user'));
      }
      return;
    }
    if (_userLat == null || _userLng == null) return;
    // Show a car (driving) or person (walking) puck that rotates to direction.
    final navIcon = _travelMode == 'walking' ? _walkIcon : _carIcon;
    final isCustom = navIcon != null;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user');
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          // On the blue line when the GPS fix is within 30 m of it.
          position: _snapped ?? LatLng(_userLat!, _userLng!),
          icon: navIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: _navBearing,
          flat: isCustom,
          anchor: isCustom
              ? (_assetPuck ? const Offset(0.5, 0.5) : const Offset(0.5, 0.61))
              : const Offset(0.5, 1.0),
          infoWindow: _isNavigating
              ? InfoWindow.noText
              : const InfoWindow(title: 'You are here'),
          zIndexInt: 2,
        ),
      );
    });
  }

  // Build (and cache statically) the car / person navigation puck.
  Future<void> _ensureVehicleIcons() async {
    if (_cachedCarIcon != null && _cachedWalkIcon != null) {
      _carIcon = _cachedCarIcon;
      _walkIcon = _cachedWalkIcon;
      return;
    }
    _assetPuck = false;
    try {
      _cachedCarIcon ??= await _renderVehicleIcon(Icons.directions_car_rounded);
      _cachedWalkIcon ??= await _renderVehicleIcon(Icons.directions_walk_rounded);
      _carIcon = _cachedCarIcon;
      _walkIcon = _cachedWalkIcon;
    } catch (e) {
      debugPrint('Error generating custom pucks: $e');
    }
  }

  // Load a bundled PNG as a marker, or null if the file hasn't been added yet.
  Future<BitmapDescriptor?> _loadMarkerAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return BitmapDescriptor.bytes(data.buffer.asUint8List(), width: 64);
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor> _renderVehicleIcon(IconData icon) async {
    const double size = 150;
    const Offset c = Offset(75, 92); // glossy disc center
    const double r = 46;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Directional pointer (rounded chevron) at the top — points up = heading.
    final pointer = Path()
      ..moveTo(75, 6)
      ..lineTo(50, 48)
      ..quadraticBezierTo(75, 40, 100, 48)
      ..close();
    canvas.drawPath(
      pointer,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(75, 6),
          const Offset(75, 48),
          const [Color(0xFF5AA0FF), Color(0xFF1A73E8)],
        ),
    );

    // Drop shadow beneath the disc (depth).
    canvas.drawCircle(
      c.translate(0, 7),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // White ring.
    canvas.drawCircle(c, r + 3, Paint()..color = Colors.white);

    // Glossy blue sphere — radial gradient: bright top-left → deep bottom.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c.translate(-r * 0.35, -r * 0.4),
          r * 1.6,
          const [Color(0xFF6AAcFF), Color(0xFF1A73E8), Color(0xFF0B57D0)],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Glossy highlight across the top of the sphere.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final hl = Rect.fromLTWH(c.dx - r * 0.75, c.dy - r, r * 1.5, r * 0.95);
    canvas.drawOval(
      hl,
      Paint()
        ..shader = ui.Gradient.linear(
          hl.topCenter,
          hl.bottomCenter,
          [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
        ),
    );
    canvas.restore();

    // Icon glyph (car / person), white, with a soft shadow for depth.
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 52,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    // Scale the 150px bitmap down to ~55 logical px on the map.
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: 2.7,
    );
  }



  void _addDestinationMarker() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'dest');
      _markers.add(
        Marker(
          markerId: const MarkerId('dest'),
          position: LatLng(_destLat, _destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: _destName ?? 'Destination',
            snippet: 'Tap to navigate',
          ),
        ),
      );
    });
  }

  Future<void> _fetchRoute({bool fitCamera = true}) async {
    if (_destLat == 0.0 || _destLng == 0.0) return;
    if (_userLat == null || _userLng == null) {
      try {
        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
          timeLimit: const Duration(seconds: 3),
        );
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      } catch (_) {}
    }
    if (_userLat == null || _userLng == null) return;

    try {
      final result = await GooglePlacesService.getDirections(
        originLat: _userLat!,
        originLng: _userLng!,
        destLat: _destLat,
        destLng: _destLng,
        profile: _travelMode,
        // From this very spot. The shared ~555 m grid could start the blue
        // line half a kilometre away, so the car never sat on it.
        exactOrigin: true,
      );

      if (result != null && mounted) {
        final points = result['polyline'] as List<LatLng>? ?? [];
        final durationSec = result['duration_seconds'] as double? ?? 0;
        final distanceM = result['distance_meters'] as double? ?? 0;

        setState(() {
          _polylines.clear();
          // Dark blue casing underneath for crisp Google Maps border
          if (_travelMode != 'walking') {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route_casing'),
                points: points,
                color: const Color(0xFF0F2B9C),
                width: 9,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            );
          }
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: const Color(0xFF1A3CD8),
              width: _travelMode == 'walking' ? 6 : 7,
              patterns: _travelMode == 'walking'
                  ? [PatternItem.dot, PatternItem.gap(10)]
                  : [],
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          _routeDurationSec = durationSec;
          _routeDistanceM = distanceM;
          _remainingDurationSec = durationSec;
          _remainingDistanceM = distanceM;
          _duration = _fmtDuration(durationSec);
          _distance = _fmtDistance(distanceM);
          _routeLoaded = true;
          _steps = ((result['steps'] as List?) ?? const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        });
        _indexRoute(points);
        if (fitCamera || !_didInitialFit) {
          _fitRouteBounds(points);
          _didInitialFit = true;
        }
      }
    } catch (e) {
      debugPrint('Google Maps route error: $e');
      // Still show the map focused on destination (once; never yank it back)
      if (!_didInitialFit) _animateCameraToDestination();
    }
  }

  String _fmtDuration(double sec) => sec < 3600
      ? '${(sec / 60).ceil()} min'
      : '${(sec / 3600).toStringAsFixed(1)} hr';
  String _fmtDistance(double m) =>
      m < 1000 ? '${m.toInt()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  // ─── Live navigation ───
  Future<void> _startNavigation() async {
    if (_userLat == null || _userLng == null || !_routeLoaded) return;
    await _ensureVehicleIcons(); // car/person puck ready before we show it
    final me = LatLng(_userLat!, _userLng!);
    _navBearing = _bearingTo(me, LatLng(_destLat, _destLng));
    _recomputeRemaining(me); // snaps to the line and sets the progress
    if (_snapped != null) _navBearing = _routeBearingAt(_progressM);
    setState(() {
      _isNavigating = true;
      _arrived = false;
      _followUser = true;
    });
    _addUserMarker(); // the car/person puck, on the line
    _updateNavCamera(force: true); // into the follow view

    // No compass while navigating: the map faces along the route, so it no
    // longer spins when the phone moves (client video: "this is on
    // navigating"). The GPS position below moves it forward.
    _compassSub?.cancel();
    _compassSub = null;

    // GPS → follow position. On the route the map faces along it; off the
    // route and moving, it faces the way we are going; three fixes more than
    // 60 m off the line ask for a new route (at most every 30 s).
    _navSub?.cancel();
    _navSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
      ),
    ).listen((pos) {
      if (!mounted || !_isNavigating) return;
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      _recomputeRemaining(LatLng(pos.latitude, pos.longitude));
      if (_snapped != null) {
        // On the route: face along it, like Google Maps.
        _navBearing = _routeBearingAt(_progressM);
      } else if (pos.speed > 2.0 && pos.heading >= 0 && !pos.heading.isNaN) {
        // Off the route but moving: face the way we are going.
        _navBearing = pos.heading;
      }
      _addUserMarker();
      _updateNavCamera();
    });
  }

  void _stopNavigation() {
    _navSub?.cancel();
    _navSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    setState(() {
      _isNavigating = false;
      _arrived = false;
    });
    _addUserMarker(); // restore the default blue pin
    if (_polylines.isNotEmpty) _fitRouteBounds(_polylines.first.points);
  }

  // Re-apply the close follow camera at the user's current position + heading.
  // Not while the user is looking around (dragged the map), and at most a
  // little over once a second so animations never pile up into a shake.
  void _updateNavCamera({bool force = false}) {
    if (_userLat == null || _userLng == null || !_followUser) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastCameraMove).inMilliseconds < 800) return;
    _lastCameraMove = now;
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        _navCameraPosition(_snapped ?? LatLng(_userLat!, _userLng!), _navBearing),
      ),
    );
  }

  // A close, tilted, heading-up camera. The target is pushed ahead of the user
  // so the puck sits low and you see the road ahead — like Google Maps nav.
  CameraPosition _navCameraPosition(LatLng user, double bearing) {
    // Zoomed out enough to see the next streets and the route ahead (the
    // old 19.5 / 20 showed a single block, so the line was mostly off screen).
    final ahead =
        _offsetAhead(user, bearing, _travelMode == 'walking' ? 50 : 150);
    return CameraPosition(
      target: ahead,
      zoom: _travelMode == 'walking' ? 18.5 : 17.5,
      tilt: 0.0,
      bearing: bearing,
    );
  }

  // Move a lat/lng `meters` along `bearingDeg`.
  LatLng _offsetAhead(LatLng from, double bearingDeg, double meters) {
    const double rad = 3.141592653589793 / 180;
    const double earth = 6378137.0;
    final br = bearingDeg * rad;
    final dLat = (meters * math.cos(br)) / earth;
    final dLng =
        (meters * math.sin(br)) / (earth * math.cos(from.latitude * rad));
    return LatLng(from.latitude + dLat / rad, from.longitude + dLng / rad);
  }

  // Remaining distance/time along the drawn route from the user's position,
  // plus where the user sits on the line (for the car puck, the camera and the
  // turn banner). Leaving the line for good asks for a new route.
  void _recomputeRemaining(LatLng user) {
    final snap = _snapToRoute(user);
    if (snap == null) return;
    final off = snap.dist;
    final remain = (_routeLengthM - snap.along).clamp(0.0, double.infinity) +
        (off > 30 ? off : 0.0);
    final speed = (_routeDurationSec > 0 && _routeDistanceM > 0)
        ? _routeDistanceM / _routeDurationSec
        : (_travelMode == 'walking' ? 1.4 : 11.0); // m/s fallback
    setState(() {
      _progressM = snap.along;
      _snapped = off <= 30 ? snap.point : null;
      _remainingDistanceM = remain;
      _remainingDurationSec = remain / (speed <= 0 ? 1 : speed);
      _arrived = remain < 25;
    });
    _offRouteCount = off > 60 ? _offRouteCount + 1 : 0;
    final now = DateTime.now();
    if (_isNavigating &&
        _offRouteCount >= 3 &&
        now.difference(_lastReroute).inSeconds >= 30) {
      _lastReroute = now;
      _offRouteCount = 0;
      _fetchRoute(fitCamera: false); // a new line from here, camera untouched
    }
  }

  // Metres from the start of [pts] to each point, for projecting onto it.
  void _indexRoute(List<LatLng> pts) {
    final cum = <double>[0];
    for (int i = 0; i < pts.length - 1; i++) {
      cum.add(cum.last +
          geo.Geolocator.distanceBetween(pts[i].latitude, pts[i].longitude,
              pts[i + 1].latitude, pts[i + 1].longitude));
    }
    _routeCum = cum;
    _routeLengthM = cum.isEmpty ? 0 : cum.last;
  }

  List<LatLng> get _routePoints =>
      _polylines.isEmpty ? const <LatLng>[] : _polylines.first.points;

  // The closest point on the drawn line to [p]: where it is, how far away,
  // and how far along the line.
  ({LatLng point, double dist, double along})? _snapToRoute(LatLng p) {
    final pts = _routePoints;
    if (pts.length < 2) return null;
    if (_routeCum.length != pts.length) _indexRoute(pts);
    const double r = 6371000.0;
    final cosLat = math.cos(p.latitude * math.pi / 180);
    double xOf(LatLng q) => q.longitude * math.pi / 180 * r * cosLat;
    double yOf(LatLng q) => q.latitude * math.pi / 180 * r;
    final px = xOf(p), py = yOf(p);
    double bestD = double.infinity, bestAlong = 0;
    LatLng bestPt = pts.first;
    for (int i = 0; i < pts.length - 1; i++) {
      final ax = xOf(pts[i]), ay = yOf(pts[i]);
      final bx = xOf(pts[i + 1]), by = yOf(pts[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      double t = len2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final qx = ax + t * dx, qy = ay + t * dy;
      final d = math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
      if (d < bestD) {
        bestD = d;
        bestAlong = _routeCum[i] + t * (_routeCum[i + 1] - _routeCum[i]);
        bestPt = LatLng(
          pts[i].latitude + t * (pts[i + 1].latitude - pts[i].latitude),
          pts[i].longitude + t * (pts[i + 1].longitude - pts[i].longitude),
        );
      }
    }
    return (point: bestPt, dist: bestD, along: bestAlong);
  }

  // The point [along] metres from the start of the drawn line.
  LatLng _pointAlong(double along) {
    final pts = _routePoints;
    if (pts.isEmpty) return LatLng(_destLat, _destLng);
    if (_routeCum.length != pts.length) _indexRoute(pts);
    if (along <= 0) return pts.first;
    for (int i = 0; i < pts.length - 1; i++) {
      if (_routeCum[i + 1] >= along) {
        final seg = _routeCum[i + 1] - _routeCum[i];
        final t = seg <= 0 ? 0.0 : (along - _routeCum[i]) / seg;
        return LatLng(
          pts[i].latitude + t * (pts[i + 1].latitude - pts[i].latitude),
          pts[i].longitude + t * (pts[i + 1].longitude - pts[i].longitude),
        );
      }
    }
    return pts.last;
  }

  // Which way the route goes from [along]: towards a point 40 m further on.
  double _routeBearingAt(double along) {
    final a = _pointAlong(along);
    final b = _pointAlong(math.min(along + 40, _routeLengthM));
    final d = geo.Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    return d < 3 ? _navBearing : _bearingTo(a, b);
  }

  // The next instruction from Google's steps, and how far until it. Steps are
  // measured along the road; the drawn line is a little simplified, so the
  // user's progress is scaled onto the steps' total.
  ({String text, String maneuver, double inM})? _nextTurn() {
    if (_steps.isEmpty || _routeLengthM <= 0) return null;
    double stepM(Map<String, dynamic> st) => (st['distance_m'] as num?)?.toDouble() ?? 0.0;
    final legTotal = _steps.fold<double>(0, (a, st) => a + stepM(st));
    if (legTotal <= 0) return null;
    final at = (_progressM / _routeLengthM).clamp(0.0, 1.0) * legTotal;
    final arrive = 'Arrive at ${_destName ?? 'your destination'}';
    double cum = 0;
    for (int i = 0; i < _steps.length; i++) {
      cum += stepM(_steps[i]);
      if (cum > at) {
        if (i + 1 < _steps.length) {
          final next = _steps[i + 1];
          final text = (next['instruction'] ?? '').toString();
          return (
            text: text.isEmpty ? 'Continue' : text,
            maneuver: (next['maneuver'] ?? '').toString(),
            inM: cum - at,
          );
        }
        return (text: arrive, maneuver: 'arrive', inM: legTotal - at);
      }
    }
    return (text: arrive, maneuver: 'arrive', inM: 0);
  }

  IconData _maneuverIcon(String m) {
    switch (m) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-slight-left':
      case 'keep-left':
        return Icons.turn_slight_left;
      case 'turn-slight-right':
      case 'keep-right':
        return Icons.turn_slight_right;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
        return Icons.u_turn_left;
      case 'uturn-right':
        return Icons.u_turn_right;
      case 'roundabout-left':
        return Icons.roundabout_left;
      case 'roundabout-right':
        return Icons.roundabout_right;
      case 'fork-left':
        return Icons.fork_left;
      case 'fork-right':
        return Icons.fork_right;
      case 'ramp-left':
        return Icons.ramp_left;
      case 'ramp-right':
        return Icons.ramp_right;
      case 'merge':
        return Icons.merge;
      case 'arrive':
        return Icons.place_rounded;
      default:
        return _travelMode == 'walking' ? Icons.directions_walk_rounded : Icons.straight;
    }
  }

  // "200 m" / "1.2 km", rounded the way a driver reads it.
  String _fmtTurnDistance(double m) {
    if (m < 1000) return '${((m / 10).round() * 10).clamp(10, 990)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  double _bearingTo(LatLng a, LatLng b) {
    final lat1 = a.latitude * 3.141592653589793 / 180;
    final lat2 = b.latitude * 3.141592653589793 / 180;
    final dLon = (b.longitude - a.longitude) * 3.141592653589793 / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / 3.141592653589793;
    return (brng + 360) % 360;
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (_controller == null || points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  void _animateCameraToDestination() {
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_destLat, _destLng),
          zoom: 15.5,
          tilt: 0,
        ),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    if (_destLat != 0.0 && _destLng != 0.0) {
      if (!_routeLoaded) {
        _animateCameraToDestination();
      }
    } else if (_userLat != null && _userLng != null) {
      _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_userLat!, _userLng!),
            zoom: 15.0,
          ),
        ),
      );
    }
  }

  void _setTravelMode(String mode) {
    if (_travelMode == mode) return;
    setState(() {
      _travelMode = mode;
      _routeLoaded = false;
      _polylines.clear();
    });
    _fetchRoute();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: Stack(
        children: [
          // ── Google Map ──
          // Dragging the map while navigating stops the follow camera until
          // the user taps Re-centre.
          Listener(
            onPointerMove: (_) {
              if (_isNavigating && _followUser) setState(() => _followUser = false);
            },
            child: GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: LatLng(
                (widget.initialLat != 0.0) ? widget.initialLat : (_userLat ?? 20.0),
                (widget.initialLng != 0.0) ? widget.initialLng : (_userLng ?? 0.0),
              ),
              // Street level once we know where to look; a world view when we
              // genuinely do not, instead of a confident wrong city.
              zoom: (widget.initialLat != 0.0 || _userLat != null) ? 14.0 : 1.5,
              tilt: 0.0,
            ),
            markers: _markers,
            polylines: _polylines,
            mapType: _mapType,
            // Hide the native blue dot during navigation — the car/person puck
            // replaces it; keep it otherwise.
            myLocationEnabled: !_isNavigating,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: false,
            tiltGesturesEnabled: false,
            trafficEnabled: false,
            padding: EdgeInsets.only(
              top: topPad + 80,
              bottom: _isNavigating ? 170 : (_routeLoaded ? 220 : 0),
            ),
          ),
          ),

          // ── Top Bar (search) — replaced by the nav banner while navigating ──
          if (!_isNavigating)
            Positioned(
              top: topPad + 16,
              left: 16,
              right: 16,
              child: _buildTopBar(),
            )
          else
            Positioned(
              top: topPad + 16,
              left: 16,
              right: 16,
              child: _buildNavBanner(),
            ),

          // ── Bottom card: route preview OR live-navigation bar ──
          if (!_searchFocusNode.hasFocus) ...[
            if (_isNavigating)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildNavBottomBar(bottomPad),
              )
            else if (_routeLoaded)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildRouteCard(bottomPad),
              ),
          ],

          // ── Re-centre (navigation, after the user dragged the map) ──
          if (_isNavigating && !_followUser && !_searchFocusNode.hasFocus)
            Positioned(
              left: 16,
              bottom: 190 + bottomPad,
              child: GestureDetector(
                onTap: () {
                  setState(() => _followUser = true);
                  _updateNavCamera(force: true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation_rounded, size: 18, color: Color(0xFF1A3CD8)),
                      SizedBox(width: 8),
                      Text(
                        'Re-centre',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A3CD8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Right FAB Stack ──
          if (!_searchFocusNode.hasFocus)
            Positioned(
              right: 16,
              bottom: (_isNavigating ? 250 : (_routeLoaded ? 300 : 90)) + bottomPad,
              child: ScaleTransition(
                scale: _fabAnim,
                child: _buildFabStack(),
              ),
            ),
        ],
      ),
    );
  }

  // Top banner shown during live navigation (next-step style).
  Widget _buildNavBanner() {
    final turn = _arrived ? null : _nextTurn();
    final icon = _arrived
        ? Icons.place_rounded
        : (turn != null
            ? _maneuverIcon(turn.maneuver)
            : (_travelMode == 'walking' ? Icons.directions_walk_rounded : Icons.straight_rounded));
    final top = _arrived
        ? 'Arriving'
        : (turn != null ? 'In ${_fmtTurnDistance(turn.inM)}' : 'Head to');
    final main = _arrived ? (_destName ?? 'Destination') : (turn?.text ?? (_destName ?? 'Destination'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3CD8),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A3CD8).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  top,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  main,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                  maxLines: 3,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Bottom bar shown during live navigation: ETA + remaining + Exit.
  Widget _buildNavBottomBar(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPad + 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _arrived ? 'Arrived' : _fmtDuration(_remainingDurationSec),
                  style: TextStyle(
                    color: _arrived
                        ? const Color(0xFF1E8E3E)
                        : const Color(0xFF202124),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _arrived
                      ? "You've reached ${_destName ?? 'your destination'}"
                      : '${_fmtDistance(_remainingDistanceM)} • ${_travelMode == 'walking' ? 'Walking' : 'Driving'}',
                  style: const TextStyle(
                    color: Color(0xFF5F6368),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _stopNavigation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: _arrived ? const Color(0xFF1E8E3E) : const Color(0xFFEA4335),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_arrived ? Icons.check_rounded : Icons.close_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _arrived ? 'Done' : 'Exit',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _clearDestinationAndRoute() {
    setState(() {
      _destName = '';
      _routeLoaded = false;
      _polylines.clear();
      _destLat = _userLat ?? widget.initialLat;
      _destLng = _userLng ?? widget.initialLng;
      _markers.removeWhere((m) => m.markerId.value == 'dest');
    });
  }

  Future<void> _onSearchSubmitted(String query) async {
    _searchFocusNode.unfocus();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _clearDestinationAndRoute();
      return;
    }
    // If suggestions are already loaded, let the user tap their preferred one
    if (_suggestions.isNotEmpty) return;

    try {
      final results = await GooglePlacesService.searchPlaces(
        query: trimmed,
        latitude: _userLat ?? _destLat,
        longitude: _userLng ?? _destLng,
      );
      if (results.isNotEmpty) {
        if (mounted) {
          setState(() {
            _suggestions = results.map((place) => {
              'place_id': place.id,
              'main_text': place.name,
              'description': place.address ?? place.categoryName ?? '',
              'latitude': place.latitude,
              'longitude': place.longitude,
            }).toList();
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No places found for "$trimmed"'),
              backgroundColor: Colors.black87,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Google Maps Search error: $e');
    }
  }

  void _onSearchTextChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Debounce: 200ms for fast Google Maps-like typing response
    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final results = await GooglePlacesService.getAutocompleteSuggestions(
          input: text.trim(),
          latitude: _userLat ?? _destLat,
          longitude: _userLng ?? _destLng,
        );
        if (mounted) {
          setState(() => _suggestions = results);
        }
      } catch (e) {
        debugPrint('Autocomplete error: $e');
      }
    });
  }

  Future<void> _onSuggestionTapped(Map<String, dynamic> suggestion) async {
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = [];
      _routeLoaded = false;
    });

    final placeId = suggestion['place_id'] as String?;
    double? lat = (suggestion['latitude'] as num?)?.toDouble();
    double? lng = (suggestion['longitude'] as num?)?.toDouble();
    String name = suggestion['main_text'] ?? suggestion['description'] ?? 'Destination';

    if ((lat == null || lng == null || lat == 0.0 || lng == 0.0) && placeId != null && placeId.isNotEmpty) {
      final placeDetails = await GooglePlacesService.getPlaceDetails(placeId);
      if (placeDetails != null && placeDetails.latitude != 0.0 && placeDetails.longitude != 0.0) {
        lat = placeDetails.latitude;
        lng = placeDetails.longitude;
        name = placeDetails.name;
      }
    }

    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      setState(() {
        _destLat = lat!;
        _destLng = lng!;
        _destName = name;
        _searchController.text = name;
      });
      _addDestinationMarker();
      _animateCameraToDestination();
      await _fetchRoute();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not locate coordinates for "$name"'),
            backgroundColor: Colors.black87,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _switchToSmartMap() {
    if (widget.fromSmartMap && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    final double targetLat = (_destLat != 0.0) ? _destLat : (_userLat ?? widget.initialLat);
    final double targetLng = (_destLng != 0.0) ? _destLng : (_userLng ?? widget.initialLng);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SmartTourismMapPage(
          initialLat: targetLat,
          initialLng: targetLng,
          destinationName: _destName,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0x14000000)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Color(0xFF202124), size: 20),
          ),
        ),
        const SizedBox(width: 10),
        // Search bar
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: const Color(0x14000000)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: Color(0xFF4285F4), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearchTextChanged,
                        style: const TextStyle(
                          color: Color(0xFF202124),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search location...',
                          hintStyle: TextStyle(
                            color: const Color(0xFF202124).withValues(alpha: 0.4),
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSearchSubmitted,
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, child) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _suggestions = []);
                            _clearDestinationAndRoute();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFF5F6368),
                              size: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x14000000), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final item = _suggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on_rounded, color: Color(0xFFEA4335), size: 16),
                        title: Text(
                          item['main_text'] ?? '',
                          style: const TextStyle(color: Color(0xFF202124), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          (item['secondary_text'] != null && (item['secondary_text'] as String).isNotEmpty)
                              ? item['secondary_text']!
                              : (item['description'] ?? ''),
                          style: const TextStyle(color: Color(0xFF5F6368), fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _onSuggestionTapped(item),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // ── Clearly-labelled "Smart Map" switch ──
        GestureDetector(
          onTap: _switchToSmartMap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Smart',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildRouteCard(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad + 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Destination info
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEA4335).withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.place_rounded,
                    color: Color(0xFFEA4335), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _destName ?? 'Destination',
                      style: const TextStyle(
                        color: Color(0xFF202124),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 13, color: Color(0xFF1A3CD8)),
                        const SizedBox(width: 4),
                        Text(
                          _duration,
                          style: const TextStyle(
                              color: Color(0xFF1A3CD8),
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.straighten_rounded,
                            size: 13, color: Color(0xFF5F6368)),
                        const SizedBox(width: 4),
                        Text(
                          _distance,
                          style: const TextStyle(
                              color: Color(0xFF5F6368),
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Satellite / normal map type toggle
              GestureDetector(
                onTap: () {
                  setState(() {
                    _mapType = _mapType == MapType.normal
                        ? MapType.hybrid
                        : MapType.normal;
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF1F3F4),
                  ),
                  child: Icon(
                    _mapType == MapType.normal
                        ? Icons.satellite_alt_rounded
                        : Icons.map_rounded,
                    color: const Color(0xFF5F6368),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Driving / Walking segmented toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildModeTab('driving', Icons.directions_car_rounded, 'Driving'),
                _buildModeTab('walking', Icons.directions_walk_rounded, 'Walking'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Navigate button
          GestureDetector(
            onTap: _startNavigation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3CD8), Color(0xFF1531B8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A3CD8).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Start Navigation',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // One tab of the Driving/Walking segmented control.
  Widget _buildModeTab(String mode, IconData icon, String label) {
    final selected = _travelMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setTravelMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1A3CD8) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFF5F6368)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF5F6368),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFabStack() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // My location
        _buildFab(
          icon: Icons.my_location_rounded,
          color: const Color(0xFF4285F4),
          onTap: () {
            if (_isNavigating) {
              setState(() => _followUser = true);
              _updateNavCamera(force: true);
              return;
            }
            if (_userLat != null && _userLng != null) {
              _controller?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(_userLat!, _userLng!),
                    zoom: 17,
                    tilt: 0,
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        // Fit route
        if (_routeLoaded)
          _buildFab(
            icon: Icons.route_rounded,
            color: Colors.black.withValues(alpha: 0.8),
            onTap: () {
              if (_polylines.isNotEmpty) {
                _fitRouteBounds(
                    _polylines.first.points);
              }
            },
          ),
      ],
    );
  }

  Widget _buildFab({
    IconData? icon,
    String? imagePath,
    required Color color,
    required VoidCallback onTap,
    bool fillImage = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: imagePath != null
              ? (fillImage
                  ? Image.asset(imagePath, fit: BoxFit.cover, width: 48, height: 48)
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(imagePath, fit: BoxFit.contain),
                    ))
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
