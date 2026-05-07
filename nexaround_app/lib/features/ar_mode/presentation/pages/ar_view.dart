import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:nexaround_app/core/network/geocoding_service.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/geo_calculator.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_bloc.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_state.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ArView extends StatefulWidget {
  const ArView({super.key});

  @override
  State<ArView> createState() => _ArViewState();
}

class _ArViewState extends State<ArView> with TickerProviderStateMixin {
  StreamSubscription<Position>? _positionStream;
  CameraController? _cameraController;
  late ObjectDetector _objectDetector;
  bool _cameraInitialized = false;
  bool _cameraError = false;
  bool _isProcessing = false;
  List<DetectedObject> _detectedObjects = [];
  String _currentAddress = 'Locating...';
  
  // Mapping Mode Controllers
  final TextEditingController _placeNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategoryId = 'HERITAGE';

  final List<Map<String, dynamic>> _discoveryCategories = [
    {'id': 'HERITAGE', 'icon': Icons.account_balance_rounded, 'label': 'Heritage'},
    {'id': 'DINING', 'icon': Icons.restaurant_rounded, 'label': 'Dining'},
    {'id': 'VIEWPOINT', 'icon': Icons.photo_camera_rounded, 'label': 'Viewpoint'},
    {'id': 'SECRET', 'icon': Icons.vpn_key_rounded, 'label': 'Secret Spot'},
    {'id': 'NATURE', 'icon': Icons.park_rounded, 'label': 'Nature'},
  ];

  late AnimationController _pulseController;
  late AnimationController _scanController;

  static const double _detectionAngle = 20.0;
  static const double _detectionDistance = 50000.0;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    if (!kIsWeb) {
      _initCamera();
      _startLocationTracking();
    }
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _initCamera() async {
    try {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _cameraError = true);
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _cameraInitialized = true);
        _startDetectionStream();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _cameraController?.dispose();
    _objectDetector.close();
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  void _startDetectionStream() {
    _cameraController?.startImageStream((CameraImage image) {
      if (_isProcessing) return;
      _isProcessing = true;
      _processImage(image);
    });
  }

  Future<void> _processImage(CameraImage image) async {
    final InputImage? inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }

    try {
      final objects = await _objectDetector.processImage(inputImage);
      if (mounted) {
        setState(() {
          _detectedObjects = objects;
        });
      }
    } catch (e) {
      debugPrint('ML Error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final sensorOrientation = _cameraController!.description.sensorOrientation;
    final InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final InputImageFormat? format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (format != InputImageFormat.yuv420 && format != InputImageFormat.bgra8888)) return null;

    if (image.planes.length != 1 && format == InputImageFormat.bgra8888) return null;
    if (image.planes.length != 3 && format == InputImageFormat.yuv420) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Future<void> _startLocationTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((position) {
      if (mounted) {
        context.read<ArBloc>().add(ArUpdateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
        ));
        _detectAttractionInView(position.heading);
      }
    });
  }

  void _detectAttractionInView(double heading) {
    final state = context.read<ArBloc>().state;
    if (state.attractions.isEmpty) return;

    AttractionEntity? closest;
    double closestDistance = double.infinity;

    for (final attraction in state.attractions) {
      final bearing = GeoCalculator.bearing(state.currentLatitude, state.currentLongitude, attraction.latitude, attraction.longitude);
      final distance = GeoCalculator.distance(state.currentLatitude, state.currentLongitude, attraction.latitude, attraction.longitude);

      double diff = (bearing - heading).abs();
      if (diff > 180) diff = 360 - diff;

      if (diff <= _detectionAngle && distance <= _detectionDistance) {
        if (distance < closestDistance) {
          closest = attraction;
          closestDistance = distance;
        }
      }
    }

    if (closest != null) {
      context.read<ArBloc>().add(ArDetectAttraction(closest, closestDistance));
    } else {
      context.read<ArBloc>().add(ArClearDetection());
    }
  }

  Future<void> _onMappingToggled(bool isMapping) async {
    if (isMapping) {
      // Get current position for geocoding
      try {
        final pos = await Geolocator.getCurrentPosition();
        final service = GeocodingService();
        final name = await service.getPlaceNameFromCoordinates(pos.latitude, pos.longitude);
        if (mounted && name != null) {
          setState(() {
            _placeNameController.text = name;
          });
        }
      } catch (_) {}
    } else {
      _placeNameController.clear();
      _descriptionController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocListener<ArBloc, ArState>(
        listenWhen: (prev, curr) => prev.isMappingMode != curr.isMappingMode,
        listener: (context, state) => _onMappingToggled(state.isMappingMode),
        child: BlocBuilder<ArBloc, ArState>(
          builder: (context, state) {
            return Stack(
              children: [
                // Layer 1: Camera Feed
                _buildCameraFeed(),

                // Layer 2: Subtle scan overlay
                _buildScanOverlay(),

                // Layer 3: AR POI markers in 3D space
                if (state.attractions.isNotEmpty) ..._buildArPOI(state),

                // Layer 4: Top-Left — Place Name Banner
                if (state.detectedAttraction != null) _buildPlaceNameBanner(state),

                // Layer 5: Left — Info Pills
                if (state.detectedAttraction != null) _buildInfoPills(state),

                // Layer 6: Right — Category Icons
                _buildCategoryIcons(state),

                // Layer 7: Top-Right — Status Bar
                _buildStatusBar(state),

                // Layer 8: Bottom — Distance + Address
                if (state.detectedAttraction != null) _buildDistanceBanner(state),

                // Layer 9: Bottom Dock
                _buildBottomDock(state),

                // Layer 10: AI Vision Result Overlay
                if (state.identifiedObject != null) _buildVisionResultOverlay(state),

                // Layer 11: Full Detail Sheet
                if (state.selectedAttraction != null) _buildDetailSheet(state),

                // Layer 12: Discovery Crosshair (Only in Mapping Mode)
                if (state.isMappingMode) _buildDiscoveryCrosshair(),

                // Layer 13: Mapping Form Overlay
                if (state.isMappingMode) _buildMappingOverlay(state),

                // Loading
                if (state.status == ArStatus.loading || state.isScanning)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─── Camera ────────────────────────────────────────────
  Widget _buildCameraFeed() {
    if (!_cameraInitialized || _cameraController == null) {
      // Fallback for web/simulator: Gradient background
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A237E).withOpacity(0.8),
              const Color(0xFF0D47A1).withOpacity(0.6),
              const Color(0xFF00695C).withOpacity(0.4),
            ],
          ),
        ),
        child: CustomPaint(painter: _ArGridPainter(), child: const SizedBox.expand()),
      );
    }
    return SizedBox.expand(child: CameraPreview(_cameraController!));
  }

  List<Widget> _buildDetectedObjects() {
    if (_detectedObjects.isEmpty || _cameraController == null || !_cameraInitialized) return [];

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    
    final previewH = _cameraController!.value.previewSize!.width;
    final previewW = _cameraController!.value.previewSize!.height;
    
    final scaleX = screenW / previewW;
    final scaleY = screenH / previewH;

    return _detectedObjects.map((obj) {
      final rect = obj.boundingBox;
      String label = 'OBJECT';
      if (obj.labels.isNotEmpty) {
        label = obj.labels.first.text.toUpperCase();
      }

      return Positioned(
        left: rect.left * scaleX,
        top: rect.top * scaleY,
        child: Container(
          width: rect.width * scaleX,
          height: rect.height * scaleY,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.neonGreen, width: 2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: AppColors.neonGreen.withOpacity(0.3), blurRadius: 15),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -30,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hub_rounded, color: Colors.black, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildScanOverlay() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, _) {
        return Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer circle
                Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                  ),
                ),
                // Inner circle
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
                  ),
                ),
                // Crosshair
                Icon(Icons.add, color: Colors.white.withOpacity(0.15), size: 20),
                // Sweep line
                Transform.rotate(
                  angle: _scanController.value * 2 * pi,
                  child: Container(
                    width: 1.5, height: 100,
                    alignment: Alignment.topCenter,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white.withOpacity(0.3), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Place Name Banner (Top-Left) ─────────────────────
  Widget _buildPlaceNameBanner(ArState state) {
    final place = state.detectedAttraction!;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      place.categoryName?.toUpperCase() ?? 'LANDMARK',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade().slideX(begin: -0.3, end: 0);
  }

  // ─── Info Pills (Left Side) ───────────────────────────
  Widget _buildInfoPills(ArState state) {
    final place = state.detectedAttraction!;
    final distance = state.detectedDistance;

    final pills = <_InfoPill>[
      _InfoPill(Icons.star_rounded, 'Rating', '${place.rating}/5'),
      _InfoPill(Icons.reviews_outlined, 'Reviews', '${place.reviewCount}'),
      _InfoPill(Icons.straighten_rounded, 'Distance', '${(distance / 1000).toStringAsFixed(1)} km'),
      if (place.categoryName != null)
        _InfoPill(Icons.category_outlined, 'Type', place.categoryName!),
    ];

    return Positioned(
      left: 20,
      top: MediaQuery.of(context).size.height * 0.25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: pills.asMap().entries.map((entry) {
          final pill = entry.value;
          final delay = entry.key * 100;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pill.icon, color: AppColors.secondary, size: 16),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pill.label,
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          Text(
                            pill.value,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fade(delay: Duration(milliseconds: delay)).slideX(begin: -0.3, end: 0);
        }).toList(),
      ),
    );
  }

  // ─── Category Icons (Right Side) ──────────────────────
  Widget _buildCategoryIcons(ArState state) {
    final icons = [
      _CategoryIcon(Icons.temple_buddhist_rounded, 'Heritage'),
      _CategoryIcon(Icons.restaurant_rounded, 'Food'),
      _CategoryIcon(Icons.park_rounded, 'Nature'),
      _CategoryIcon(Icons.hotel_rounded, 'Stay'),
      _CategoryIcon(Icons.photo_camera_rounded, 'Photo'),
    ];

    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.22,
      child: Column(
        children: icons.asMap().entries.map((entry) {
          final icon = entry.value;
          final delay = entry.key * 80;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: icon.label,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Icon(icon.icon, color: Colors.white.withOpacity(0.7), size: 20),
                  ),
                ),
              ),
            ),
          ).animate().fade(delay: Duration(milliseconds: 400 + delay)).slideX(begin: 0.3, end: 0);
        }).toList(),
      ),
    );
  }

  // ─── Status Bar (Top-Right) ───────────────────────────
  Widget _buildStatusBar(ArState state) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.radar_rounded, color: AppColors.secondary, size: 14),
                const SizedBox(width: 8),
                Text(
                  state.attractions.isEmpty ? 'SCANNING...' : '${state.attractions.length} NEARBY',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade().slideY(begin: -0.2, end: 0);
  }

  // ─── Distance Banner (Bottom) ─────────────────────────
  Widget _buildDistanceBanner(ArState state) {
    final distance = state.detectedDistance;
    final distanceStr = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} KM'
        : '${distance.toInt()} M';

    return Positioned(
      bottom: 180,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                Text(
                  '$distanceStr from your location',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on_outlined, color: Colors.white.withOpacity(0.5), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _currentAddress,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    // Navigate to the detail page
                    if (state.detectedAttraction != null) {
                      context.read<ArBloc>().add(ArSelectAttraction(state.detectedAttraction));
                    }
                  },
                  child: Text(
                    'View Full Details',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 0.5, end: 0, duration: 500.ms);
  }

  // ─── Bottom Action Dock ───────────────────────────────
  Widget _buildBottomDock(ArState state) {
    return Positioned(
      bottom: 110,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Back Button
          _buildDockButton(Icons.arrow_back_rounded, 'Back', () => Navigator.pop(context)),
          const SizedBox(width: 16),
          // AR Mode (active)
          _buildDockButton(
            Icons.view_in_ar_rounded, 
            'AR', 
            state.isMappingMode ? () => context.read<ArBloc>().add(ArToggleMappingMode()) : null, 
            isActive: !state.isMappingMode
          ),
          const SizedBox(width: 16),
          // Central Button
          GestureDetector(
            onTap: state.isMappingMode 
              ? null // Handled by the overlay "Lock" button
              : (state.isScanning ? null : _captureAndScan),
            child: Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: state.isMappingMode ? AppColors.secondary : AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (state.isMappingMode ? AppColors.secondary : AppColors.primary).withOpacity(0.4), 
                    blurRadius: 20, 
                    offset: const Offset(0, 10)
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(
                state.isMappingMode ? Icons.add_location_alt_rounded : (state.isScanning ? Icons.sync_rounded : Icons.camera_rounded), 
                color: state.isMappingMode ? Colors.black : Colors.white, 
                size: 32
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
          const SizedBox(width: 16),
          // Mapping Mode Toggle
          _buildDockButton(
            Icons.map_rounded, 
            'Map', 
            () => context.read<ArBloc>().add(ArToggleMappingMode()),
            isActive: state.isMappingMode
          ),
        ],
      ),
    ).animate().fade(delay: 300.ms).slideY(begin: 0.5, end: 0);
  }

  Future<void> _captureAndScan() async {
    if (_cameraController == null || !_cameraInitialized) return;

    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      if (mounted) {
        context.read<ArBloc>().add(ArVisualScan(bytes.toList()));
      }
    } catch (e) {
      // Handle capture error
    }
  }

  Widget _buildVisionResultOverlay(ArState state) {
    final obj = state.identifiedObject!;
    return Positioned(
      top: 120,
      left: 24,
      right: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.secondary.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 40),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: const Text('AI VISION', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textTertiary),
                      onPressed: () => context.read<ArBloc>().add(const ArSelectAttraction(null)),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  obj['object_name'] ?? 'Identified Object',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  obj['category']?.toString().toUpperCase() ?? 'LANDMARK',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1.5),
                ),
                const SizedBox(height: 16),
                Text(
                  obj['significance'] ?? '',
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          obj['interesting_fact'] ?? '',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack).fade();
  }

  Widget _buildDockButton(IconData icon, String label, VoidCallback? onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: isActive 
                ? AppColors.primary.withOpacity(0.8) 
                : Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  // ─── AR POI Markers ──────────────────────────────────
  List<Widget> _buildArPOI(ArState state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return state.attractions.take(6).map((point) {
      final bearing = GeoCalculator.bearing(state.currentLatitude, state.currentLongitude, point.latitude, point.longitude);
      final angle = (bearing - state.currentHeading) * pi / 180;
      
      final x = screenWidth / 2 + (screenWidth * 0.4 * sin(angle));
      final y = screenHeight * 0.35 + (bearing % 20) * 8;
      
      final isDetected = state.detectedAttraction?.id == point.id;

      return Positioned(
        left: x - 30,
        top: y - 30,
        child: GestureDetector(
          onTap: () => context.read<ArBloc>().add(ArSelectAttraction(point)),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: AnimatedContainer(
                    duration: 300.ms,
                    width: isDetected ? 50 : 40,
                    height: isDetected ? 50 : 40,
                    decoration: BoxDecoration(
                      color: isDetected 
                        ? AppColors.primary.withOpacity(0.8) 
                        : Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDetected ? AppColors.secondary : Colors.white.withOpacity(0.2),
                        width: isDetected ? 2 : 1,
                      ),
                      boxShadow: isDetected ? [
                        BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12),
                      ] : null,
                    ),
                    child: Icon(
                      Icons.place_rounded,
                      color: isDetected ? Colors.white : Colors.white.withOpacity(0.7),
                      size: isDetected ? 24 : 18,
                    ),
                  ),
                ),
              ),
              if (isDetected) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    point.name.length > 16 ? '${point.name.substring(0, 16)}...' : point.name,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ).animate().fade().slideY(begin: 0.5, end: 0),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  // ─── Detail Sheet ─────────────────────────────────────
  Widget _buildDetailSheet(ArState state) {
    final point = state.selectedAttraction!;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),

                // Header Row
                Row(
                  children: [
                    if (point.photoUrls.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(point.photoUrls.first, width: 64, height: 64, fit: BoxFit.cover),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            point.name,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${point.rating} ⭐  ·  ${point.categoryName ?? 'Attraction'}',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
                      onPressed: () => context.read<ArBloc>().add(const ArSelectAttraction(null)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // AI Insight
                if (state.isLoadingInsight)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(
                      color: AppColors.primary,
                      backgroundColor: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      state.aiInsight ?? 'Tap "Discover" to learn AI-curated secrets about this place.',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.6),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 20),

                // Action Row
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.read<ArBloc>().add(ArFetchAIInsight(point)),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('DISCOVER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: AppColors.primary.withOpacity(0.3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, color: AppColors.primary, size: 20),
                        onPressed: () {
                          Navigator.push(
                            context,
                              MaterialPageRoute(builder: (_) => AttractionDetailPage(
                                name: point.name,
                                category: point.categoryName ?? 'Attraction',
                                rating: point.rating,
                                distance: '${((point.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                                emoji: '🏛',
                                imageUrl: point.photoUrls.isNotEmpty ? point.photoUrls.first : '',
                              )),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutQuart);
  }
  Widget _buildDiscoveryCrosshair() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 2),
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 2.seconds),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.secondary, width: 2),
              shape: BoxShape.circle,
            ),
          ),
          Container(width: 2, height: 20, color: AppColors.secondary),
          Container(width: 20, height: 2, color: AppColors.secondary),
        ],
      ),
    ).animate().fade().scale(begin: const Offset(2, 2));
  }

  Widget _buildMappingOverlay(ArState state) {
    return Positioned(
      bottom: 200,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DISCOVER NEW PLACE',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _placeNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Place Name',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _discoveryCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final cat = _discoveryCategories[index];
                      final isSelected = _selectedCategoryId == cat['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategoryId = cat['id']),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.secondary : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              cat['label'],
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: state.isSavingDiscovery ? null : () {
                      context.read<ArBloc>().add(ArSubmitDiscovery(
                        name: _placeNameController.text,
                        description: _descriptionController.text,
                        categoryId: _selectedCategoryId,
                        latitude: state.currentLatitude,
                        longitude: state.currentLongitude,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: state.isSavingDiscovery
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('LOCK SPATIAL ANCHOR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 0.5, end: 0);
  }
}

// ─── Data Classes ─────────────────────────────────────────
class _InfoPill {
  final IconData icon;
  final String label;
  final String value;
  const _InfoPill(this.icon, this.label, this.value);
}

class _CategoryIcon {
  final IconData icon;
  final String label;
  const _CategoryIcon(this.icon, this.label);
}

// ─── Background Painter ──────────────────────────────────
class _ArGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;

    const spacing = 50.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Perspective lines from center
    final cx = size.width / 2;
    final cy = size.height / 2;
    final perspPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 0.5;

    for (var i = 0; i < 12; i++) {
      final angle = i * pi / 6;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + cos(angle) * size.width, cy + sin(angle) * size.height),
        perspPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
