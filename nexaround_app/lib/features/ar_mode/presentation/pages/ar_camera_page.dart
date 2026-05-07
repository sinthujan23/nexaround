import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';

class ArCameraPage extends StatefulWidget {
  const ArCameraPage({super.key});

  @override
  State<ArCameraPage> createState() => _ArCameraPageState();
}

class _ArCameraPageState extends State<ArCameraPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _showInfoCard = false;
  int _selectedLandmark = -1;
  String _arMode = 'explore'; // explore, navigate, photo, mapping
  int _nexusPoints = 1250;
  bool _isMapping = false;
  bool _isSavingMapping = false;
  String _selectedCategory = 'HIDDEN';
  final TextEditingController _newPlaceController = TextEditingController();
  final TextEditingController _newPlaceDescriptionController = TextEditingController();
  
  // Navigation State
  bool _isNavigating = false;
  _ArLandmark? _navigationTarget;
  double _distanceToTarget = 0.0;
  bool _isListening = false;

  // Discovery State
  bool _isIdentifying = false;
  String _selectedDiscoveryType = 'HERITAGE';
  final List<Map<String, dynamic>> _discoveryTypes = [
    {'id': 'HERITAGE', 'icon': Icons.account_balance_rounded, 'label': 'Heritage'},
    {'id': 'ANCIENT', 'icon': Icons.fort_rounded, 'label': 'Ancient'},
    {'id': 'MUSEUM', 'icon': Icons.museum_rounded, 'label': 'Museum'},
    {'id': 'MONUMENT', 'icon': Icons.temple_buddhist_rounded, 'label': 'Monument'},
    {'id': 'HIDDEN', 'icon': Icons.vignette_rounded, 'label': 'Hidden Gem'},
  ];
  
  _ArLandmark? _identifiedPlace;
  bool _isNevaAnalyzing = false;

  // ═══════════════════════════════════════
  // AR DISCOVERY MODE - Automatic Silent Capture
  // ═══════════════════════════════════════
  bool _arDiscoveryEnabled = false;
  bool _isArDiscoveryActive = false;
  Map<String, dynamic>? _arDiscoveryResult;
  _ArLandmark? _arDiscoveryTarget;
  Timer? _arDiscoveryTimer;
  geo.Position? _currentPosition;
  static const double _arDiscoveryMaxDistance = 100.0; // 100m - extremely close
  static const int _arDiscoveryCaptureDelay = 3000; // 3 seconds of stable view before capture

  StreamSubscription<CompassEvent>? _compassSubscription;
  double _heading = 0.0;
  List<_ArLandmark> _landmarks = [];
  bool _minimalHud = false;
  bool _isCapturing = false;

  final List<Map<String, dynamic>> _mappingCategories = [
    {'id': 'HERITAGE', 'icon': Icons.account_balance_rounded, 'label': 'Heritage'},
    {'id': 'DINING', 'icon': Icons.restaurant_rounded, 'label': 'Dining'},
    {'id': 'VIEWPOINT', 'icon': Icons.photo_camera_rounded, 'label': 'Viewpoint'},
    {'id': 'SECRET', 'icon': Icons.vpn_key_rounded, 'label': 'Secret Spot'},
    {'id': 'NATURE', 'icon': Icons.park_rounded, 'label': 'Nature'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _fetchLivePlaces();
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted) setState(() => _heading = event.heading ?? 0.0);
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _controller?.dispose();
    _newPlaceController.dispose();
    _newPlaceDescriptionController.dispose();
    _arDiscoveryTimer?.cancel();
    super.dispose();
  }

  double _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    var lat1 = startLat * pi / 180;
    var lat2 = endLat * pi / 180;
    var dLon = (endLng - startLng) * pi / 180;

    var y = sin(dLon) * cos(lat2);
    var x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    var brng = atan2(y, x);

    return (brng * 180 / pi + 360) % 360;
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      // Set flash mode to off by default
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera Error: $e');
    }
  }

  Future<void> _handleIdentify() async {
    if (_isNevaAnalyzing || _controller == null || !_isCameraReady) return;
    
    setState(() {
      _isCapturing = true;
      _isNevaAnalyzing = true;
    });

    try {
      // 1. Capture real image from camera
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      
      setState(() => _isCapturing = false);

      // 2. Call backend for AI Vision identification
      final repository = getIt<AttractionRepository>();
      final result = await repository.identifyPlace(bytes.toList());

      result.fold(
        (failure) {
          debugPrint('Identification Failure: ${failure.message}');
          if (mounted) setState(() => _isNevaAnalyzing = false);
        },
        (data) {
          // 4. Map backend response to AR Landmark
          final landmark = _mapToLandmark(data);

          if (mounted) {
            setState(() {
              _isNevaAnalyzing = false;
              _identifiedPlace = landmark;
              _showInfoCard = true;
              
              // Only add if it's not already in the list (simple check)
              if (!_landmarks.any((l) => l.name == landmark.name)) {
                _landmarks.add(landmark);
              }
              _selectedLandmark = _landmarks.indexWhere((l) => l.name == landmark.name);
              _isListening = true;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('AR Identification Error: $e');
      if (mounted) setState(() => _isNevaAnalyzing = false);
    }
  }

  _ArLandmark _mapToLandmark(Map<String, dynamic> data) {
    final String name = data['object_name'] ?? 'Discovery';
    
    final metadataStrings = [
      'Identified via Google Lens visual search.',
      'Identified via Google reverse image search.',
      'Identified via Google visual search.',
      'Extracted from Google Lens visual data.',
      'Free, real-time visual identification.',
      'Free visual search powered by Google.',
      'Free visual search.',
    ];
    
    String _clean(String? text) {
      if (text == null || text.isEmpty) return '';
      for (var m in metadataStrings) {
        text = text!.replaceAll(m, '');
      }
      if (text!.startsWith('Identified as:')) text = text.replaceFirst('Identified as:', '');
      return text.trim();
    }
    
    final parts = [
      _clean(data['significance']),
      _clean(data['interesting_fact']),
      _clean(data['real_time_info']),
    ].where((s) => s.isNotEmpty).toList();
    
    final String desc = parts.isNotEmpty 
        ? parts.join('\n\n') 
        : 'Neva identified this as $name. Tap "Ask Neva" for more details about this discovery.';
    
    return _ArLandmark(
      name,
      'https://images.unsplash.com/photo-1564507592333-c60657eaa0ae?q=80&w=1000&auto=format&fit=crop',
      4.8,
      'Detected',
      _heading,
      desc,
      data['category'] ?? 'LANDMARK',
      0,
      _currentPosition?.latitude ?? 0.0,
      _currentPosition?.longitude ?? 0.0
    );
  }

  static const int _maxVisibleMarkers = 25;
  static const int _maxVisibleOnScreen = 5;
  static const List<int> _searchRadii = [100, 1000, 2000, 5000, 10000, 20000];

  Future<void> _fetchLivePlaces() async {
    try {
      final pos = await geo.Geolocator.getCurrentPosition();
      List<_ArLandmark> collected = [];

      for (final radius in _searchRadii) {
        debugPrint('🔍 AR: Searching radius $radius m...');
        final places = await GooglePlacesService.fetchNearbyPlaces(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radius: radius,
        );

        for (final p in places) {
          if (collected.any((l) => l.name == p.name)) continue;

          final rawDistM = (p.distanceM ?? 0).toDouble();
          
          // Only filter if we actually have distance data from API
          if (p.distanceM != null && rawDistM > (radius * 1.5)) continue;

          final bearing = _calculateBearing(pos.latitude, pos.longitude, p.latitude, p.longitude);
          final distKm = rawDistM / 1000;
          final distStr = distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';
          
          collected.add(_ArLandmark(
            p.name,
            p.photoUrls.isNotEmpty ? p.photoUrls.first : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop',
            p.rating,
            distStr,
            bearing,
            'A remarkable location nearby!',
            p.categoryName?.toUpperCase() ?? 'ATTRACTION',
            rawDistM,
            p.latitude,
            p.longitude,
          ));
        }

        debugPrint('📍 AR: ${collected.length} places so far at $radius m tier.');
        if (collected.length >= _maxVisibleMarkers) break;
      }

      // Sort by distance (closest first)
      collected.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      
      if (collected.length > _maxVisibleMarkers) {
        collected = collected.sublist(0, _maxVisibleMarkers);
      }

      if (mounted) setState(() => _landmarks = collected);
      
      // Also update current position for AR discovery
      final pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (e) {
      debugPrint('AR places error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // AR DISCOVERY MODE - Automatic Silent Capture with Gemini
  // ════════════════════════════════════════════════════════════════
  
  /// Start AR Discovery mode - monitors compass and auto-captures close places
  void _startArDiscovery() {
    if (_arDiscoveryEnabled) return;
    
    setState(() {
      _arDiscoveryEnabled = true;
      _isArDiscoveryActive = true;
      _arDiscoveryResult = null;
      _arDiscoveryTarget = null;
    });
    
    // Get current position
    _updateCurrentPosition();
    
    // Start periodic check for close places in view
    _arDiscoveryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkForClosePlaceInView();
    });
    
    debugPrint('🔮 AR Discovery Mode Activated');
  }
  
  /// Stop AR Discovery mode
  void _stopArDiscovery() {
    _arDiscoveryTimer?.cancel();
    _arDiscoveryTimer = null;
    
    if (mounted) {
      setState(() {
        _arDiscoveryEnabled = false;
        _isArDiscoveryActive = false;
        _arDiscoveryTarget = null;
      });
    }
    
    debugPrint('🔮 AR Discovery Mode Deactivated');
  }
  
  /// Update current GPS position
  Future<void> _updateCurrentPosition() async {
    try {
      final pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (e) {
      debugPrint('Position error: $e');
    }
  }
  
  /// Check if there's an extremely close place in the current camera view
  void _checkForClosePlaceInView() {
    if (!_arDiscoveryEnabled || _isNevaAnalyzing || _currentPosition == null) return;
    
    _ArLandmark? closestInView;
    double closestDist = double.infinity;
    
    for (final lm in _landmarks) {
      // Calculate if place is in current camera view (±30° from heading)
      double diff = lm.bearing - _heading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      
      // Check if within camera FOV (approximately 60° field of view)
      final isInView = diff.abs() < 30;
      
      // Check if extremely close (within 100m)
      final isClose = lm.distanceM <= _arDiscoveryMaxDistance;
      
      if (isInView && isClose && lm.distanceM < closestDist) {
        closestDist = lm.distanceM;
        closestInView = lm;
      }
    }
    
    // Update target if found
    if (closestInView != null && closestInView != _arDiscoveryTarget) {
      setState(() => _arDiscoveryTarget = closestInView);
      // Trigger silent capture after a short delay
      _triggerSilentCapture(closestInView);
    } else if (closestInView == null && _arDiscoveryTarget != null) {
      // Clear target if no close place in view
      setState(() => _arDiscoveryTarget = null);
    }
  }
  
  /// Silently capture image and send to Gemini for analysis
  /// No UI feedback - user doesn't know image is being captured
  Future<void> _triggerSilentCapture(_ArLandmark target) async {
    if (_controller == null || !_isCameraReady || _isNevaAnalyzing) return;
    
    debugPrint('🔮 Silent capture triggered for: ${target.name}');
    
    // Set analyzing state (but don't show any UI feedback)
    setState(() => _isNevaAnalyzing = true);
    
    try {
      // 1. Capture image silently (no flash, no sound)
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      
      debugPrint('🔮 Image captured silently, sending to Gemini...');
      
      // 2. Send directly to Gemini Vision API
      final rawResponse = await GeminiService().identifyPlace(
        imageBytes: bytes,
        latitude: _currentPosition?.latitude ?? target.lat ?? 0,
        longitude: _currentPosition?.longitude ?? target.lng ?? 0,
      );
      
      // 3. Parse JSON response
      String jsonStr = rawResponse.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```json?\n?'), '').replaceAll(RegExp(r'\n?```\$'), '');
      }
      
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      debugPrint('🔮 Gemini Response: $result');
      
      // 4. Store result and show discovery card
      if (mounted) {
        setState(() {
          _arDiscoveryResult = result;
          _isNevaAnalyzing = false;
          _isArDiscoveryActive = false; // Stop active scanning after discovery
        });
      }
      
    } catch (e) {
      debugPrint('🔮 Silent capture error: $e');
      if (mounted) {
        setState(() {
          _isNevaAnalyzing = false;
        });
      }
    }
  }
  
  /// Build AR Discovery result card
  Widget _buildArDiscoveryResultCard() {
    if (_arDiscoveryResult == null) return const SizedBox.shrink();
    
    final result = _arDiscoveryResult!;
    final name = result['name'] ?? 'Unknown Place';
    final category = result['category'] ?? 'Place';
    final description = result['description'] ?? '';
    final funFact = result['fun_fact'] ?? '';
    final tips = result['tips'] ?? '';
    final confidence = ((result['confidence'] ?? 0.7) * 100).toInt();
    
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.98),
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 30),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.green, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'DISCOVERED',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _arDiscoveryResult = null;
                      _isArDiscoveryActive = true; // Resume scanning
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Place name and category
            Text(
              name,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$confidence% match',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Description
            if (description.isNotEmpty) ...[
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Fun Fact
            if (funFact.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FUN FACT',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            funFact,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Tips
            if (tips.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VISITOR TIP',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tips,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // Navigate to the place
                      if (_arDiscoveryTarget != null) {
                        setState(() {
                          _navigationTarget = _arDiscoveryTarget;
                          _isNavigating = true;
                          _arDiscoveryResult = null;
                        });
                      }
                    },
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'NAVIGATE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    // Ask Neva for more details
                    if (_arDiscoveryTarget != null) {
                      HomePage.homeKey.currentState?.switchToNeva(
                        'Tell me more about ${_arDiscoveryTarget!.name}',
                      );
                    }
                  },
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: _buildNevaAvatar(32),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutCubic);
  }
  
  /// Build AR Discovery target indicator (subtle, non-intrusive)
  Widget _buildArDiscoveryIndicator() {
    if (!_arDiscoveryEnabled || !_isArDiscoveryActive || _arDiscoveryTarget == null) {
      return const SizedBox.shrink();
    }
    
    final target = _arDiscoveryTarget!;
    
    // Very subtle indicator - just a small pulse at the bottom
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.primary, blurRadius: 8),
                  ],
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
               .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 800.ms),
              const SizedBox(width: 10),
              Text(
                target.distance,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• ${target.name}',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(duration: 300.ms);
  }
  
  /// Build AR Discovery mode toggle button
  Widget _buildArDiscoveryToggle() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            if (_arDiscoveryEnabled) {
              _stopArDiscovery();
            } else {
              _startArDiscovery();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: _arDiscoveryEnabled 
                  ? AppColors.primary.withOpacity(0.2)
                  : Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _arDiscoveryEnabled 
                    ? AppColors.primary
                    : Colors.white24,
                width: _arDiscoveryEnabled ? 2 : 1,
              ),
              boxShadow: _arDiscoveryEnabled
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15)]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _arDiscoveryEnabled ? Icons.auto_awesome : Icons.explore_rounded,
                  color: _arDiscoveryEnabled ? AppColors.primary : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _arDiscoveryEnabled ? 'AR DISCOVERY ON' : 'START AR DISCOVERY',
                  style: TextStyle(
                    color: _arDiscoveryEnabled ? AppColors.primary : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 300.ms);
  }

  // ── SCAN LINE PAINTER ──
  Widget _buildScanLines() {
    return Positioned.fill(
      child: IgnorePointer(
        child: _AnimatedScanLines(),
      ),
    );
  }

  // ── DATA PARTICLES ──
  Widget _buildDataParticles() {
    return Positioned.fill(
      child: IgnorePointer(
        child: _ParticleField(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Live camera feed
          _buildCameraBackground(),

          // Removed subtle scan line wave effect as requested
          
          // EXPLORE MODE: Floating AR markers (compass-driven)
          if (!_isNavigating && !_isIdentifying)
            ..._landmarks.asMap().entries.map((e) => _buildLandmarkMarker(e.key, e.value)),

          // DISCOVER MODE: Show single closest place with lock-on animation
          if (_isIdentifying && !_showInfoCard && !_isNevaAnalyzing)
            _buildDiscoveryTarget(),

          // Top HUD (XP and Map Place) - HIDE IF NAVIGATING
          if (!_minimalHud && !_isNavigating) _buildTopHUD(),

          // Place count/Status badge at bottom - HIDE IF NAVIGATING
          if (!_minimalHud && !_isNavigating && !_isIdentifying) 
            Positioned(
              top: 190,
              left: 0,
              right: 0,
              child: Center(child: _buildXPBadge()),
            ),

          // Expanded detail card
          if (_showInfoCard && _selectedLandmark >= 0 && _selectedLandmark < _landmarks.length) ...[
            _buildInfoCard(_landmarks[_selectedLandmark]),
            Positioned(
              left: 25, 
              top: 70,
              child: GestureDetector(
                onTap: () {
                  final landmark = _landmarks[_selectedLandmark];
                  HomePage.homeKey.currentState?.switchToNeva('Tell me more about the ${landmark.name}');
                },
                child: Column(
                  children: [
                    _buildNevaAvatar(60)
                     .animate(onPlay: (c) => c.repeat(reverse: true))
                     .moveY(begin: -5, end: 5, duration: 2.seconds, curve: Curves.easeInOut)
                     .shimmer(duration: 3.seconds, color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black, 
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1),
                      ),
                      child: const Text('ASK NEVA', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds),
                  ],
                ),
              ),
            ).animate().fade().scale(begin: const Offset(0.5, 0.5)),
          ],

          // DISCOVERY CROSSHAIR (Only in Mapping Mode)
          if (_isMapping) _buildDiscoveryCrosshair(),
          if (_isMapping) _buildMappingOverlay(),

          // NEVA DISCOVERY MODE - Analysis overlay only
          if (_isNevaAnalyzing) _buildNevaAnalysisOverlay(),

          // MODE SELECTOR (Explore vs Discover)
          if (!_isMapping && !_isNavigating && !_showInfoCard) _buildModeSelector(),

          // DISCOVERY CATEGORY SELECTOR (Top Filter)
          if (_isIdentifying && !_showInfoCard && !_isNevaAnalyzing) _buildDiscoveryCategorySelector(),


          // CAMERA FLASH EFFECT
          if (_isCapturing)
            Positioned.fill(
              child: Container(color: Colors.white).animate().fade(duration: 200.ms, begin: 0, end: 0.8).then().fade(duration: 400.ms, begin: 0.8, end: 0),
            ),

          // NAVIGATION OVERLAY
          if (_isNavigating && _navigationTarget != null)
            _buildNavigationOverlay(),

          // ═══════════════════════════════════════════════════════════
          // AR DISCOVERY MODE - Automatic Silent Capture
          // ═══════════════════════════════════════════════════════════
          
          // AR Discovery Toggle Button (only when not navigating/mapping/showing info)
          if (!_isNavigating && !_isMapping && !_showInfoCard && !_isIdentifying)
            _buildArDiscoveryToggle(),
          
          // AR Discovery Target Indicator (subtle, non-intrusive)
          if (_arDiscoveryEnabled && _isArDiscoveryActive && _arDiscoveryTarget != null && !_isNevaAnalyzing)
            _buildArDiscoveryIndicator(),
          
          // AR Discovery Result Card
          if (_arDiscoveryResult != null)
            _buildArDiscoveryResultCard(),
        ],
      ),
    );
  }

  Widget _buildTopHUD() {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // AR Active Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.1), blurRadius: 15)],
            ),
            child: Row(
              children: [
                const Text('AR ACTIVE', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 1, height: 16, color: Colors.white24,
                ),
                const Icon(Icons.stars_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 6),
                const Text('1300 XP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 4.seconds),
          // Exit AR Button
          GestureDetector(
            onTap: () => HomePage.homeKey.currentState?.switchToExplore(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXPBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
      ),
      child: const Text(
        'SPATIAL DISCOVERY ACTIVE',
        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.5, end: 1.0, duration: 1500.ms);
  }

  Widget _buildCameraBackground() {
    if (!_isCameraReady || _controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white24),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize!.height,
          height: _controller!.value.previewSize!.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  // Tracks how many markers are currently visible on screen
  int _visibleCount = 0;

  Widget _buildLandmarkMarker(int index, _ArLandmark landmark) {
    // Reset visible counter at the start of each build cycle
    if (index == 0) _visibleCount = 0;

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    // Horizontal position based on compass bearing
    double diff = landmark.bearing - _heading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    double dx = 0.5 + (diff / 60);

    // Skip if not in current camera view
    if (dx < -0.3 || dx > 1.3) return const SizedBox.shrink();

    // Cap at 5 visible markers in the current direction
    if (_visibleCount >= _maxVisibleOnScreen) return const SizedBox.shrink();

    int currentSlot = _visibleCount;
    _visibleCount++;

    // === POSITION CALCULATIONS ===
    const double topStart = 270.0;
    const double rowHeight = 100.0;
    const double cardW = 280.0;

    double topPos = topStart + (currentSlot * rowHeight);
    double leftPos = (screenW * dx) - (cardW / 2);
    leftPos = leftPos.clamp(12.0, screenW - cardW - 12.0);

    // Slight alternating offset
    if (currentSlot % 2 == 1) {
      leftPos = (leftPos + 25).clamp(12.0, screenW - cardW - 12.0);
    }

    return Positioned(
      left: leftPos,
      top: topPos,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedLandmark = index;
            _showInfoCard = true;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            // --- Holographic Background Plate ---
            Container(
              width: cardW,
              height: 75,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(5),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, spreadRadius: -5),
                  if (_selectedLandmark == index)
                    BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 30, spreadRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                  topRight: Radius.circular(5),
                  bottomLeft: Radius.circular(5),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      border: Border.all(
                        color: _selectedLandmark == index ? AppColors.primary : AppColors.primary.withOpacity(0.3),
                        width: _selectedLandmark == index ? 2.0 : 1.2,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withOpacity(0.1),
                          Colors.transparent,
                          Colors.black.withOpacity(0.2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- Floating Hex-Core Image ---
            Positioned(
              left: -15,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer scanning ring
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).rotate(duration: 5.seconds),
                  
                  // The Image Core
                  Container(
                    width: 54, height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 15)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(27),
                      child: _buildMarkerImage(landmark),
                    ),
                  ),
                ],
              ),
            ),

            // --- Holographic Content ---
            Container(
              width: cardW,
              padding: const EdgeInsets.only(left: 60, right: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary, blurRadius: 5)]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        landmark.category.toUpperCase(),
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    landmark.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildMetaBadge(Icons.star_rounded, '${landmark.rating}', Colors.amber),
                      const SizedBox(width: 15),
                      _buildMetaBadge(Icons.radar_rounded, landmark.distance, AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),

            if (currentSlot == 0)
              Positioned(
                top: -12, right: 15,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 12)],
                  ),
                  child: const Text(
                    'OPTIMAL PATH',
                    style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 1.5.seconds),
              ),
          ],
        ),
      ),
    ).animate().fade(duration: 400.ms).moveX(begin: -30, end: 0, curve: Curves.easeOutBack);
  }

  Widget _buildDiscoveryTarget() {
    // Find the single closest place in the current camera direction
    _ArLandmark? closestInView;
    double closestDist = double.infinity;
    int closestIndex = -1;

    for (int i = 0; i < _landmarks.length; i++) {
      final lm = _landmarks[i];
      
      // FILTER BY SELECTED CATEGORY
      bool matchesFilter = false;
      final cat = lm.category.toLowerCase();
      final filter = _selectedDiscoveryCategory.toLowerCase();
      
      if (filter == 'all') {
        matchesFilter = true;
      } else if (filter == 'historical') {
        matchesFilter = cat.contains('history') || cat.contains('museum') || cat.contains('culture') || 
                        cat.contains('temple') || cat.contains('monument') || cat.contains('church') || 
                        cat.contains('place_of_worship') || cat.contains('art_gallery');
      } else if (filter == 'attractions') {
        matchesFilter = cat.contains('attraction') || cat.contains('park') || cat.contains('landmark') || 
                        cat.contains('point_of_interest') || cat.contains('zoo') || cat.contains('aquarium') ||
                        cat.contains('amusement');
      } else if (filter == 'food') {
        matchesFilter = cat.contains('food') || cat.contains('restaurant') || cat.contains('cafe') || 
                        cat.contains('bakery') || cat.contains('bar') || cat.contains('meal');
      } else if (filter == 'shopping') {
        matchesFilter = cat.contains('shop') || cat.contains('store') || cat.contains('mall') || 
                        cat.contains('clothing') || cat.contains('market');
      } else {
        matchesFilter = cat.contains(filter);
      }

      if (!matchesFilter) continue;

      double diff = lm.bearing - _heading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      double dx = 0.5 + (diff / 60);

      // Must be within the camera FOV
      if (dx < 0.1 || dx > 0.9) continue;

      // Pick the closest one by distance
      if (lm.distanceM < closestDist) {
        closestDist = lm.distanceM;
        closestInView = lm;
        closestIndex = i;
      }
    }

    if (closestInView == null) {
      // Nothing in view — show "Scanning" prompt (Text only)
      return Positioned.fill(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 120), // Offset from center
              Text(
                'SCANNING ENVIRONMENT...',
                style: TextStyle(color: AppColors.primary.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, end: 1, duration: 1.seconds),
              const SizedBox(height: 6)
            ],
          ),
        ),
      );
    }

    // We have a target — show only the info panel
    final landmark = closestInView;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedLandmark = closestIndex;
            _showInfoCard = true;
          });
        },
        child: Stack(
          children: [
            // === INFO PANEL (bottom) ===
            Positioned(
              bottom: 220,
              left: 30, right: 30,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.black.withOpacity(0.85),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30),
                    BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 20),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Category + Distance row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary, blurRadius: 6)]),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              landmark.category.toUpperCase(),
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 2),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.radar_rounded, color: AppColors.primary, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                landmark.distance,
                                style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Image + Details Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Small Thumbnail
                        Container(
                          width: 80, height: 80,
                          child: PlaceImageHelper.buildPlaceImage(
                            imagePath: landmark.imagePath,
                            category: landmark.category,
                            name: landmark.name,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Name and rating
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                landmark.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, height: 1.1),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ...List.generate(5, (i) => Icon(
                                    i < landmark.rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: Colors.amber,
                                    size: 14,
                                  )),
                                  const SizedBox(width: 6),
                                  Text('${landmark.rating}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      landmark.description.isNotEmpty
                          ? landmark.description
                          : 'Neva has identified this location. Tap to unlock the full AI-powered analysis and discover its history, significance, and visitor insights.',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6), height: 1.5, fontWeight: FontWeight.w400),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),

                    // Action hint
                    Center(
                      child: Text(
                        'TAP ANYWHERE TO EXPLORE →',
                        style: TextStyle(color: AppColors.primary.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.4, end: 1, duration: 1.seconds),
                    ),
                  ],
                ),
              ).animate().slideY(begin: 0.3, end: 0, duration: 600.ms, curve: Curves.easeOutCubic).fade(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkerImage(_ArLandmark landmark) {
    return PlaceImageHelper.buildPlaceImage(
      imagePath: landmark.imagePath, 
      category: landmark.category, 
      name: landmark.name,
    );
  }


  Widget _buildMetaBadge(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildInfoCard(_ArLandmark landmark) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85, 
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.85),
              Colors.black.withOpacity(0.98),
            ],
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 40, 30, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              landmark.name.toUpperCase(),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                '✨ AI VERIFIED ${landmark.category.toUpperCase()} • ${landmark.distance}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final map = {
                                'id': landmark.name.hashCode.toString(),
                                'name': landmark.name,
                                'category_name': landmark.category,
                                'rating': landmark.rating,
                                'photo_urls': [landmark.imagePath],
                                'latitude': landmark.lat ?? 0.0,
                                'longitude': landmark.lng ?? 0.0,
                                'created_at': DateTime.now().toIso8601String(),
                              };
                              await CacheService.toggleSavedPlace(map);
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle, 
                                color: CacheService.isPlaceSaved(landmark.name.hashCode.toString()) 
                                    ? AppColors.primary.withOpacity(0.2) 
                                    : Colors.white10
                              ),
                              child: Icon(
                                CacheService.isPlaceSaved(landmark.name.hashCode.toString()) 
                                    ? Icons.favorite_rounded 
                                    : Icons.favorite_outline_rounded, 
                                color: CacheService.isPlaceSaved(landmark.name.hashCode.toString()) 
                                    ? AppColors.primary 
                                    : Colors.white, 
                                size: 24
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => setState(() {
                              _showInfoCard = false;
                              _isListening = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        landmark.description,
                        style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8), height: 1.8, fontWeight: FontWeight.w400, letterSpacing: 0.2),
                      ),
                    ),
                  ),
                  
                  if (_isListening) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(15, (i) => Container(
                        width: 4,
                        height: 10 + Random().nextInt(40).toDouble(),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true))
                       .scaleY(begin: 0.5, end: 1.5, duration: (300 + i * 50).ms, curve: Curves.easeInOut)),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: Text('NEVA IS NARRATING...', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2))),
                  ],

                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isListening = !_isListening),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 64,
                            decoration: BoxDecoration(
                              color: _isListening ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: (_isListening ? AppColors.primary : Colors.white).withOpacity(0.3), blurRadius: 30)],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isListening ? Icons.pause_rounded : Icons.graphic_eq_rounded, 
                                  color: _isListening ? Colors.white : Colors.black, 
                                  size: 26
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _isListening ? 'STOP NARRATION' : 'NEVA NARRATION',
                                  style: TextStyle(
                                    color: _isListening ? Colors.white : Colors.black, 
                                    fontWeight: FontWeight.w900, 
                                    fontSize: 14, 
                                    letterSpacing: 1
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _navigationTarget = landmark;
                            _isNavigating = true;
                            _showInfoCard = false;
                            _arMode = 'navigate';
                          });
                        },
                        child: Container(
                          width: 140,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.4), blurRadius: 20)],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.navigation_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text('NAVIGATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // New "View on Smart Map" button
                  GestureDetector(
                    onTap: () {
                      if (landmark.lat != null && landmark.lng != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SmartTourismMapPage(
                              initialLat: landmark.lat!,
                              initialLng: landmark.lng!,
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 12),
                          const Text(
                            'VIEW ON SMART MAP',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 800.ms, curve: Curves.easeOutQuart);
  }

  Widget _buildDiscoveryCrosshair() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Architectural Scanner
          Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary.withOpacity(0.1), width: 1),
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat()).rotate(duration: 10.seconds).scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 2.seconds, curve: Curves.easeInOut),
          
          // Corner Brackets
          ...List.generate(4, (index) => Transform.rotate(
            angle: (index * 90) * pi / 180,
            child: SizedBox(
              width: 180, height: 180,
              child: Stack(
                children: [
                  Positioned(
                    top: 0, left: 0,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.primary.withOpacity(0.5), width: 2),
                          left: BorderSide(color: AppColors.primary.withOpacity(0.5), width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 1.seconds),

          // Central Lock
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15)],
            ),
            child: Center(
              child: Container(
                width: 4, height: 4,
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds),
          
          // Scanning Beam
          Container(
            width: 2, height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.primary, Colors.transparent],
              ),
            ),
          ).animate(onPlay: (c) => c.repeat()).moveX(begin: -80, end: 80, duration: 2.seconds),
        ],
      ),
    );
  }

  Widget _buildVisionNodes() {
    return Positioned.fill(
      child: Stack(
        children: List.generate(8, (i) {
          final random = Random(i);
          return Positioned(
            left: MediaQuery.of(context).size.width * (0.2 + random.nextDouble() * 0.6),
            top: MediaQuery.of(context).size.height * (0.3 + random.nextDouble() * 0.4),
            child: Column(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.6),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.primary, blurRadius: 10)],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 1, height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.primary.withOpacity(0.5), Colors.transparent],
                    ),
                  ),
                ),
              ],
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .fadeIn(delay: (i * 200).ms)
             .moveY(begin: -10, end: 10, duration: (2000 + i * 500).ms, curve: Curves.easeInOut),
          );
        }),
      ),
    );
  }

  Widget _buildMappingOverlay() {
    return Positioned(
      bottom: 120,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildNevaAvatar(50),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    '"Point at the center of the place and lock the coordinates."',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isMapping = false),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _newPlaceController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Place Name (e.g. Secret Rooftop)',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.white70, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _mappingCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final cat = _mappingCategories[index];
                  final isSelected = _selectedCategory == cat['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat['id']),
                    child: AnimatedContainer(
                      duration: 300.ms,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? Colors.white30 : Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'], color: Colors.white, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            cat['label'],
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPlaceDescriptionController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'What makes this place special...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                if (_newPlaceController.text.isEmpty) return;
                setState(() => _isSavingMapping = true);
                await Future.delayed(const Duration(milliseconds: 1500));
                
                if (mounted) {
                  setState(() {
                    _nexusPoints += 50;
                    _isMapping = false;
                    _isSavingMapping = false;
                    _landmarks.add(_ArLandmark(
                      _newPlaceController.text, 
                      'assets/images/lotus_temple.png', 
                      5.0, 
                      '0 m', 
                      _heading, 
                      _newPlaceDescriptionController.text.isEmpty ? 'Discovered by you.' : _newPlaceDescriptionController.text, 
                      _selectedCategory
                    ));
                    _newPlaceController.clear();
                    _newPlaceDescriptionController.clear();
                    _selectedCategory = 'HIDDEN';
                  });
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      content: GlassCard(
                        padding: const EdgeInsets.all(16),
                        glowColor: Colors.amber,
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: Colors.amber),
                            const SizedBox(width: 12),
                            const Text('DISCOVERY SAVED! +50 NEXUS POINTS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20)],
                ),
                child: Center(
                  child: _isSavingMapping 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('LOCK SPATIAL ANCHOR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
  }

  Widget _buildNavigationOverlay() {
    if (_navigationTarget == null) return const SizedBox.shrink();

    double diff = _navigationTarget!.bearing - _heading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    final isTargetInView = diff.abs() < 30;

    return Positioned.fill(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                stops: const [0.3, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 130,
            right: 20,
            child: GestureDetector(
              onTap: () => setState(() {
                _isNavigating = false;
                _navigationTarget = null;
                _arMode = 'explore';
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
                  boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.2), blurRadius: 15)],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.close_rounded, color: Color(0xFF00E5FF), size: 18),
                    SizedBox(width: 8),
                    Text('EXIT NAV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5)),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isTargetInView)
                  Transform.rotate(
                    angle: (diff > 0 ? 90 : -90) * pi / 180,
                    child: Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 80)
                        .animate(onPlay: (c) => c.repeat())
                        .fade(duration: 1.seconds)
                        .moveX(begin: diff > 0 ? -20 : 20, end: diff > 0 ? 20 : -20),
                  )
                else
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Stack(
                      children: [
                        ...List.generate(4, (i) => Positioned(
                          top: i < 2 ? 0 : null,
                          bottom: i >= 2 ? 0 : null,
                          left: i % 2 == 0 ? 0 : null,
                          right: i % 2 != 0 ? 0 : null,
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              border: Border(
                                top: i < 2 ? const BorderSide(color: Color(0xFF00E5FF), width: 4) : BorderSide.none,
                                bottom: i >= 2 ? const BorderSide(color: Color(0xFF00E5FF), width: 4) : BorderSide.none,
                                left: i % 2 == 0 ? const BorderSide(color: Color(0xFF00E5FF), width: 4) : BorderSide.none,
                                right: i % 2 != 0 ? const BorderSide(color: Color(0xFF00E5FF), width: 4) : BorderSide.none,
                              ),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 10)
                              ],
                            ),
                          ),
                        )),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.gps_fixed_rounded, color: Color(0xFF00E5FF), size: 50)
                                  .animate(onPlay: (c) => c.repeat())
                                  .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1.seconds),
                              const SizedBox(height: 12),
                              const Text('TARGET LOCKED', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().scale(begin: const Offset(0.8, 0.8)).fade(),
                const SizedBox(height: 60),
                
                // DISTANCE HUD - IMPROVED COLOR AND POSITION
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.2), blurRadius: 30),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _navigationTarget!.distance.toUpperCase(),
                        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ESTIMATED TO ${_navigationTarget!.name.toUpperCase()}',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: 0.5, end: 0),
              ],
            ),
          ),
          
          // BOTTOM INSTRUCTIONS - MOVED EVEN HIGHER TO AVOID OVERLAP
          Positioned(
            bottom: 160, 
            left: 30,
            right: 30,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 40)],
              ),
              child: Row(
                children: [
                  _buildNevaAvatar(50),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      isTargetInView 
                          ? "Target locked. Proceed forward towards ${_navigationTarget!.name}."
                          : "Rotate your device to align with the guidance arrow.",
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                  ),
                ],
              ),
            ).animate().fade().slideY(begin: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildNevaAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF64B5F6).withOpacity(0.5), blurRadius: 15, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.asset(
          'assets/images/neva_avatar.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFF1976D2),
            child: const Center(
              child: Icon(Icons.face_5_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Positioned(
      top: 130,
      left: 60,
      right: 60,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(35),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isIdentifying = false),
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Text(
                      'EXPLORE',
                      style: TextStyle(
                        color: !_isIdentifying ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 30, color: Colors.white10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _isIdentifying = true),
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: Text(
                      'DISCOVER',
                      style: TextStyle(
                        color: _isIdentifying ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: -1, end: 0, duration: 500.ms, curve: Curves.easeOutQuart);
  }

  Widget _buildDiscoveryBar() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category selector
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _discoveryTypes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final type = _discoveryTypes[index];
                final isSelected = _selectedDiscoveryType == type['id'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedDiscoveryType = type['id']),
                  child: AnimatedContainer(
                    duration: 300.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: isSelected ? Colors.white : Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Icon(type['icon'], color: isSelected ? Colors.black : Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          type['label'],
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          // Capture Button
          GestureDetector(
            onTap: _handleIdentify,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer tactical ring
                Container(
                  width: 95, height: 95,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
                  ),
                ).animate(onPlay: (c) => c.repeat()).rotate(duration: 3.seconds),
                
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20)],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(Icons.architecture_rounded, color: Colors.black, size: 35),
                  ),
                ),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08), duration: 800.ms),
          const SizedBox(height: 12),
          const Text(
            'ANALYZE ARCHITECTURE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2.5),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds),
        ],
      ),
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
  }

  String _selectedDiscoveryCategory = 'Historical';

  Widget _buildDiscoveryCategorySelector() {
    final categories = [
      {'id': 'Historical', 'icon': Icons.account_balance_rounded, 'label': 'HISTORICAL'},
      {'id': 'Attractions', 'icon': Icons.auto_awesome_rounded, 'label': 'ATTRACTIONS'},
      {'id': 'Food', 'icon': Icons.restaurant_rounded, 'label': 'FOOD & DRINK'},
      {'id': 'Shopping', 'icon': Icons.shopping_bag_rounded, 'label': 'SHOPPING'},
    ];

    return Positioned(
      top: 190,
      left: 0, right: 0,
      child: Center(
        child: Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedDiscoveryCategory == cat['id'];
              return GestureDetector(
                onTap: () => setState(() => _selectedDiscoveryCategory = cat['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withOpacity(0.8) : Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? Colors.white : Colors.white10),
                    boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)] : [],
                  ),
                  child: Row(
                    children: [
                      Icon(cat['icon'] as IconData, color: Colors.white, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        cat['label'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ).animate().slideY(begin: -1, end: 0, duration: 600.ms, curve: Curves.easeOutBack);
  }

  Widget _buildNevaAnalysisOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNevaAvatar(120)
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 2.seconds)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1.seconds, curve: Curves.easeInOut),
            const SizedBox(height: 40),
            const Text(
              'NEVA IS ANALYZING...',
              style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 3),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 1.seconds),
            const SizedBox(height: 16),
            Container(
              width: 200,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(1),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.7, // Simulated progress
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF),
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.5), blurRadius: 10)],
                  ),
                ),
              ).animate(onPlay: (c) => c.repeat()).moveX(begin: -200, end: 200, duration: 1.5.seconds),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyPlacesPanel() {
    return Positioned(
      top: 220,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'NEARBY PLACES',
            style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          ..._landmarks.take(3).map((l) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    Text(l.distance, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 12),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: (l.imagePath.startsWith('http') 
                          ? CachedNetworkImageProvider(l.imagePath) 
                          : AssetImage(l.imagePath)) as ImageProvider, 
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    ).animate().slideX(begin: 1, end: 0);
  }
}

class _AnimatedScanLines extends StatefulWidget {
  const _AnimatedScanLines();
  @override
  State<_AnimatedScanLines> createState() => _AnimatedScanLinesState();
}

class _AnimatedScanLinesState extends State<_AnimatedScanLines> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ScanLinePainter(offset: _controller.value),
        );
      },
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  final double offset;
  _ScanLinePainter({this.offset = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.05)
      ..strokeWidth = 1.0;

    for (double y = 0; y < size.height; y += 8) {
      double shiftY = (y + (offset * size.height)) % size.height;
      canvas.drawLine(Offset(0, shiftY), Offset(size.width, shiftY), paint);
    }
    
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, const Color(0xFF00E5FF).withOpacity(0.1), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, (offset * size.height) % size.height, size.width, 100));
    
    canvas.drawRect(Rect.fromLTWH(0, (offset * size.height) % size.height, size.width, 100), beamPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ParticleField extends StatefulWidget {
  const _ParticleField();
  @override
  State<_ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<_ParticleField> with SingleTickerProviderStateMixin {
  late List<_Particle> particles;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    particles = List.generate(30, (index) => _Particle());
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..addListener(() {
      setState(() {
        for (var p in particles) {
          p.update();
        }
      });
    })..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ParticlePainter(particles: particles),
    );
  }
}

class _Particle {
  double x = Random().nextDouble();
  double y = Random().nextDouble();
  double vx = (Random().nextDouble() - 0.5) * 0.001;
  double vy = (Random().nextDouble() - 0.5) * 0.001;
  double size = Random().nextDouble() * 2 + 1;
  double opacity = Random().nextDouble();

  void update() {
    x += vx;
    y += vy;
    if (x < 0 || x > 1) vx *= -1;
    if (y < 0 || y > 1) vy *= -1;
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var p in particles) {
      paint.color = const Color(0xFF00E5FF).withOpacity(p.opacity * 0.3);
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ArLandmark {
  final String name;
  final String imagePath;
  final double rating;
  final String distance;
  final double bearing;
  final String description;
  final String category;
  final double distanceM;
  final double? lat;
  final double? lng;

  const _ArLandmark(this.name, this.imagePath, this.rating, this.distance, this.bearing, this.description, this.category, [this.distanceM = 0, this.lat, this.lng]);
}

class _SonarRadarPainter extends CustomPainter {
  final double heading;
  final List<_ArLandmark> landmarks;

  _SonarRadarPainter({required this.heading, required this.landmarks});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const cyanColor = Color(0xFF00E5FF);

    canvas.drawCircle(center, maxRadius, Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill);
    
    for (int i = 1; i <= 3; i++) {
      final r = maxRadius * i / 3;
      canvas.drawCircle(center, r, Paint()
        ..color = cyanColor.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0);
    }

    final crossPaint = Paint()
      ..color = cyanColor.withOpacity(0.1)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crossPaint);
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crossPaint);

    // Removed central blue dot and wave animation as requested
    for (final lm in landmarks) {
      double relAngle = (lm.bearing - heading) * pi / 180;
      double dist = maxRadius * 0.7;
      double dx = center.dx + dist * sin(relAngle);
      double dy = center.dy - dist * cos(relAngle);

      canvas.drawCircle(Offset(dx, dy), 8, Paint()
        ..color = cyanColor.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(dx, dy), 4, Paint()..color = cyanColor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

extension StringExtension on String {
  String capitalize() => isNotEmpty ? "${this[0].toUpperCase()}${substring(1).toLowerCase()}" : this;
}
