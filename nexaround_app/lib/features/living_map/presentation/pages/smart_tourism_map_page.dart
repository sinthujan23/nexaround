import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/google_maps_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class SmartTourismMapPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String? destinationName;
  final String? initialCategory;

  const SmartTourismMapPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.destinationName,
    this.initialCategory,
  });

  @override
  State<SmartTourismMapPage> createState() => _SmartTourismMapPageState();
}

class _SmartTourismMapPageState extends State<SmartTourismMapPage>
    with TickerProviderStateMixin {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;
  StreamSubscription<CompassEvent>? _compassSub;
  double _navBearing = 0;

  double? _userLat;
  double? _userLng;
  double _destLat = 0;
  double _destLng = 0;

  List<AttractionModel> _places = [];
  bool _isLoading = true;
  bool _routeLoaded = false;
  String _selectedCategory = 'All';

  // Navigation info
  String _duration = '--';
  String _distance = '--';
  List<List<double>> _routeCoordinates = [];
  bool _isActivelyNavigating = false;
  List<String> _navigationSteps = [];
  int _currentStepIndex = 0;
  String _navigationProfile = 'driving';

  // Map style
  int _styleIndex = 0;
  static const _styles = [
    mapbox.MapboxStyles.DARK,
    mapbox.MapboxStyles.SATELLITE_STREETS,
    mapbox.MapboxStyles.STANDARD,
  ];
  static const _styleIcons = [Icons.dark_mode, Icons.satellite_alt, Icons.map];

  // Proximity alert
  String? _proximityAlert;
  String _currentNeighborhood = 'Locating...';
  int? _selectedCardIndex;
  bool _isAutoTouring = false;
  final ScrollController _cardScrollController = ScrollController();

  // Destination can be overridden (e.g. when navigating to a tapped place).
  String? _destinationNameOverride;

  String? get _destinationName {
    if (_destinationNameOverride == '') return null;
    return _destinationNameOverride ?? widget.destinationName;
  }

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounceTimer;

  // Animation
  late AnimationController _pulseController;
  late AnimationController _alertController;
  late Animation<double> _alertAnimation;

  final List<String> _categories = [
    'All',
    'Attractions',
    'Food & Drink',
    'Hotels',
    'Shopping',
  ];

  @override
  void initState() {
    super.initState();
    _destLat = widget.initialLat;
    _destLng = widget.initialLng;
    _searchController = TextEditingController(text: widget.destinationName ?? '');
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
      if (!_categories.contains(_selectedCategory) && _selectedCategory != 'Transport') {
        _categories.add(_selectedCategory);
      }
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _alertController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _alertAnimation = CurvedAnimation(
      parent: _alertController,
      curve: Curves.easeOutBack,
    );

    _getUserLocationThenInit();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _compassSub?.cancel();
    _pulseController.dispose();
    _alertController.dispose();
    _cardScrollController.dispose();
    super.dispose();
  }

  // ─── Step 1: Get user GPS, then fetch places & route ───
  Future<void> _getUserLocationThenInit() async {
    try {
      // Check location permission first (critical for iOS)
      final permissionGranted = await Permission.locationWhenInUse.status;
      if (!permissionGranted.isGranted && !permissionGranted.isLimited) {
        final result = await Permission.locationWhenInUse.request();
        if (!result.isGranted && !result.isLimited) {
          debugPrint('📍 Location permission not granted for map');
          // Fall through to fallback below
          throw Exception('Location permission denied');
        }
      }

      final pos = await geo.Geolocator.getCurrentPosition();
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });
      // Fetch neighborhood name
      final name = await GooglePlacesService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _currentNeighborhood = name.split(',')[0]);
      }
    } catch (_) {
      // Fallback to Colombo
      setState(() {
        _userLat = 6.9271;
        _userLng = 79.8612;
        _currentNeighborhood = 'Colombo';
      });
    }

    if (_destinationName == null) {
      _fetchPlaces();
    } else {
      setState(() => _isLoading = false);
    }
    _fetchRoute();
  }

  // ─── Fetch nearby places ───
  Future<void> _fetchPlaces() async {
    setState(() => _isLoading = true);
    try {
      final ds = AttractionRemoteDatasource();
      final catId = _selectedCategory == 'All'
          ? null
          : _categories.indexOf(_selectedCategory).toString();
      final places = await ds.getNearbyAttractions(
        latitude: _userLat ?? _destLat,
        longitude: _userLng ?? _destLng,
        categoryName: _selectedCategory == 'All' ? null : _selectedCategory,
        radius: 5000,
      );
      if (mounted) {
        setState(() {
          _places = places;
          _isLoading = false;
        });
        _addMarkers();
      }
    } catch (e) {
      debugPrint('Fetch places error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // ─── Fetch driving route from Mapbox Directions API via backend proxy ───
  Future<void> _fetchRoute() async {
    if (_userLat == null || _userLng == null) return;
    try {
      // Google Directions (via the secure proxy) so the distance/route matches
      // Google Maps instead of Mapbox's longer, less-accurate local routing.
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/directions/json',
        queryParameters: {
          'origin': '$_userLat,$_userLng',
          'destination': '$_destLat,$_destLng',
          'mode': _navigationProfile, // driving | walking | bicycling | transit
        },
      );
      final data = response.data;

      if (data != null &&
          data['routes'] != null &&
          (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0] as Map;
        final legsList = route['legs'] as List?;
        if (legsList == null || legsList.isEmpty) return;
        final leg = legsList[0] as Map;

        final durationSec =
            ((leg['duration'] as Map?)?['value'] as num?)?.toDouble() ?? 0.0;
        final distanceM =
            ((leg['distance'] as Map?)?['value'] as num?)?.toDouble() ?? 0.0;

        final encoded = (route['overview_polyline'] as Map?)?['points'] as String?;
        final coords = (encoded != null && encoded.isNotEmpty)
            ? _decodePolylineLngLat(encoded)
            : <List<double>>[];

        final List<String> parsedSteps = [];
        final stepsRaw = leg['steps'] as List?;
        if (stepsRaw != null) {
          for (final step in stepsRaw) {
            final html = (step as Map)['html_instructions'] as String?;
            if (html != null && html.isNotEmpty) {
              parsedSteps.add(_stripHtml(html));
            }
          }
        }

        if (mounted) {
          setState(() {
            _duration = durationSec < 3600
                ? '${(durationSec / 60).ceil()} min'
                : '${(durationSec / 3600).toStringAsFixed(1)} hr';
            _distance = distanceM < 1000
                ? '${distanceM.toInt()} m'
                : '${(distanceM / 1000).toStringAsFixed(1)} km';
            _routeCoordinates = coords;
            _navigationSteps = parsedSteps;
            _currentStepIndex = 0;
            _routeLoaded = true;
          });
          _drawRoute();
          _addMarkers();
        }
      }
    } catch (e) {
      debugPrint('Route fetch error: $e');
    }
  }

  /// Decodes a Google "encoded polyline" into [lng, lat] pairs (GeoJSON order)
  /// for drawing on the Mapbox map.
  List<List<double>> _decodePolylineLngLat(String encoded) {
    final coords = <List<double>>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      coords.add([lng / 1e5, lat / 1e5]);
    }
    return coords;
  }

  /// Strips HTML tags from Google's turn-by-turn instructions.
  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _disableOrnaments() {
    final map = _mapboxMap;
    if (map == null) return;
    map.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    map.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    map.attribution.updateSettings(
      mapbox.AttributionSettings(enabled: false),
    );
    map.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(enabled: false),
    );
  }

  // ─── Map Created ───
  void _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;

    // Enable the user‑location puck (blue dot) only if permission is granted to avoid native crashes
    final permissionGranted = await Permission.locationWhenInUse.isGranted || await Permission.locationWhenInUse.isLimited;
    map.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: permissionGranted,
        pulsingEnabled: permissionGranted,
        pulsingColor: AppColors.primary.toARGB32(),
        showAccuracyRing: permissionGranted,
      ),
    );

    // Hide default Mapbox ornaments for a clean, custom UI
    _disableOrnaments();

    // Wait for style to fully load before adding layers
    await Future.delayed(const Duration(milliseconds: 800));
    _disableOrnaments(); // Ensure ornaments remain hidden after style loading

    // Add 3D building extrusion layer
    await _add3DBuildingLayer();

    // Animate camera to show both origin & destination
    _fitRouteBounds();

    // Setup markers
    _annotationManager =
        await map.annotations.createPointAnnotationManager();

    _addMarkers();

    // If route was already fetched, draw it
    if (_routeLoaded) {
      _drawRoute();
    }

    // Start location streaming for live tracking
    geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
        _checkProximity();
        if (_isActivelyNavigating) {
          _flyToUserWithBearing();
        }
      }
    });
  }

  // ─── 3D Building Extrusions ───
  Future<void> _add3DBuildingLayer() async {
    if (_mapboxMap == null) return;

    try {
      // Check if there's an existing building layer we can modify
      final exists = await _mapboxMap!.style.styleLayerExists('building');
      
      if (exists) {
        // The "building" layer is a flat fill in the standard dark style.
        // We add a fill-extrusion layer on top of the same source for 3D.
        final alreadyHas3D =
            await _mapboxMap!.style.styleLayerExists('3d-buildings-extrusion');
        if (!alreadyHas3D) {
          await _mapboxMap!.style.addStyleLayer(
            jsonEncode({
              'id': '3d-buildings-extrusion',
              'type': 'fill-extrusion',
              'source': 'composite',
              'source-layer': 'building',
              'minzoom': 14,
              'paint': {
                'fill-extrusion-color': '#1a1a2e',
                'fill-extrusion-height': [
                  'interpolate',
                  ['linear'],
                  ['zoom'],
                  14, 0,
                  14.5, ['get', 'height'],
                ],
                'fill-extrusion-base': [
                  'interpolate',
                  ['linear'],
                  ['zoom'],
                  14, 0,
                  14.5, ['get', 'min_height'],
                ],
                'fill-extrusion-opacity': 0.85,
                'fill-extrusion-vertical-gradient': true,
              },
              'filter': ['==', 'extrude', 'true'],
            }),
            mapbox.LayerPosition(above: 'building'),
          );
        }
      }
    } catch (e) {
      debugPrint('3D building layer error: $e');
      // Some styles don't have "building" source-layer — that's okay
    }
  }

  // ─── Draw Route Polyline ───
  Future<void> _drawRoute() async {
    if (_mapboxMap == null || _routeCoordinates.isEmpty) return;

    try {
      // Remove existing route layer/source if present
      final layerExists =
          await _mapboxMap!.style.styleLayerExists('route-line');
      if (layerExists) {
        await _mapboxMap!.style.removeStyleLayer('route-line');
      }
      final glowExists =
          await _mapboxMap!.style.styleLayerExists('route-glow');
      if (glowExists) {
        await _mapboxMap!.style.removeStyleLayer('route-glow');
      }
      final srcExists =
          await _mapboxMap!.style.styleSourceExists('route-source');
      if (srcExists) {
        await _mapboxMap!.style.removeStyleSource('route-source');
      }

      // Build GeoJSON
      final geojson = {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': _routeCoordinates,
        },
      };

      // Add source
      await _mapboxMap!.style.addStyleSource(
        'route-source',
        jsonEncode({
          'type': 'geojson',
          'data': geojson,
        }),
      );

      // Add glow (wider, transparent) layer underneath
      final Map<String, dynamic> glowPaint = {
        'line-color': '#00E5FF',
        'line-width': 12,
        'line-opacity': 0.25,
        'line-blur': 8,
      };
      if (_navigationProfile == 'walking') {
        glowPaint['line-dasharray'] = [0.01, 2.0];
      }

      await _mapboxMap!.style.addStyleLayer(
        jsonEncode({
          'id': 'route-glow',
          'type': 'line',
          'source': 'route-source',
          'paint': glowPaint,
          'layout': {
            'line-cap': 'round',
            'line-join': 'round',
          },
        }),
        null,
      );

      // Add main route line
      final Map<String, dynamic> linePaint = {
        'line-color': '#00E5FF',
        'line-width': 5,
        'line-opacity': 0.9,
      };
      if (_navigationProfile == 'walking') {
        linePaint['line-dasharray'] = [0.01, 2.0];
      }

      await _mapboxMap!.style.addStyleLayer(
        jsonEncode({
          'id': 'route-line',
          'type': 'line',
          'source': 'route-source',
          'paint': linePaint,
          'layout': {
            'line-cap': 'round',
            'line-join': 'round',
          },
        }),
        null,
      );
    } catch (e) {
      debugPrint('Draw route error: $e');
    }
  }

  // ─── Fit camera to show full route ───
  void _fitRouteBounds() {
    if (_mapboxMap == null || _userLat == null) return;

    final minLat = math.min(_userLat!, _destLat);
    final maxLat = math.max(_userLat!, _destLat);
    final minLng = math.min(_userLng!, _destLng);
    final maxLng = math.max(_userLng!, _destLng);

    _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            (minLng + maxLng) / 2,
            (minLat + maxLat) / 2,
          ),
        ),
        zoom: _calculateZoom(minLat, maxLat, minLng, maxLng),
        pitch: 60.0,
        bearing: _calculateBearing(),
      ),
      mapbox.MapAnimationOptions(duration: 2500),
    );
  }

  double _calculateZoom(
      double minLat, double maxLat, double minLng, double maxLng) {
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = math.max(latDiff, lngDiff);
    if (maxDiff < 0.005) return 16.0;
    if (maxDiff < 0.01) return 15.0;
    if (maxDiff < 0.05) return 13.5;
    if (maxDiff < 0.1) return 12.0;
    if (maxDiff < 0.5) return 10.0;
    return 8.0;
  }

  double _calculateBearing() {
    if (_userLat == null || _userLng == null) return 0;
    final dLng = (_destLng - _userLng!) * math.pi / 180;
    final lat1 = _userLat! * math.pi / 180;
    final lat2 = _destLat * math.pi / 180;
    final x = math.sin(dLng) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  }

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
    // White disc + brand ring.
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.primary,
    );

    // Emoji, centered.
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 46)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    _iconCache[emoji] = bytes;
    return bytes;
  }

  // ─── Add place markers ───
  Future<void> _addMarkers() async {
    if (_annotationManager == null) return;
    await _annotationManager!.deleteAll();

    if (_destinationName != null) {
      final iconBytes = await _markerImage('🏁');
      final destAnnotation = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(_destLng, _destLat),
        ),
        image: iconBytes,
        iconSize: 0.6,
        textField: _destinationName!,
        textSize: 12.0,
        textOffset: [0.0, 2.0],
        textColor: Colors.white.toARGB32(),
        textHaloColor: Colors.black.toARGB32(),
        textHaloWidth: 1.5,
      );
      await _annotationManager!.create(destAnnotation);
      return;
    }

    if (_places.isEmpty) return;

    final annotations = _places.map((place) {
      return mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(place.longitude, place.latitude),
        ),
        textField: place.name,
        textSize: 11.0,
        textOffset: [0.0, 2.0],
        textColor: Colors.white.toARGB32(),
        textHaloColor: Colors.black.toARGB32(),
        textHaloWidth: 1.5,
        iconSize: 1.2,
      );
    }).toList();

    await _annotationManager!.createMulti(annotations);
  }

  // ─── Focus on destination with cinematic fly ───
  void _flyToDestination() {
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_destLng, _destLat),
        ),
        zoom: 17.0,
        pitch: 72.0,
        bearing: _calculateBearing(),
      ),
      mapbox.MapAnimationOptions(duration: 2000),
    );
  }

  // Follow-the-user camera used during active navigation: closer zoom + strong
  // tilt for a 3D first-person feel, rotated to the travel heading.
  void _flyToUserWithBearing() {
    if (_userLat == null || _userLng == null) return;
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_userLng!, _userLat!),
        ),
        zoom: 19.5,
        pitch: 75.0,
        bearing: _navBearing,
      ),
      mapbox.MapAnimationOptions(duration: 1500),
    );
  }

  void _updateNavCamera() {
    if (_userLat == null || _userLng == null) return;
    _mapboxMap?.easeTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_userLng!, _userLat!),
        ),
        zoom: 19.5,
        pitch: 75.0,
        bearing: _navBearing,
      ),
      mapbox.MapAnimationOptions(duration: 300), // smooth easing
    );
  }

  // ─── Recenter button: just show where I am (north-up overview) ───
  // Deliberately different from Navigate so the two buttons aren't redundant.
  void _recenterOnUser() {
    if (_userLat == null || _userLng == null) return;
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_userLng!, _userLat!),
        ),
        zoom: 16.0,
        pitch: 35.0,
        bearing: 0,
      ),
      mapbox.MapAnimationOptions(duration: 1200),
    );
  }

  // ─── Navigate button: enter 3D follow mode ───
  // Turns the location dot into a car (Driving) or person (Walking) and follows
  // the user in 3D. The position stream keeps re-centering while navigating.
  Future<void> _enterFollowNavigation() async {
    if (_userLat == null || _userLng == null) return;
    setState(() => _isActivelyNavigating = true);
    await _applyVehiclePuck();
    _flyToUserWithBearing();

    // Start compass listener to rotate the map
    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null || !mounted || !_isActivelyNavigating) return;
      double d = (h - _navBearing).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d < 3) return; // ignore tiny jitters to avoid camera spam
      _navBearing = h;
      _updateNavCamera();
    });
  }

  Future<void> _exitFollowNavigation() async {
    _compassSub?.cancel();
    _compassSub = null;
    setState(() => _isActivelyNavigating = false);
    await _applyDefaultPuck();
  }

  // Swap the map's location puck for a car/person icon based on travel mode.
  Future<void> _applyVehiclePuck() async {
    if (_mapboxMap == null) return;
    try {
      final icon = _navigationProfile == 'walking'
          ? Icons.directions_walk_rounded
          : Icons.directions_car_rounded;
      final bytes = await _renderPuckIcon(icon);
      await _mapboxMap!.location.updateSettings(
        mapbox.LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: mapbox.PuckBearing.HEADING,
          locationPuck: mapbox.LocationPuck(
            locationPuck2D: mapbox.LocationPuck2D(topImage: bytes),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Vehicle puck failed: $e');
    }
  }

  // Restore the default pulsing blue dot.
  Future<void> _applyDefaultPuck() async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.location.updateSettings(
        mapbox.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          pulsingColor: AppColors.primary.toARGB32(),
          showAccuracyRing: true,
          puckBearingEnabled: false,
          locationPuck: mapbox.LocationPuck(
            locationPuck2D: mapbox.LocationPuck2D(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Default puck failed: $e');
    }
  }

  // Render a custom 3D arrow to a PNG for use as the Mapbox location puck.
  Uint8List? _arrowPuckBytes;
  Future<Uint8List> _renderArrowPuckIcon() async {
    if (_arrowPuckBytes != null) return _arrowPuckBytes!;

    const double size = 120;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Drop shadow
    final shadowPath = Path()
      ..moveTo(60, 15)
      ..lineTo(25, 115)
      ..lineTo(60, 90)
      ..lineTo(95, 115)
      ..close();
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Left half (Lighter Teal)
    final leftPath = Path()
      ..moveTo(60, 10)
      ..lineTo(25, 110)
      ..lineTo(60, 85)
      ..close();
    canvas.drawPath(
      leftPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(60, 10),
          const Offset(25, 110),
          [const Color(0xFF00B2B4), const Color(0xFF007A7C)],
        ),
    );

    // Right half (Darker Teal)
    final rightPath = Path()
      ..moveTo(60, 10)
      ..lineTo(60, 85)
      ..lineTo(95, 110)
      ..close();
    canvas.drawPath(
      rightPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(60, 10),
          const Offset(95, 110),
          [const Color(0xFF007A7C), const Color(0xFF004C4E)],
        ),
    );

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    _arrowPuckBytes = data!.buffer.asUint8List();
    return _arrowPuckBytes!;
  }

  // Render a Material icon to a PNG for use as the Mapbox location puck.
  final Map<int, Uint8List> _puckCache = {};
  Future<Uint8List> _renderPuckIcon(IconData icon) async {
    final cached = _puckCache[icon.codePoint];
    if (cached != null) return cached;

    const double size = 120;
    const Offset center = Offset(60, 60);
    const double radius = 48;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Soft shadow.
    canvas.drawCircle(
      const Offset(60, 64),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Brand disc + white ring.
    canvas.drawCircle(center, radius, Paint()..color = AppColors.primary);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white,
    );
    // The icon glyph, centered.
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 56,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    _puckCache[icon.codePoint] = bytes;
    return bytes;
  }

  // ─── Check proximity to places ───
  void _checkProximity() {
    if (_userLat == null || _userLng == null || _places.isEmpty) return;
    for (final place in _places) {
      final dist = _haversine(_userLat!, _userLng!, place.latitude, place.longitude);
      if (dist < 200) {
        final msg = '📍 You\'re ${dist.toInt()}m from ${place.name}!';
        if (_proximityAlert != msg) {
          setState(() => _proximityAlert = msg);
          _alertController.forward(from: 0);
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _proximityAlert = null);
          });
        }
        return;
      }
    }
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

  // ─── Switch map style ───
  void _toggleMapStyle() {
    setState(() => _styleIndex = (_styleIndex + 1) % _styles.length);
    _mapboxMap?.style.setStyleURI(_styles[_styleIndex]);
    // Re-add 3D buildings and ensure ornaments remain disabled after style change
    Future.delayed(const Duration(milliseconds: 1200), () {
      _add3DBuildingLayer();
      _disableOrnaments();
      if (_routeLoaded) _drawRoute();
    });
  }

  // ─── Auto Tour - fly between places cinematically ───
  Future<void> _startAutoTour() async {
    if (_places.isEmpty || _isAutoTouring) return;
    setState(() => _isAutoTouring = true);
    for (var i = 0; i < math.min(_places.length, 5); i++) {
      if (!_isAutoTouring || !mounted) break;
      final place = _places[i];
      setState(() => _selectedCardIndex = i);
      // Scroll card into view
      if (_cardScrollController.hasClients) {
        _cardScrollController.animateTo(
          i * 220.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
      _mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(place.longitude, place.latitude),
          ),
          zoom: 17.0,
          pitch: 70.0,
          bearing: (i * 72.0) % 360,
        ),
        mapbox.MapAnimationOptions(duration: 2500),
      );
      await Future.delayed(const Duration(seconds: 4));
    }
    if (mounted) setState(() => _isAutoTouring = false);
  }

  // ─── Fly to a specific place ───
  Future<void> _flyToPlace(AttractionModel place, int index) async {
    setState(() {
      _selectedCardIndex = index;
      _destLat = place.latitude;
      _destLng = place.longitude;
      _destinationNameOverride = place.name;
      _searchController.text = place.name;
    });

    await _fetchRoute();
    _addMarkers();

    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(place.longitude, place.latitude),
        ),
        zoom: 17.0,
        pitch: 68.0,
        bearing: _bearingTo(place.latitude, place.longitude),
      ),
      mapbox.MapAnimationOptions(duration: 1800),
    );
  }

  double _bearingTo(double lat, double lng) {
    if (_userLat == null || _userLng == null) return 0;
    final dLng = (lng - _userLng!) * math.pi / 180;
    final lat1 = _userLat! * math.pi / 180;
    final lat2 = lat * math.pi / 180;
    final x = math.sin(dLng) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  }

  double _getManeuverAngle() {
    if (_navigationSteps.isEmpty || _currentStepIndex >= _navigationSteps.length) return 0.0;
    final inst = _navigationSteps[_currentStepIndex].toLowerCase();
    if (inst.contains('left')) return -math.pi / 2;
    if (inst.contains('right')) return math.pi / 2;
    if (inst.contains('turn back') || inst.contains('uturn')) return math.pi;
    return 0.0; // straight
  }

  String _categoryEmoji(String? cat) {
    if (cat == null) return '📍';
    final c = cat.toLowerCase();
    if (c.contains('food') || c.contains('restaurant') || c.contains('cafe')) return '🍽️';
    if (c.contains('hotel') || c.contains('lodging')) return '🏨';
    if (c.contains('shop')) return '🛍️';
    if (c.contains('museum') || c.contains('temple')) return '🏛️';
    if (c.contains('park') || c.contains('garden')) return '🌿';
    if (c.contains('beach')) return '🏖️';
    return '✨';
  }

  // ─── BUILD ───
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final hasCards = _places.isNotEmpty && !_isLoading && _destinationName == null;
    final cardAreaHeight = hasCards ? 180.0 : 0.0;
    final navCardHeight = _routeLoaded
        ? (_destinationName != null ? 310.0 : 250.0)
        : 0.0;
    final bottomOffset = cardAreaHeight + navCardHeight + bottomPad + 16;

    return Scaffold(
      body: Stack(
        children: [
          // ── Mapbox 3D Map ──
          mapbox.MapWidget(
            key: const ValueKey('smart_tourism_3d'),
            onMapCreated: _onMapCreated,
            styleUri: _styles[_styleIndex],
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(widget.initialLng, widget.initialLat),
              ),
              zoom: 14.0,
              pitch: 60.0,
            ),
          ),

          // ── Location Bar & Back Button ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.7),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSearchBar(),
                ),
                const SizedBox(width: 10),
                // ── Clearly-labelled "Google Maps" switch (single entry point) ──
                // A labelled pill so users understand it switches to the familiar
                // Google Maps view, instead of an unlabelled icon.
                GestureDetector(
                  onTap: _launchExternalMapNav,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF34A853)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Google',
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
                ),
                _buildSuggestions(),
              ],
            ),
          ),

          // (Search results overlay removed — the top bar is location-only now.)

          // ── Active Navigation HUD Banner ──
          if (_isActivelyNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 85,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Dynamic turn/arrow icon based on instruction text
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                          ),
                          child: Transform.rotate(
                            angle: _getManeuverAngle(),
                            child: const Icon(
                              Icons.navigation_rounded,
                              color: Color(0xFF00E5FF),
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'TURN-BY-TURN GUIDANCE',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF00E5FF),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _navigationProfile == 'walking'
                                        ? Icons.directions_walk_rounded
                                        : Icons.directions_car_rounded,
                                    color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                                    size: 11,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _navigationSteps.isNotEmpty && _currentStepIndex < _navigationSteps.length
                                    ? _navigationSteps[_currentStepIndex]
                                    : 'Proceed to ${_destinationName ?? "Destination"}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Close button to exit navigation
                        GestureDetector(
                          onTap: _exitFollowNavigation,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_navigationSteps.length > 1) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _currentStepIndex > 0
                                ? () => setState(() => _currentStepIndex--)
                                : null,
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: _currentStepIndex > 0 ? Colors.white70 : Colors.white24,
                              size: 14,
                            ),
                          ),
                          Text(
                            'Step ${_currentStepIndex + 1} of ${_navigationSteps.length}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: _currentStepIndex < _navigationSteps.length - 1
                                ? () => setState(() => _currentStepIndex++)
                                : null,
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: _currentStepIndex < _navigationSteps.length - 1 ? Colors.white70 : Colors.white24,
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // ── Loading ──
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),

          // ── Proximity Alert Banner ──
          if (_proximityAlert != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20, // Moved back up since categories are gone
              left: 20,
              right: 20,
              child: ScaleTransition(
                scale: _alertAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radar_rounded, color: Colors.black, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _proximityAlert!,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Discovery Place Cards ──
          if (hasCards && !_searchFocusNode.hasFocus)
            Positioned(
              bottom: navCardHeight + bottomPad + 8,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 160,
                child: ListView.builder(
                  controller: _cardScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _places.length,
                  itemBuilder: (ctx, i) => _buildPlaceCard(_places[i], i),
                ),
              ),
            ),

          // ── Navigation Info Card ──
          if (_routeLoaded && !_searchFocusNode.hasFocus)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildNavigationCard(),
            ),



          // ── Right side buttons (sleek 48px circles, stacked dynamically) ──
          if (!_searchFocusNode.hasFocus)
            _isActivelyNavigating
                ? Positioned(
                    bottom: bottomOffset,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCircleButton(
                          icon: Icons.my_location_rounded,
                          onTap: _recenterOnUser,
                          bgColor: Colors.black.withValues(alpha: 0.7),
                          iconColor: const Color(0xFF00E5FF),
                        ),
                        const SizedBox(height: 8),
                        _buildCircleButton(
                          icon: Icons.close_rounded,
                          onTap: _exitFollowNavigation,
                          bgColor: Colors.red,
                          iconColor: Colors.white,
                          glow: true,
                        ),
                      ],
                    ),
                  )
                : Positioned(
                    top: MediaQuery.of(context).padding.top + 130, // Positioned completely under the Google button and its shadow
                    bottom: cardAreaHeight + (navCardHeight > 0 ? (navCardHeight - 80.0) : 0.0) + bottomPad + 16, // Shifted 80px down to prevent button clipping
                    right: 20,
                    child: SingleChildScrollView(
                      reverse: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCircleButton(
                            icon: _isAutoTouring
                                ? Icons.stop_rounded
                                : Icons.explore_rounded,
                            onTap: _isAutoTouring
                                ? () => setState(() => _isAutoTouring = false)
                                : _startAutoTour,
                            bgColor: _isAutoTouring
                                ? Colors.red
                                : const Color(0xFF7C4DFF),
                            iconColor: Colors.white,
                            glow: true,
                          ),
                          const SizedBox(height: 8),
                          _buildCircleButton(
                            icon: _styleIcons[_styleIndex],
                            onTap: _toggleMapStyle,
                            bgColor: Colors.black.withValues(alpha: 0.7),
                            iconColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          if (_routeLoaded) ...[
                            _buildCircleButton(
                              icon: Icons.route_rounded,
                              onTap: _fitRouteBounds,
                              bgColor: Colors.black.withValues(alpha: 0.7),
                              iconColor: const Color(0xFF00E5FF),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _buildCircleButton(
                            imagePath: 'assets/images/booking_logo.jpg',
                            onTap: _openBooking,
                            bgColor: Colors.white, // Changed to white to match standard white icon background without blue border ring
                            iconColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          _buildCircleButton(
                            imagePath: 'assets/images/uber_logo.png',
                            onTap: _openUber,
                            bgColor: Colors.black,
                            iconColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          _buildCircleButton(
                            imagePath: 'assets/images/headout.png',
                            onTap: _openHeadout,
                            bgColor: Colors.transparent,
                            iconColor: Colors.white,
                            fillImage: true,
                          ),
                          const SizedBox(height: 8),
                          _buildCircleButton(
                            icon: Icons.my_location_rounded,
                            onTap: _recenterOnUser,
                            bgColor: Colors.black.withValues(alpha: 0.7),
                            iconColor: const Color(0xFF00E5FF),
                          ),
                          const SizedBox(height: 8),
                          _buildCircleButton(
                            icon: Icons.navigation_rounded,
                            onTap: _enterFollowNavigation,
                            bgColor: const Color(0xFF00E5FF),
                            iconColor: Colors.black,
                            glow: true,
                          ),
                        ],
                      ),
                    ),
                  ),
        ],
      ),
    );
  }

  // ─── Discovery Place Card ───
  Widget _buildPlaceCard(AttractionModel place, int index) {
    final isSelected = _selectedCardIndex == index;
    final dist = (_userLat != null && _userLng != null)
        ? _haversine(_userLat!, _userLng!, place.latitude, place.longitude)
        : null;
    final distText = dist != null
        ? (dist < 1000 ? '${dist.toInt()}m' : '${(dist / 1000).toStringAsFixed(1)}km')
        : '';

    return GestureDetector(
      onTap: () => _flyToPlace(place, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 210,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00E5FF)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), blurRadius: 16)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category emoji + name
            Row(
              children: [
                Text(_categoryEmoji(place.categoryName), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    place.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Rating + Distance
            Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.ratingGold, size: 16),
                const SizedBox(width: 4),
                Text(
                  place.rating.toStringAsFixed(1),
                  style: const TextStyle(color: AppColors.ratingGold, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const Spacer(),
                if (distText.isNotEmpty) ...[
                  const Icon(Icons.directions_walk_rounded, color: Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Text(distText, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Category label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                place.categoryName ?? 'Attraction',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launchExternalMapNav() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoogleMapsPage(
          initialLat: _destLat,
          initialLng: _destLng,
          destinationName: _destinationName,
        ),
      ),
    );
  }

  /// Optional Booking.com affiliate id. Paste your `aid` here (free to sign up)
  /// to earn commission on hotel bookings; leave empty for plain links.
  static const String _bookingAffiliateId = '';

  /// Opens Booking.com hotel search for the current destination/area via a deep
  /// link (no API key) — uses the installed app if present, else the website.
  Future<void> _openBooking() async {
    final double lat = _destLat != 0 ? _destLat : (_userLat ?? widget.initialLat);
    final double lng = _destLng != 0 ? _destLng : (_userLng ?? widget.initialLng);
    final name = _destinationName;
    final params = <String, String>{
      if (name != null && name.trim().isNotEmpty) 'ss': name.trim(),
      'latitude': lat.toStringAsFixed(6),
      'longitude': lng.toStringAsFixed(6),
      if (_bookingAffiliateId.isNotEmpty) 'aid': _bookingAffiliateId,
    };
    await _launchExternalUrl(
      Uri.https('www.booking.com', '/searchresults.html', params),
    );
  }

  /// Opens Uber with the drop-off pre-set to the current destination via a deep
  /// link (no API key) — falls back to Uber's site / store if the app is absent.
  Future<void> _openUber() async {
    final double dLat = _destLat != 0 ? _destLat : widget.initialLat;
    final double dLng = _destLng != 0 ? _destLng : widget.initialLng;
    final name = _destinationName ?? 'Destination';
    final params = <String, String>{
      'action': 'setPickup',
      'pickup': 'my_location',
      'dropoff[latitude]': dLat.toStringAsFixed(6),
      'dropoff[longitude]': dLng.toStringAsFixed(6),
      'dropoff[nickname]': name,
    };
    await _launchExternalUrl(Uri.https('m.uber.com', '/ul/', params));
  }

  /// Opens Headout for activities & experiences near the destination.
  Future<void> _openHeadout() async {
    final double lat = _destLat != 0 ? _destLat : (_userLat ?? widget.initialLat);
    final double lng = _destLng != 0 ? _destLng : (_userLng ?? widget.initialLng);
    final name = _destinationName ?? '';
    final uri = await GooglePlacesService.getHeadoutSearchUri(lat, lng, name);
    await _launchExternalUrl(uri);
  }

  Future<void> _launchExternalUrl(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the app or website.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open link: $e")),
        );
      }
    }
  }

  // ─── Navigation Bottom Card ───
  Widget _buildNavigationCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.85),
            Colors.black,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Route info row
          Row(
            children: [
              // Duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _duration,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_distance · ${_navigationProfile == 'walking' ? 'Walking Path' : 'Fastest Route'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // (The navigate arrow moved to the right-side button stack so the
              // recenter and navigate actions are distinct and aligned.)
            ],
          ),
          const SizedBox(height: 20),
          // Segmented profile toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_navigationProfile != 'driving') {
                        setState(() {
                          _navigationProfile = 'driving';
                          _currentStepIndex = 0;
                        });
                        _fetchRoute();
                        if (_isActivelyNavigating) _applyVehiclePuck();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _navigationProfile == 'driving'
                            ? const Color(0xFF00E5FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_car_rounded,
                            color: _navigationProfile == 'driving'
                                ? Colors.black
                                : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Driving',
                            style: TextStyle(
                              color: _navigationProfile == 'driving'
                                  ? Colors.black
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_navigationProfile != 'walking') {
                        setState(() {
                          _navigationProfile = 'walking';
                          _currentStepIndex = 0;
                        });
                        _fetchRoute();
                        if (_isActivelyNavigating) _applyVehiclePuck();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _navigationProfile == 'walking'
                            ? const Color(0xFF00E5FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_walk_rounded,
                            color: _navigationProfile == 'walking'
                                ? Colors.black
                                : Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Walking',
                            style: TextStyle(
                              color: _navigationProfile == 'walking'
                                  ? Colors.black
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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
          const SizedBox(height: 16),
          // Destination name
          if (_destinationName != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded,
                      color: Color(0xFF00E5FF), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _destinationName!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
             GestureDetector(
              onTap: _enterFollowNavigation,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFF00E5FF),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_rounded, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'Start Turn-by-Turn GPS',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The "Open in Google Maps" button was removed here — switching to
            // the Google Maps view is now done from the single top-right button.
          ],
        ],
      ),
    );
  }

  // ─── Circle Button Widget ───
  Widget _buildCircleButton({
    IconData? icon,
    String? imagePath,
    required VoidCallback onTap,
    required Color bgColor,
    required Color iconColor,
    bool glow = false,
    String? label,
    bool fillImage = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, // Increased back to 48 for better visibility/reach
            height: 48, // Increased back to 48 for better visibility/reach
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: bgColor.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: ClipOval(
              child: imagePath != null
                  ? (fillImage
                      ? Image.asset(imagePath, fit: BoxFit.cover)
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: ClipOval(
                            child: Image.asset(imagePath, fit: BoxFit.cover),
                          ),
                        ))
                  : Icon(icon, color: iconColor, size: 22), // Set icon size to 22px
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearDestinationAndRoute() async {
    setState(() {
      _destinationNameOverride = '';
      _routeLoaded = false;
      _routeCoordinates = [];
      _destLat = _userLat ?? widget.initialLat;
      _destLng = _userLng ?? widget.initialLng;
      _isLoading = true;
    });

    try {
      if (_mapboxMap != null) {
        final layerExists = await _mapboxMap!.style.styleLayerExists('route-line');
        if (layerExists) await _mapboxMap!.style.removeStyleLayer('route-line');
        final glowExists = await _mapboxMap!.style.styleLayerExists('route-glow');
        if (glowExists) await _mapboxMap!.style.removeStyleLayer('route-glow');
        final srcExists = await _mapboxMap!.style.styleSourceExists('route-source');
        if (srcExists) await _mapboxMap!.style.removeStyleSource('route-source');
      }
    } catch (e) {
      debugPrint('Error clearing route: $e');
    }

    await _fetchPlaces();
  }

  Future<void> _onSearchSubmitted(String query) async {
    _searchFocusNode.unfocus();
    if (query.trim().isEmpty) {
      await _clearDestinationAndRoute();
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await GooglePlacesService.searchPlaces(
        query: query,
        latitude: _userLat ?? _destLat,
        longitude: _userLng ?? _destLng,
      );
      if (results.isNotEmpty) {
        final place = results.first;
        setState(() {
          _destLat = place.latitude;
          _destLng = place.longitude;
          _destinationNameOverride = place.name;
          _searchController.text = place.name;
          _places = [];
        });
        await _fetchRoute();
        _fitRouteBounds();
        _addMarkers();
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No results found for "$query"'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error searching for location'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _onSearchTextChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestions = []);
    }
  }

  Future<void> _onSuggestionTapped(Map<String, dynamic> suggestion) async {
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = [];
      _isLoading = true;
    });
    final placeId = suggestion['place_id'] as String;
    final placeDetails = await GooglePlacesService.getPlaceDetails(placeId);
    if (placeDetails != null) {
      setState(() {
        _destLat = placeDetails.latitude;
        _destLng = placeDetails.longitude;
        _destinationNameOverride = placeDetails.name;
        _searchController.text = placeDetails.name;
        _places = [];
      });
      await _fetchRoute();
      _fitRouteBounds();
      _addMarkers();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchTextChanged,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _onSearchSubmitted,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _suggestions = []);
                    _clearDestinationAndRoute();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Autocomplete dropdown — rendered full-width BELOW the whole search row (not
  /// inside the narrow search field), so long place names show clearly on one
  /// line instead of wrapping.
  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _suggestions.length,
          itemBuilder: (context, index) {
            final item = _suggestions[index];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.location_on_rounded, color: Color(0xFF00E5FF), size: 16),
              title: Text(
                item['main_text'] ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item['description'] ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _onSuggestionTapped(item),
            );
          },
        ),
      ),
    );
  }
}
