import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

class GoogleMapsPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String? destinationName;

  const GoogleMapsPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.destinationName,
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

  // Search
  final TextEditingController _searchController = TextEditingController();
  List<AttractionEntity> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  // Destination (can be updated via search)
  late double _destLat;
  late double _destLng;
  String? _destName;

  // Animation
  late AnimationController _fabAnimController;
  late Animation<double> _fabAnim;

  @override
  void initState() {
    super.initState();
    _destLat = widget.initialLat;
    _destLng = widget.initialLng;
    _destName = widget.destinationName;

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fabAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.easeOutBack,
    );

    _init();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _getUserLocation();
    _addDestinationMarker();
    _fetchRoute();
    _fabAnimController.forward();
  }

  Future<void> _getUserLocation() async {
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
        });
        _addUserMarker();
      }
    } catch (_) {
      // Fallback
      setState(() {
        _userLat = 6.9271;
        _userLng = 79.8612;
      });
    }
  }

  void _addUserMarker() {
    if (_userLat == null || _userLng == null) return;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user');
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: LatLng(_userLat!, _userLng!),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    });
  }

  void _addDestinationMarker() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'dest');
      _markers.add(
        Marker(
          markerId: const MarkerId('dest'),
          position: LatLng(_destLat, _destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: _destName ?? 'Destination',
            snippet: 'Tap to navigate',
          ),
        ),
      );
    });
  }

  Future<void> _fetchRoute() async {
    if (_userLat == null || _userLng == null) return;

    try {
      final result = await GooglePlacesService.getDirections(
        originLat: _userLat!,
        originLng: _userLng!,
        destLat: _destLat,
        destLng: _destLng,
      );

      if (result != null && mounted) {
        final points = result['polyline'] as List<LatLng>? ?? [];
        final durationSec = result['duration_seconds'] as double? ?? 0;
        final distanceM = result['distance_meters'] as double? ?? 0;

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              color: const Color(0xFF4285F4),
              width: 5,
              patterns: [],
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          _duration = durationSec < 3600
              ? '${(durationSec / 60).ceil()} min'
              : '${(durationSec / 3600).toStringAsFixed(1)} hr';
          _distance = distanceM < 1000
              ? '${distanceM.toInt()} m'
              : '${(distanceM / 1000).toStringAsFixed(1)} km';
          _routeLoaded = true;
        });
        _fitRouteBounds(points);
      }
    } catch (e) {
      debugPrint('Google Maps route error: $e');
      // Still show the map focused on destination
      _animateCameraToDestination();
    }
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
          tilt: 45,
        ),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    // Apply dark style
    _applyDarkStyle(controller);
    // Fit to show both user and destination if route loads
    if (!_routeLoaded) {
      _animateCameraToDestination();
    }
  }

  void _applyDarkStyle(GoogleMapController controller) {
    controller.setMapStyle('''[
      {"elementType": "geometry", "stylers": [{"color": "#0d0d1a"}]},
      {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
      {"elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
      {"elementType": "labels.text.stroke", "stylers": [{"color": "#1d2c4d"}]},
      {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
      {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]},
      {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#bdbdbd"}]},
      {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
      {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#0d2a1c"}]},
      {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b9a76"}]},
      {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#1a1a2e"}]},
      {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
      {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
      {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#2c3e6b"}]},
      {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2835"}]},
      {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#f3d19c"}]},
      {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f3948"}]},
      {"featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
      {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#060d13"}]},
      {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]},
      {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#17263c"}]}
    ]''');
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });
    try {
      final results = await GooglePlacesService.searchPlaces(
        query: query,
        latitude: _userLat ?? _destLat,
        longitude: _userLng ?? _destLng,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectSearchResult(AttractionEntity place) {
    setState(() {
      _destLat = place.latitude;
      _destLng = place.longitude;
      _destName = place.name;
      _showSearchResults = false;
      _searchController.text = place.name;
      _routeLoaded = false;
      _polylines.clear();
    });
    FocusScope.of(context).unfocus();
    _addDestinationMarker();
    _fetchRoute();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: Stack(
        children: [
          // ── Google Map ──
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.initialLat, widget.initialLng),
              zoom: 14.0,
              tilt: 45.0,
            ),
            markers: _markers,
            polylines: _polylines,
            mapType: _mapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: true,
            trafficEnabled: false,
            padding: EdgeInsets.only(
              top: topPad + 80,
              bottom: _routeLoaded ? 220 : 0,
            ),
          ),

          // ── Top Bar ──
          Positioned(
            top: topPad + 16,
            left: 16,
            right: 16,
            child: _buildTopBar(),
          ),

          // ── Search Results Dropdown ──
          if (_showSearchResults && (_searchResults.isNotEmpty || _isSearching))
            Positioned(
              top: topPad + 68,
              left: 62,
              right: 16,
              child: _buildSearchDropdown(),
            ),

          // ── Route Info Card ──
          if (_routeLoaded)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildRouteCard(bottomPad),
            ),

          // ── Right FAB Stack ──
          Positioned(
            right: 16,
            bottom: _routeLoaded ? 210 + bottomPad : 80 + bottomPad,
            child: ScaleTransition(
              scale: _fabAnim,
              child: _buildFabStack(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.8),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 10),
        // Search bar
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: _destName ?? 'Search any place...',
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF4285F4), size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: Colors.white60, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _showSearchResults = false;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 16),
                  ),
                  onChanged: _performSearch,
                  onSubmitted: _performSearch,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Google Maps badge
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF4285F4), Color(0xFF34A853)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4285F4).withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.map_rounded, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  Widget _buildSearchDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _isSearching
            ? const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF4285F4),
                      strokeWidth: 2,
                    ),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final place = _searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: Color(0xFF4285F4),
                        size: 16,
                      ),
                    ),
                    title: Text(
                      place.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: place.address != null
                        ? Text(
                            place.address!,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: place.distanceM != null
                        ? Text(
                            place.distanceM! < 1000
                                ? '${place.distanceM!.toInt()}m'
                                : '${(place.distanceM! / 1000).toStringAsFixed(1)}km',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10),
                          )
                        : null,
                    onTap: () => _selectSearchResult(place),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildRouteCard(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF0A0A12).withValues(alpha: 0.9),
            const Color(0xFF0A0A12),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Destination info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.place_rounded,
                      color: Color(0xFF4285F4), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _destName ?? 'Destination',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 12, color: Color(0xFF4285F4)),
                          const SizedBox(width: 4),
                          Text(
                            _duration,
                            style: const TextStyle(
                                color: Color(0xFF4285F4),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.straighten_rounded,
                              size: 12, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            _distance,
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Map type toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _mapType = _mapType == MapType.normal
                          ? MapType.hybrid
                          : MapType.normal;
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      _mapType == MapType.normal
                          ? Icons.satellite_alt_rounded
                          : Icons.map_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Navigate button
          GestureDetector(
            onTap: () {
              if (_controller != null && _userLat != null) {
                _controller!.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(_userLat!, _userLng!),
                      zoom: 17,
                      tilt: 60,
                      bearing: 0,
                    ),
                  ),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF1A73E8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.35),
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

  Widget _buildFabStack() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // My location
        _buildFab(
          icon: Icons.my_location_rounded,
          color: const Color(0xFF4285F4),
          onTap: () {
            if (_userLat != null && _userLng != null) {
              _controller?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(_userLat!, _userLng!),
                    zoom: 17,
                    tilt: 50,
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
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
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
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
