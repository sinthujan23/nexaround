import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/mapbox_geocoding_service.dart';

/// Shows the point the Home screen will search around, on a map, and lets the
/// traveller move it before anything is fetched.
///
/// A search result is one point chosen by the search provider: for a city it
/// is the provider's idea of the centre, which is rarely where the traveller
/// is staying. Until this page that point was used unseen. Here the pin stays
/// in the middle of the screen and the map moves under it, the way the
/// Walking Challenge picker works.
///
/// Nothing is fetched while the map moves. The caller fetches once, after
/// "Explore here", with what this page pops:
/// `{latitude, longitude, name, district}`. Backing out pops nothing.
class ExplorePinPage extends StatefulWidget {
  /// Where the pin starts: the searched place, or the centre already in use
  /// when the traveller came in through "Choose on map". Null opens a world
  /// view to pan from.
  final double? initialLatitude;
  final double? initialLongitude;

  /// The name of the searched place. Kept for the chip while the pin stays
  /// near where the search put it. Null when there was no search.
  final String? placeName;
  final String? district;

  const ExplorePinPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.placeName,
    this.district,
  });

  @override
  State<ExplorePinPage> createState() => _ExplorePinPageState();
}

class _ExplorePinPageState extends State<ExplorePinPage> {
  /// The circle drawn round the pin. Food, shops and the Around You map are
  /// searched within 5 km; sights and nature reach further, which the caption
  /// says rather than the circle.
  static const double _circleRadiusM = 5000;

  /// How much of the screen's width the circle takes when the page opens.
  static const double _circleWidthShare = 0.62;

  /// A pin still inside the circle first drawn round the searched place keeps
  /// that place's name; further out, the chip shows the city the pin is in.
  ///
  /// Not a tighter limit, because the city lookup names administrative areas:
  /// 3 km south of Colombo's centre it answers "Thimbirigasyaya", which is no
  /// name a traveller who searched for Colombo expects to see.
  static const double _keepNameWithinM = _circleRadiusM;

  /// Metres across one screen point at zoom 0 on the equator (Mapbox draws the
  /// world 512 points wide at zoom 0).
  static const double _metresPerPointAtZoom0 = 78271.51696;

  mapbox.MapboxMap? _map;
  bool _confirming = false;

  /// The circle's radius in screen points. A notifier so that only the circle
  /// repaints as the map zooms, not the map widget.
  final ValueNotifier<double> _circleRadiusPx = ValueNotifier<double>(0);
  bool _syncing = false;
  bool _syncAgain = false;

  /// The zoom the map opens at. Worked out once, from the screen's width.
  double? _openingZoom;

  bool get _hasStart =>
      widget.initialLatitude != null && widget.initialLongitude != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openingZoom != null) return;
    final zoom = _zoomToFitCircle(MediaQuery.of(context).size.width);
    _openingZoom = zoom;
    if (_hasStart) {
      // Right for the opening zoom; the first camera read replaces it.
      _circleRadiusPx.value =
          _circleRadiusM / _metresPerPoint(widget.initialLatitude!, zoom);
    }
  }

  @override
  void dispose() {
    _circleRadiusPx.dispose();
    super.dispose();
  }

  static double _metresPerPoint(double latitude, double zoom) =>
      _metresPerPointAtZoom0 *
      math.cos(latitude * math.pi / 180) /
      math.pow(2, zoom);

  /// The zoom at which the circle takes [_circleWidthShare] of the screen.
  double _zoomToFitCircle(double screenWidth) {
    if (!_hasStart) return 1.5;
    final wantedMetresPerPoint =
        (_circleRadiusM * 2) / (screenWidth * _circleWidthShare);
    final cosLat =
        math.cos(widget.initialLatitude! * math.pi / 180).abs().clamp(0.05, 1.0);
    final zoom = math.log(_metresPerPointAtZoom0 * cosLat / wantedMetresPerPoint) /
        math.ln2;
    return zoom.clamp(3.0, 16.0).toDouble();
  }

  /// Resize the circle to the map's current zoom. Camera changes arrive many
  /// times a second while a finger is down; one read runs at a time, and a
  /// change that lands during a read asks for one more so the last frame is
  /// never the stale one.
  Future<void> _syncCircle() async {
    _syncAgain = true;
    if (_syncing) return;
    _syncing = true;
    try {
      while (_syncAgain && mounted) {
        _syncAgain = false;
        final map = _map;
        if (map == null) break;
        final cam = await map.getCameraState();
        if (!mounted) break;
        final lat = cam.center.coordinates.lat.toDouble();
        _circleRadiusPx.value = _circleRadiusM / _metresPerPoint(lat, cam.zoom);
      }
    } catch (_) {
      // The circle is a guide; a missed resize is not worth an error.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _confirm() async {
    final map = _map;
    if (map == null || _confirming) return;
    setState(() => _confirming = true);
    try {
      final cam = await map.getCameraState();
      final c = cam.center.coordinates;
      final lat = c.lat.toDouble();
      final lng = c.lng.toDouble();

      var name = (widget.placeName ?? '').trim();
      var district = (widget.district ?? '').trim();

      final nearWhatWasSearched = _hasStart &&
          name.isNotEmpty &&
          geo.Geolocator.distanceBetween(
                widget.initialLatitude!,
                widget.initialLongitude!,
                lat,
                lng,
              ) <=
              _keepNameWithinM;

      if (!nearWhatWasSearched) {
        // The pin is somewhere the search did not name: show its city.
        final city = await MapboxGeocodingService.reverseCity(lat, lng)
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (city != null) {
          name = city['name']!;
          district = city['region'] ?? name;
        } else if (name.isEmpty) {
          // No searched name to fall back on, so ask the lookup the GPS chip
          // already uses.
          final details = await GooglePlacesService.reverseGeocodeDetailed(lat, lng)
              .timeout(const Duration(seconds: 4), onTimeout: () => const {});
          final locName = details['location_name'] ?? 'Nearby';
          final locDistrict = details['district'] ?? 'Nearby';
          if (locName != 'Nearby') {
            name = locName;
          } else if (locDistrict != 'Nearby') {
            name = locDistrict;
          }
          if (locDistrict != 'Nearby') district = locDistrict;
        }
      }

      if (name.isEmpty) name = 'Selected area';
      if (district.isEmpty) district = name;

      if (!mounted) return;
      Navigator.pop(context, <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'name': name,
        'district': district,
      });
    } catch (_) {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          mapbox.MapWidget(
            key: const ValueKey('explore_pin_map'),
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  widget.initialLongitude ?? 0.0,
                  widget.initialLatitude ?? 20.0,
                ),
              ),
              zoom: _openingZoom ?? 1.5,
            ),
            onMapCreated: (m) {
              _map = m;
              m.logo.updateSettings(mapbox.LogoSettings(enabled: false));
              m.attribution
                  .updateSettings(mapbox.AttributionSettings(enabled: false));
              m.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
              m.compass.updateSettings(mapbox.CompassSettings(enabled: false));
              // A tilted map would turn the circle into an ellipse the flat
              // overlay cannot follow.
              m.gestures
                  .updateSettings(mapbox.GesturesSettings(pitchEnabled: false));
              _syncCircle();
            },
            onCameraChangeListener: (_) => _syncCircle(),
          ),

          // The area searched round the pin.
          IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: _circleRadiusPx,
              builder: (context, radiusPx, _) {
                // Zoomed out to a country or further, 5 km is a dot under the
                // pin, and a label on it would only cover the pin.
                if (radiusPx < 12) return const SizedBox.shrink();
                // Once the circle is larger than the screen its edge is out of
                // sight, and so would its label be.
                final labelFits = radiusPx * 2 < size.shortestSide - 24;
                return OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: radiusPx * 2,
                    height: radiusPx * 2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brandGreen.withValues(alpha: 0.10),
                              border: Border.all(
                                color: AppColors.brandGreen.withValues(alpha: 0.65),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (labelFits)
                          Positioned(
                            top: -11,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.brandGreen,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                '5 km',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
          _buildConfirmCard(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final searched = (widget.placeName ?? '').trim();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
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
              child: Text(
                searched.isEmpty ? 'Choose where to explore' : searched,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmCard() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Drag the map to move the pin',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Nearby places are found around this pin. Food and shops come '
              'from inside the circle; sights can be further away.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirming ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.brandGreen.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _confirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.explore_rounded, size: 18),
                label: const Text(
                  'Explore here',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
