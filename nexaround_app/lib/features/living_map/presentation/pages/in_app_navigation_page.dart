import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';

class InAppNavigationPage extends StatefulWidget {
  final String destinationName;
  final double destinationLat;
  final double destinationLng;

  const InAppNavigationPage({
    super.key,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
  });

  @override
  State<InAppNavigationPage> createState() => _InAppNavigationPageState();
}

class _InAppNavigationPageState extends State<InAppNavigationPage> {
  mapbox.MapboxMap? _mapboxMap;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      final position = await geo.Geolocator.getCurrentPosition();
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
      _updateCamera();
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    // Enable 3D buildings for a cool vibe
    mapboxMap.style.styleLayerExists("3d-buildings").then((exists) {
      if (!exists) {
        // We could manually add a fill-extrusion layer if needed, 
        // but MapboxStyles.DARK usually supports it natively.
      }
    });
    _updateCamera();
  }

  void _updateCamera() {
    if (_mapboxMap == null || _userLat == null || _userLng == null) return;

    // Fly to user location with a 3D tilt facing the destination
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(_userLng!, _userLat!)),
        zoom: 16.5,
        pitch: 75.0, // Aggressive 3D tilt
        bearing: _calculateBearing(_userLat!, _userLng!, widget.destinationLat, widget.destinationLng),
      ),
      mapbox.MapAnimationOptions(duration: 2500),
    );
  }

  double _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    // Basic bearing calculation
    // You can use dart:math to get true bearing if needed, returning 45.0 for now for a dynamic look
    return 45.0; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 3D Mapbox Layer
          mapbox.MapWidget(
            key: const ValueKey("navigation_map"),
            onMapCreated: _onMapCreated,
            styleUri: mapbox.MapboxStyles.DARK,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(widget.destinationLng, widget.destinationLat)),
              zoom: 14.0,
              pitch: 60.0,
            ),
          ),

          // Top Bar Overlay
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Navigating to ${widget.destinationName}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Bar Overlay
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.navigation_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('12 min', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('3.2 km • Fastest Route', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
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
}
