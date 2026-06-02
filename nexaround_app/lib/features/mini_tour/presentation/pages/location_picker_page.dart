import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:nexaround_app/app/theme/app_colors.dart';

/// Full-screen Mapbox picker: pan/zoom the map so the centre pin sits over the
/// area you want a tour in, then confirm. Pops `{lat, lng}` back to the caller.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  mapbox.MapboxMap? _map;
  double _initLat = 6.9271; // Colombo fallback until GPS resolves
  double _initLng = 79.8612;
  bool _ready = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _seedFromGps();
  }

  Future<void> _seedFromGps() async {
    try {
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm != geo.LocationPermission.denied &&
          perm != geo.LocationPermission.deniedForever) {
        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 8));
        _initLat = pos.latitude;
        _initLng = pos.longitude;
      }
    } catch (_) {
      // Keep the fallback centre.
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _confirm() async {
    if (_map == null) return;
    setState(() => _confirming = true);
    try {
      final cam = await _map!.getCameraState();
      final c = cam.center.coordinates;
      if (!mounted) return;
      Navigator.pop(context, {
        'lat': c.lat.toDouble(),
        'lng': c.lng.toDouble(),
      });
    } catch (_) {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          mapbox.MapWidget(
            key: const ValueKey('mini_tour_picker_map'),
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(_initLng, _initLat),
              ),
              zoom: 14.0,
            ),
            onMapCreated: (m) {
              _map = m;
              m.logo.updateSettings(mapbox.LogoSettings(enabled: false));
              m.attribution
                  .updateSettings(mapbox.AttributionSettings(enabled: false));
              m.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
              m.compass.updateSettings(mapbox.CompassSettings(enabled: false));
            },
          ),

          // Fixed centre pin (nudged up so the tip marks the exact centre).
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on,
                  size: 50, color: AppColors.brandGreen, shadows: const [
                Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
              ]),
            ),
          ),

          _buildTopBar(),
          _buildConfirmBar(),
        ],
      ),
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
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Drag the map to choose a spot',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmBar() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 40,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _confirming ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: _confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.flag_rounded, size: 18),
          label: Text(
            _confirming ? 'Building tour…' : 'Start tour here',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
