import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
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

class _ArViewState extends State<ArView> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _startLocationTracking();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _arSessionManager?.dispose();
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

  void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arSessionManager?.onInitialize(
      showFeaturePoints: false,
      showPlanes: false,
      showWorldOrigin: false,
      handleTaps: true,
    );
    _arObjectManager?.onInitialize();
    
    context.read<ArBloc>().add(ArSessionStarted());
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebFallback();
    }

    return Scaffold(
      body: BlocConsumer<ArBloc, ArState>(
        listener: (context, state) {
          if (state.attractions.isNotEmpty) {
            _updateArNodes(state);
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              ARView(
                onARViewCreated: onARViewCreated,
                planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
              ),
              
              // Overlay UI
              _buildTopBar(),
              
              if (state.selectedAttraction != null)
                _buildAttractionDetail(state.selectedAttraction!),
                
              if (state.status == ArStatus.loading)
                const Center(child: CircularProgressIndicator()),
                
              _buildScannerOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebFallback() {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mobile_friendly_rounded, size: 80, color: AppColors.primary),
              ),
              const SizedBox(height: 32),
              const Text(
                'Mobile Required for AR',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Advanced Augmented Reality features require ARCore (Android) or ARKit (iOS) sensors. Please use your mobile device to experience NexAround AR.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.radar_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Scanning Surroundings',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
          borderRadius: BorderRadius.circular(125),
        ),
        child: const Center(
          child: Icon(Icons.add, color: Colors.white24, size: 40),
        ),
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
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withOpacity(0.5)),
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
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                backgroundColor: Colors.white24,
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

  void _updateArNodes(ArState state) async {
    if (_arObjectManager == null) return;

    // Clear existing nodes
    // Note: In real production, we'd delta-update
    
    for (var attraction in state.attractions) {
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

      // Simple placement logic: Place nodes 2-3 meters away in the direction of the POI
      // Normalized distance for visualization
      const double visualDistance = 3.0;
      final angle = (bearing - state.currentHeading) * pi / 180;
      
      final x = visualDistance * sin(angle);
      final z = -visualDistance * cos(angle);
      
      final node = ARNode(
        type: NodeType.localGLTF2,
        uri: "assets/ar_models/poi_marker.gltf", // Need to ensure this exists or use a primitive
        position: vector.Vector3(x, 0, z),
        scale: vector.Vector3(0.5, 0.5, 0.5),
        name: attraction.id,
      );
      
      await _arObjectManager?.addNode(node);
    }
  }
}
