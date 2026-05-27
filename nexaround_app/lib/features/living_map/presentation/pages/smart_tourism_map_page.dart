import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // Map style
  int _styleIndex = 0;
  static const _styles = [
    mapbox.MapboxStyles.DARK,
    mapbox.MapboxStyles.SATELLITE_STREETS,
    mapbox.MapboxStyles.STANDARD,
  ];
  static const _styleLabels = ['Dark', 'Satellite', 'Standard'];
  static const _styleIcons = [Icons.dark_mode, Icons.satellite_alt, Icons.map];

  // Proximity alert
  String? _proximityAlert;
  String _currentNeighborhood = 'Locating...';
  int? _selectedCardIndex;
  bool _isAutoTouring = false;
  final ScrollController _cardScrollController = ScrollController();

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

    _fetchPlaces();
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
      final path = '${ApiConstants.mapboxProxy}/$_userLng,$_userLat;$_destLng,$_destLat';

      final response = await ApiClient.instance.get(
        path,
        queryParameters: {
          'geometries': 'geojson',
          'overview': 'full',
        },
      );
      final data = response.data;

      if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final durationSec = (route['duration'] as num).toDouble();
        final distanceM = (route['distance'] as num).toDouble();
        final coords = (route['geometry']['coordinates'] as List)
            .map<List<double>>(
                (c) => [c[0].toDouble(), c[1].toDouble()])
            .toList();

        if (mounted) {
          setState(() {
            _duration = durationSec < 3600
                ? '${(durationSec / 60).ceil()} min'
                : '${(durationSec / 3600).toStringAsFixed(1)} hr';
            _distance = distanceM < 1000
                ? '${distanceM.toInt()} m'
                : '${(distanceM / 1000).toStringAsFixed(1)} km';
            _routeCoordinates = coords;
            _routeLoaded = true;
          });
          _drawRoute();
        }
      }
    } catch (e) {
      debugPrint('Route fetch error: $e');
    }
  }

  // ─── Map Created ───
  void _onMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;

    // Enable the user‑location puck (blue dot)
    map.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: AppColors.primary.toARGB32(),
        showAccuracyRing: true,
      ),
    );

    // Hide default Mapbox ornaments for a clean, custom UI
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

    // Wait for style to fully load before adding layers
    await Future.delayed(const Duration(milliseconds: 800));

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
      await _mapboxMap!.style.addStyleLayer(
        jsonEncode({
          'id': 'route-glow',
          'type': 'line',
          'source': 'route-source',
          'paint': {
            'line-color': '#00E5FF',
            'line-width': 12,
            'line-opacity': 0.25,
            'line-blur': 8,
          },
          'layout': {
            'line-cap': 'round',
            'line-join': 'round',
          },
        }),
        null,
      );

      // Add main route line
      await _mapboxMap!.style.addStyleLayer(
        jsonEncode({
          'id': 'route-line',
          'type': 'line',
          'source': 'route-source',
          'paint': {
            'line-color': '#00E5FF',
            'line-width': 5,
            'line-opacity': 0.9,
          },
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

  // ─── Add place markers ───
  Future<void> _addMarkers() async {
    if (_annotationManager == null) return;
    await _annotationManager!.deleteAll();

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

  // ─── Re‑center on user ───
  void _flyToUser() {
    if (_userLat == null || _userLng == null) return;
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_userLng!, _userLat!),
        ),
        zoom: 16.5,
        pitch: 65.0,
        bearing: 0,
      ),
      mapbox.MapAnimationOptions(duration: 1500),
    );
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
    // Re-add 3D buildings after style change
    Future.delayed(const Duration(milliseconds: 1200), () {
      _add3DBuildingLayer();
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
  void _flyToPlace(AttractionModel place, int index) {
    setState(() => _selectedCardIndex = index);
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
    final hasCards = _places.isNotEmpty && !_isLoading;
    final cardAreaHeight = hasCards ? 180.0 : 0.0;
    final navCardHeight = _routeLoaded ? 180.0 : 0.0;
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

          // ── Location Bar ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 80, 
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.near_me_rounded, color: Color(0xFF00E5FF), size: 14),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'CURRENT NEIGHBORHOOD',
                          style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            color: Colors.white70,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          _currentNeighborhood,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
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
          if (hasCards)
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
          if (_routeLoaded)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildNavigationCard(),
            ),

          // ── Left side buttons ──
          Positioned(
            bottom: bottomOffset,
            left: 20,
            child: _buildCircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context),
              bgColor: Colors.black.withValues(alpha: 0.7),
              iconColor: Colors.white,
            ),
          ),

          // ── Right side buttons ──
          Positioned(
            bottom: bottomOffset,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Auto Tour
                _buildCircleButton(
                  icon: _isAutoTouring ? Icons.stop_rounded : Icons.explore_rounded,
                  onTap: _isAutoTouring ? () => setState(() => _isAutoTouring = false) : _startAutoTour,
                  bgColor: _isAutoTouring ? Colors.red : const Color(0xFF7C4DFF),
                  iconColor: Colors.white,
                  glow: true,
                ),
                const SizedBox(height: 12),
                // Map Style Toggle
                _buildCircleButton(
                  icon: _styleIcons[_styleIndex],
                  onTap: _toggleMapStyle,
                  bgColor: Colors.black.withValues(alpha: 0.7),
                  iconColor: Colors.white,
                  label: _styleLabels[_styleIndex],
                ),
                const SizedBox(height: 12),
                // Fit Route
                if (_routeLoaded)
                  _buildCircleButton(
                    icon: Icons.route_rounded,
                    onTap: _fitRouteBounds,
                    bgColor: Colors.black.withValues(alpha: 0.7),
                    iconColor: const Color(0xFF00E5FF),
                  ),
                const SizedBox(height: 12),
                // My Location
                _buildCircleButton(
                  icon: Icons.my_location_rounded,
                  onTap: _flyToUser,
                  bgColor: const Color(0xFF00E5FF),
                  iconColor: Colors.black,
                  glow: true,
                ),
              ],
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
                      '$_distance · Fastest Route',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Destination icon
              GestureDetector(
                onTap: _flyToDestination,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Destination name
          if (widget.destinationName != null)
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
                      widget.destinationName!,
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
        ],
      ),
    );
  }

  // ─── Circle Button Widget ───
  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color bgColor,
    required Color iconColor,
    bool glow = false,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: bgColor.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
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
}
