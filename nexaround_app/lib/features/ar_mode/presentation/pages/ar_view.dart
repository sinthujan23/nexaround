import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/geo_calculator.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_bloc.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_state.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

class ArView extends StatefulWidget {
  const ArView({super.key});

  @override
  State<ArView> createState() => _ArViewState();
}

class _ArViewState extends State<ArView> with TickerProviderStateMixin {
  StreamSubscription<Position>? _positionStream;
  late AnimationController _pulseController;
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    if (!kIsWeb) {
      _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (mounted) {
        context.read<ArBloc>().add(ArUpdateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show the AR experience UI on all platforms
    // On mobile, this uses location-based AR overlay
    // On web, this shows the same UI with simulated data
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: BlocBuilder<ArBloc, ArState>(
        builder: (context, state) {
          return Stack(
            children: [
              // Dark AR-style background with grid
              _buildArBackground(),

              // Radar/Scanner overlay
              _buildScannerOverlay(),

              // AR POI markers
              if (state.attractions.isNotEmpty)
                ..._buildArMarkers(state),

              // Top status bar
              _buildTopBar(state),

              // Bottom attraction detail
              if (state.selectedAttraction != null)
                _buildAttractionDetail(state.selectedAttraction!),

              // Loading indicator
              if (state.status == ArStatus.loading)
                const Center(child: CircularProgressIndicator(color: AppColors.primary)),

              // "AR Coming Soon" banner
              if (kIsWeb) _buildWebBanner(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildArBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0E1A),
            Color(0xFF0D1326),
            Color(0xFF101832),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _GridPainter(),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Center(
      child: AnimatedBuilder(
        animation: _scanController,
        builder: (context, child) {
          return Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2 + 0.2 * _pulseController.value),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating scan line
                Transform.rotate(
                  angle: _scanController.value * 2 * pi,
                  child: Container(
                    width: 2,
                    height: 130,
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 2,
                      height: 65,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primary.withOpacity(0.8),
                            AppColors.primary.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Center crosshair
                const Icon(Icons.add, color: Colors.white24, size: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildArMarkers(ArState state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final rng = Random(42);

    return state.attractions.take(5).map((attraction) {
      final bearing = GeoCalculator.bearing(
        state.currentLatitude,
        state.currentLongitude,
        attraction.latitude,
        attraction.longitude,
      );

      final distance = GeoCalculator.distance(
        state.currentLatitude,
        state.currentLongitude,
        attraction.latitude,
        attraction.longitude,
      );

      // Position markers around the screen based on bearing
      final angle = (bearing - state.currentHeading) * pi / 180;
      final x = screenWidth / 2 + (screenWidth * 0.35 * sin(angle));
      final y = screenHeight * 0.25 + rng.nextDouble() * screenHeight * 0.35;

      return Positioned(
        left: x - 40,
        top: y - 40,
        child: GestureDetector(
          onTap: () {
            context.read<ArBloc>().add(ArSelectAttraction(attraction));
          },
          child: _ArMarkerWidget(
            attraction: attraction,
            distance: distance,
            pulseAnimation: _pulseController,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTopBar(ArState state) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Icon(
                      Icons.radar_rounded,
                      color: AppColors.primary.withOpacity(0.5 + 0.5 * _pulseController.value),
                      size: 20,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  state.attractions.isEmpty
                      ? 'Scanning Surroundings...'
                      : '${state.attractions.length} Places Found',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: IconButton(
              icon: const Icon(Icons.help_outline_rounded, color: Colors.white, size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Point your device around to discover nearby places!'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttractionDetail(AttractionEntity attraction) {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.darkSurface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attraction.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attraction.address ?? 'Colombo, Sri Lanka',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'AI INSIGHT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Looking at this historical site...',
              style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.3),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Start AI Audio Guide', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebBanner() {
    return Positioned(
      bottom: 100,
      left: 40,
      right: 40,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Install the app for full AR experience with camera overlay',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom AR Marker Widget
class _ArMarkerWidget extends StatelessWidget {
  final AttractionEntity attraction;
  final double distance;
  final AnimationController pulseAnimation;

  const _ArMarkerWidget({
    required this.attraction,
    required this.distance,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing marker
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.15),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.5 + 0.3 * pulseAnimation.value),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2 * pulseAnimation.value),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.place, color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 6),
            // Label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    attraction.name,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${distance.toStringAsFixed(0)}m away',
                    style: TextStyle(color: AppColors.primary.withOpacity(0.8), fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Grid painter for AR background
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 0.5;

    const spacing = 40.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
