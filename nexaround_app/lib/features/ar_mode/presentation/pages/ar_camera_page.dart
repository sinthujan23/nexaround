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
  final Map<String, dynamic>? initialPlace;
  const ArCameraPage({super.key, this.initialPlace});

  @override
  State<ArCameraPage> createState() => _ArCameraPageState();
}

class _ArCameraPageState extends State<ArCameraPage> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _initialPlaceTriggered = false;
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
  bool _isIdentifying = true; // Default to DISCOVER mode
  
  _ArLandmark? _identifiedPlace;
  bool _isNevaAnalyzing = false;
  bool _isNevaSearching = false;
  Map<String, dynamic>? _nevaSearchResult;
  _ArLandmark? _frozenLandmark; // Store the landmark being analyzed

  // ═══════════════════════════════════════
  // AR DISCOVERY MODE - Silent Capture in DISCOVER tab
  // ═══════════════════════════════════════
  Map<String, dynamic>? _arDiscoveryResult;
  _ArLandmark? _arDiscoveryTarget;
  geo.Position? _currentPosition;
  bool _isSilentCapturing = false; // Silent capture in progress (no UI feedback)
  bool _hasCapturedForCurrentTarget = false; // Prevent multiple captures for same place
  
  // Disable old discovery system when Neva is active
  bool get _isOldDiscoveryDisabled => _isNevaSearching || _nevaSearchResult != null;

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
      if (mounted) {
        setState(() => _heading = event.heading ?? 0.0);
      }
    });
    // If launched from proximity alert, auto-trigger Neva after short delay
    if (widget.initialPlace != null) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_initialPlaceTriggered) {
          _initialPlaceTriggered = true;
          final p = widget.initialPlace!;
          final landmark = _ArLandmark(
            p['name'] ?? 'Unknown',
            '',
            (p['rating'] ?? 0.0).toDouble(),
            p['distance'] ?? 'Nearby',
            0,
            '',
            p['category'] ?? 'Place',
            (p['distanceM'] ?? 0).toDouble(),
            p['latitude'],
            p['longitude'],
          );
          _startNevaSearch(landmark);
        }
      });
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _controller?.dispose();
    _newPlaceController.dispose();
    _newPlaceDescriptionController.dispose();
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

      if (mounted) setState(() {
        _landmarks = collected;
        _currentPosition = pos;
      });
    } catch (e) {
      debugPrint('AR places error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // AR DISCOVERY MODE - Silent Capture with Gemini (integrated with DISCOVER tab)
  // ════════════════════════════════════════════════════════════════
  
  /// Silently capture image and identify place using GPS location first, then image analysis
  Future<void> _triggerSilentCaptureForPlaceIdentification() async {
    if (_controller == null || !_isCameraReady || _isNevaAnalyzing || _isSilentCapturing) return;
    
    debugPrint('🔮 Starting place identification...');
    
    // Set silent capturing state
    setState(() => _isSilentCapturing = true);
    
    try {
      // 1. Get current GPS location first
      final currentPosition = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      debugPrint('🔮 GPS location: ${currentPosition.latitude}, ${currentPosition.longitude}');
      
      // 2. Try to identify place using GPS location (Google Places API)
      final placeFromLocation = await _identifyPlaceFromLocation(currentPosition);
      
      if (placeFromLocation != null) {
        debugPrint('🔮 Successfully identified place from GPS location');
        // Show result from GPS location
        if (mounted) {
          setState(() {
            _arDiscoveryResult = placeFromLocation;
            _currentPosition = currentPosition;
            _isSilentCapturing = false;
          });
        }
        return;
      }
      
      debugPrint('🔮 Could not identify place from GPS, trying image analysis...');
      
      // 3. If GPS identification fails, capture image and try visual analysis
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      
      debugPrint('🔮 Image captured, sending to Gemini for visual analysis...');
      
      // 4. Send image + location to Gemini Vision API
      final rawResponse = await GeminiService().identifyPlace(
        imageBytes: bytes,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
      );
      
      // 5. Parse JSON response
      String jsonStr = rawResponse.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```json?\n?'), '').replaceAll(RegExp(r'\n?```\$'), '');
      }
      
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      debugPrint('🔮 Gemini Identified Place: $result');
      
      // 6. Validate the result
      final isValid = _validatePlaceIdentification(result, currentPosition);
      
      if (isValid) {
        // Show result from image analysis
        if (mounted) {
          setState(() {
            _arDiscoveryResult = result;
            _currentPosition = currentPosition;
            _isSilentCapturing = false;
          });
        }
      } else {
        debugPrint('🔮 Both GPS and image identification failed');
        if (mounted) {
          setState(() {
            _isSilentCapturing = false;
            _hasCapturedForCurrentTarget = false; // Allow retry
          });
        }
      }
      
    } catch (e) {
      debugPrint('🔮 Place identification error: $e');
      if (mounted) {
        setState(() {
          _isSilentCapturing = false;
          _hasCapturedForCurrentTarget = false; // Allow retry on error
        });
      }
    }
  }
  
  /// Identify place using GPS location via Google Places API within 10m radius
  Future<Map<String, dynamic>?> _identifyPlaceFromLocation(geo.Position position) async {
    try {
      debugPrint('🔍 DISCOVER: Searching for places within 10m radius...');
      
      // Use Google Places API to find places at this location with 10m radius
      final places = await GooglePlacesService.fetchNearbyPlaces(
        latitude: position.latitude,
        longitude: position.longitude,
        radius: 10, // 10 meter radius as requested
      );
      
      if (places.isNotEmpty) {
        // Get the closest place (should be within 10m)
        final closestPlace = places.first;
        
        debugPrint('🔍 DISCOVER: Found place: ${closestPlace.name} (${closestPlace.distanceM}m away)');
        
        // Create result in the same format as Gemini
        final result = {
          'name': closestPlace.name,
          'category': closestPlace.categoryName ?? 'Place',
          'description': _generateDescriptionFromPlace(closestPlace),
          'fun_fact': _generateFunFactFromPlace(closestPlace),
          'tips': _generateVisitorTipsFromPlace(closestPlace),
          'confidence': 0.95, // High confidence for GPS-based identification
          'distance': closestPlace.distanceM != null ? '${closestPlace.distanceM!.toInt()}m' : 'Very close',
          'rating': closestPlace.rating ?? 0.0,
          'address': closestPlace.address ?? '',
        };
        
        return result;
      } else {
        debugPrint('🔍 DISCOVER: No places found within 10m radius');
        
        // Try expanding radius to 50m if nothing found in 10m
        debugPrint('🔍 DISCOVER: Expanding search to 50m radius...');
        final places50m = await GooglePlacesService.fetchNearbyPlaces(
          latitude: position.latitude,
          longitude: position.longitude,
          radius: 50, // 50 meter radius
        );
        
        if (places50m.isNotEmpty) {
          final closestPlace = places50m.first;
          debugPrint('🔍 DISCOVER: Found place within 50m: ${closestPlace.name} (${closestPlace.distanceM}m away)');
          
          final result = {
            'name': closestPlace.name,
            'category': closestPlace.categoryName ?? 'Place',
            'description': _generateDescriptionFromPlace(closestPlace),
            'fun_fact': _generateFunFactFromPlace(closestPlace),
            'tips': _generateVisitorTipsFromPlace(closestPlace),
            'confidence': 0.85, // Lower confidence for 50m radius
            'distance': closestPlace.distanceM != null ? '${closestPlace.distanceM!.toInt()}m' : 'Nearby',
            'rating': closestPlace.rating ?? 0.0,
            'address': closestPlace.address ?? '',
          };
          
          return result;
        }
      }
      
      debugPrint('🔍 DISCOVER: No places found nearby, will try image analysis');
      return null;
      
    } catch (e) {
      debugPrint('🔍 DISCOVER: Error in place identification: $e');
      return null;
    }
  }
  
  /// Generate description for a place from Google Places data
  String _generateDescriptionFromPlace(dynamic place) {
    final name = place.name ?? 'This place';
    final category = place.categoryName ?? 'location';
    final address = place.address;
    
    if (address != null && address.isNotEmpty) {
      return '$name is a $category located at $address. This place offers unique experiences for visitors.';
    }
    
    return '$name is a $category in this area. Visit to discover what makes this location special.';
  }
  
  /// Generate a fun fact for a place from Google Places data
  String _generateFunFactFromPlace(dynamic place) {
    final category = place.categoryName?.toLowerCase() ?? '';
    final rating = place.rating ?? 0.0;
    
    if (category.contains('restaurant') || category.contains('food')) {
      return rating > 4.5 
        ? 'This restaurant has an excellent rating of ${rating.toStringAsFixed(1)} stars!'
        : 'Local restaurants often have unique recipes passed down through generations.';
    } else if (category.contains('park') || category.contains('garden')) {
      return 'Parks provide essential green spaces and help improve air quality in urban areas.';
    } else if (category.contains('museum') || category.contains('art')) {
      return 'Museums preserve cultural heritage and tell stories about our past and present.';
    } else if (category.contains('shopping') || category.contains('store')) {
      return 'Local shops often feature unique products that you won\'t find in larger chain stores.';
    } else if (category.contains('hotel') || category.contains('lodging')) {
      return rating > 4.0
        ? 'This accommodation has a great rating of ${rating.toStringAsFixed(1)} stars!'
        : 'Hotels serve as temporary homes away from home for travelers.';
    } else {
      return 'Every place has its own unique character and stories waiting to be discovered.';
    }
  }
  
  /// Generate visitor tips for a place from Google Places data
  String _generateVisitorTipsFromPlace(dynamic place) {
    final category = place.categoryName?.toLowerCase() ?? '';
    final rating = place.rating ?? 0.0;
    
    if (category.contains('restaurant') || category.contains('food')) {
      return rating > 4.0 
        ? 'Popular spot! Consider making reservations during peak hours.'
        : 'Try visiting during off-peak hours for a more relaxed experience.';
    } else if (category.contains('park') || category.contains('garden')) {
      return 'Early mornings or late afternoons often provide the best lighting for photos.';
    } else if (category.contains('museum') || category.contains('art')) {
      return 'Check for special exhibitions or guided tours for enhanced experiences.';
    } else if (category.contains('shopping') || category.contains('store')) {
      return 'Support local businesses by exploring unique products and services.';
    } else if (category.contains('hotel') || category.contains('lodging')) {
      return 'Read recent reviews for tips on the best rooms and amenities.';
    } else {
      return 'Take time to explore and appreciate the unique features of this location.';
    }
  }
  
  /// Validate if the identified place makes sense for the location
  bool _validatePlaceIdentification(Map<String, dynamic> result, geo.Position position) {
    // Check if there was an error
    if (result['identified'] == false) {
      final description = (result['description'] ?? '').toString().toLowerCase();
      if (description.contains('error') || description.contains('connection')) {
        debugPrint('🔮 Network error occurred, allowing retry');
        return false; // Will trigger retry
      }
    }
    
    // Check if Gemini is confident enough
    final confidence = result['confidence'] ?? 0.0;
    if (confidence < 0.6) {
      debugPrint('🔮 Low confidence: $confidence');
      return false;
    }
    
    // Check if it's a generic description that might be wrong
    final name = (result['name'] ?? '').toString().toLowerCase();
    final category = (result['category'] ?? '').toString().toLowerCase();
    
    // If it identifies as a very specific famous place but we're likely in an office
    if (category.contains('temple') || category.contains('monument') || category.contains('museum')) {
      // Check if we're in a typical office area (based on time and location patterns)
      final hour = DateTime.now().hour;
      if (hour >= 9 && hour <= 17) {
        // During office hours, be more skeptical about tourist places
        debugPrint('🔮 Skeptical: Tourist place identified during office hours');
        return false;
      }
    }
    
    // If it's clearly an office or generic building, that's fine
    if (category.contains('office') || category.contains('business') || category.contains('residential')) {
      return true;
    }
    
    // Default to true for reasonable identifications
    return true;
  }
  
  /// Show a fallback message when API is not available
  Widget _buildNetworkErrorFallback() {
    return Positioned.fill(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 48),
            const SizedBox(height: 20),
            Text(
              'CONNECTION ERROR',
              style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Cannot connect to AI service\nPlease check your internet connection',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() {
                  _hasCapturedForCurrentTarget = false; // Allow retry
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'RETRY',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Silently capture image and send to Gemini for analysis
  /// No UI feedback - user doesn't know image is being captured
  Future<void> _triggerSilentCapture(_ArLandmark target) async {
    if (_controller == null || !_isCameraReady || _isNevaAnalyzing || _isSilentCapturing) return;
    
    debugPrint('🔮 Silent capture triggered for: ${target.name}');
    
    // Set silent capturing state (no UI feedback)
    setState(() {
      _isSilentCapturing = true;
      _hasCapturedForCurrentTarget = true;
    });
    
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
        if (!_isOldDiscoveryDisabled) {
          setState(() {
            _arDiscoveryResult = result;
            _arDiscoveryTarget = target;
            _isSilentCapturing = false;
          });
        } else {
          debugPrint('🔮 Old discovery system disabled - Neva is active');
          setState(() {
            _isSilentCapturing = false;
          });
        }
      }
      
    } catch (e) {
      debugPrint('🔮 Silent capture error: $e');
      if (mounted) {
        setState(() {
          _isSilentCapturing = false;
        });
      }
    }
  }
  
  Widget _buildTopHUD() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Live dot
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: [BoxShadow(color: AppColors.primary, blurRadius: 6)],
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
               .fade(begin: 0.3, end: 1, duration: 900.ms),
              const SizedBox(width: 8),
              // AR LIVE label
              Text(
                'AR LIVE',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 16),
              // XP pill
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 5),
                        const Text('1300 XP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Exit AR Button
              GestureDetector(
                onTap: () {
                  if (widget.initialPlace != null) {
                    Navigator.of(context).pop();
                  } else {
                    HomePage.homeKey.currentState?.switchToExplore();
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

          // Top HUD (XP and Map Place) - HIDE IF NAVIGATING OR SHOWING NEVA RESULTS
          if (!_minimalHud && !_isNavigating && _nevaSearchResult == null) _buildTopHUD(),

          // Place count/Status badge at bottom - HIDE IF NAVIGATING OR SHOWING NEVA RESULTS
          if (!_minimalHud && !_isNavigating && !_isIdentifying && _nevaSearchResult == null) 
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

          // CAMERA FLASH EFFECT
          if (_isCapturing)
            Positioned.fill(
              child: Container(color: Colors.white).animate().fade(duration: 200.ms, begin: 0, end: 0.8).then().fade(duration: 400.ms, begin: 0.8, end: 0),
            ),

          // NAVIGATION OVERLAY
          if (_isNavigating && _navigationTarget != null)
            _buildNavigationOverlay(),

          // ═══════════════════════════════════════════════════════════
          // AR DISCOVERY RESULT - Now using chat bubble format in _buildDiscoveryResult
          // ═══════════════════════════════════════════════════════════
        ],
      ),
    );
  }

  Widget _buildXPBadge() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, end: 1, duration: 800.ms),
              const SizedBox(width: 7),
              Text(
                'SPATIAL DISCOVERY',
                style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ],
          ),
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.6, end: 1.0, duration: 1500.ms);
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
            // --- Modern Glass Card ---
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: cardW,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white.withOpacity(_selectedLandmark == index ? 0.12 : 0.07),
                    border: Border.all(
                      color: _selectedLandmark == index
                          ? AppColors.primary.withOpacity(0.8)
                          : Colors.white.withOpacity(0.15),
                      width: _selectedLandmark == index ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      if (_selectedLandmark == index)
                        BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 20, spreadRadius: 1),
                    ],
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
                top: -10, right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'NEAREST',
                        style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 1.5.seconds),
              ),
          ],
        ),
      ),
    ).animate().fade(duration: 400.ms).moveX(begin: -30, end: 0, curve: Curves.easeOutBack);
  }

  Widget _buildDiscoveryTarget() {
    // Auto-load places if not already loaded
    if (_landmarks.isEmpty && !_isSilentCapturing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLivePlaces());
    }

    // If Neva is searching, show searching animation
    if (_isNevaSearching) {
      return Stack(children: [_buildNevaSearchingAnimation()]);
    }

    // If we have Neva result, show it
    if (_nevaSearchResult != null) {
      return _buildNevaResult();
    }

    // Clear any old discovery result
    if (_arDiscoveryResult != null) {
      setState(() => _arDiscoveryResult = null);
      return const SizedBox.shrink();
    }

    // Get the landmark the camera is pointing at
    final pointedLandmark = _frozenLandmark ?? _getPointedLandmark();
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        // ── OTHER PLACE DOTS (all landmarks except the pointed one) ─
        ..._buildOtherPlaceDots(pointedLandmark, screenW, screenH),

        // ── AR CROSSHAIR ──────────────────────────────────────────
        Positioned(
          left: screenW / 2 - 40,
          top: screenH / 2 - 40,
          child: _buildARCrosshair(pointedLandmark != null),
        ),

        // ── LIVE DISTANCE LINE + BADGE (when pointing at a place) ─
        if (pointedLandmark != null) ...[
          // Vertical distance line from crosshair to info panel
          Positioned(
            left: screenW / 2 - 1,
            top: screenH / 2 + 40,
            child: Container(
              width: 2,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0)],
                ),
              ),
            ),
          ),

          // Distance badge centered
          Positioned(
            left: screenW / 2 - 50,
            top: screenH / 2 + 100,
            child: Container(
              width: 100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary, width: 1.5),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.straighten, color: AppColors.primary, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    pointedLandmark.distance,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(begin: const Offset(0.97, 0.97), end: const Offset(1.03, 1.03), duration: 1.5.seconds),
          ),

          // Place info panel — static, no blink, live content
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _startNevaSearch(pointedLandmark),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.2),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 30, spreadRadius: 2),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 0.8),
                                ),
                                child: Text(
                                  pointedLandmark.category.toUpperCase(),
                                  style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                pointedLandmark.name,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1.1),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                                  const SizedBox(width: 3),
                                  Text('${pointedLandmark.rating}', style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 12),
                                  Icon(Icons.straighten, color: Colors.white38, size: 13),
                                  const SizedBox(width: 3),
                                  Text(pointedLandmark.distance, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Neva avatar + floating label
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildNevaAvatar(52)
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .moveY(begin: -3, end: 3, duration: 1800.ms, curve: Curves.easeInOut)
                              .shimmer(duration: 3.seconds, color: const Color(0xFF00E5FF).withOpacity(0.3)),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 0.8),
                              ),
                              child: const Text(
                                'ASK NEVA',
                                style: TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],

        // ── SCANNING STATE (no landmark in view) ──────────────────
        if (pointedLandmark == null && !_isNevaSearching)
          Positioned(
            left: 0, right: 0,
            bottom: 60,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white38),
                        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.2, end: 1, duration: 700.ms),
                        const SizedBox(width: 10),
                        Text(
                          _landmarks.isEmpty ? 'SCANNING FOR PLACES...' : 'POINT CAMERA AT A PLACE',
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.4, end: 1, duration: 900.ms),
            ),
          ),
      ],
    );
  }

  /// Build floating dots for all places NOT currently pointed at
  List<Widget> _buildOtherPlaceDots(_ArLandmark? pointedLandmark, double screenW, double screenH) {
    final List<Widget> dots = [];

    for (final lm in _landmarks) {
      // Skip the pointed one
      if (pointedLandmark != null && lm.name == pointedLandmark.name) continue;

      // Calculate horizontal position based on bearing relative to heading
      double diff = lm.bearing - _heading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      // Only show dots within ±60° of camera view
      if (diff.abs() > 60) continue;

      // Map bearing diff to screen X position
      final double xFraction = 0.5 + (diff / 60) * 0.5;
      final double x = screenW * xFraction;

      // Vertical position based on distance — closer = lower on screen
      final double maxDist = _landmarks.map((l) => l.distanceM).reduce((a, b) => a > b ? a : b);
      final double normalized = (lm.distanceM / maxDist).clamp(0.1, 1.0);
      // Closer places appear lower (near horizon center), far places higher
      final double y = screenH * 0.25 + normalized * (screenH * 0.35);

      dots.add(
        Positioned(
          left: x - 18,
          top: y - 18,
          child: GestureDetector(
            onTap: () => _startNevaSearch(lm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dot with glow
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.9),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 8, spreadRadius: 1),
                    ],
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .fade(begin: 0.5, end: 1.0, duration: 1500.ms),

                const SizedBox(height: 4),

                // Distance label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 0.8),
                  ),
                  child: Text(
                    lm.distance,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return dots;
  }

  /// Radar showing all nearby places as dots
  Widget _buildRadar() {
    const double size = 110;
    final pointedLandmark = _getPointedLandmark();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarPainter(
          landmarks: _landmarks,
          heading: _heading,
          pointedLandmark: pointedLandmark,
          primaryColor: AppColors.primary,
        ),
      ),
    ).animate(onPlay: (c) => c.repeat())
     .shimmer(duration: 3.seconds, color: AppColors.primary.withOpacity(0.1));
  }

  /// Animated AR crosshair that changes color when locked onto a place
  Widget _buildARCrosshair(bool locked) {
    final color = locked ? AppColors.primary : Colors.white54;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer pulse ring
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
        ).animate(onPlay: (c) => c.repeat())
         .scale(begin: const Offset(1, 1), end: const Offset(1.5, 1.5), duration: 2.seconds)
         .fade(begin: 0.4, end: 0, duration: 2.seconds),

        // Inner circle
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),

        // Corner brackets
        ...[ [true, true], [true, false], [false, true], [false, false] ].map((corner) {
          return Positioned(
            left: corner[0] ? 2 : null,
            right: corner[0] ? null : 2,
            top: corner[1] ? 2 : null,
            bottom: corner[1] ? null : 2,
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _CornerBracketPainter(
                color: color,
                flipX: !corner[0],
                flipY: !corner[1],
              ),
            ),
          );
        }),

        // Center dot
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: locked ? [BoxShadow(color: AppColors.primary, blurRadius: 10)] : null,
          ),
        ),
      ],
    );
  }
  
  /// Get the landmark that the camera is currently pointing at
  _ArLandmark? _getPointedLandmark() {
    if (_currentPosition == null || _landmarks.isEmpty) return null;
    
    // Camera is pointing in the direction of current heading
    final cameraHeading = _heading;
    
    // Find landmark closest to camera heading
    _ArLandmark? closestLandmark;
    double smallestAngleDiff = double.infinity;
    
    for (final landmark in _landmarks) {
      // Calculate bearing to this landmark
      final bearing = _calculateBearing(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        landmark.lat ?? 0,
        landmark.lng ?? 0,
      );
      
      // Calculate angle difference between camera heading and landmark bearing
      double angleDiff = (bearing - cameraHeading).abs();
      if (angleDiff > 180) angleDiff = 360 - angleDiff;
      
      // Consider landmarks within 30 degrees of camera center
      if (angleDiff < 30 && angleDiff < smallestAngleDiff) {
        smallestAngleDiff = angleDiff;
        closestLandmark = landmark;
      }
    }
    
    debugPrint('🔍 CAMERA: Heading $cameraHeading°, Closest landmark: ${closestLandmark?.name}, Angle diff: $smallestAngleDiff°');
    
    return closestLandmark;
  }
  
  /// Start Neva search for place information
  void _startNevaSearch(_ArLandmark landmark) async {
    setState(() {
      _isNevaSearching = true;
      _frozenLandmark = landmark; // Freeze this landmark
    });
    
    try {
      // Create a structured premium prompt for this place
      final placePrompt = '''
You are an expert local guide. Give me a STRUCTURED response about "${landmark.name}" (${landmark.category ?? 'place'}, rated ${landmark.rating}/5, located at ${landmark.lat}, ${landmark.lng}).

Respond ONLY in this exact JSON format with no extra text:
{
  "tagline": "One punchy sentence that captures the essence of this place (max 12 words)",
  "highlight1_title": "Short title (2-4 words)",
  "highlight1_body": "One impactful sentence about what makes this place worth visiting or knowing about",
  "highlight2_title": "Short title (2-4 words)",
  "highlight2_body": "One sentence about a key feature, specialty, or unique aspect",
  "top_positive": "Best thing people love about this place — be specific, not generic",
  "top_negative": "Most common complaint or downside people mention — be honest and specific",
  "insider_tip": "One practical insider tip a local would give (max 15 words)"
}

Rules:
- Be SPECIFIC to this exact place, not generic advice
- If it is a regular shop/business, focus on what sets it apart
- top_positive and top_negative should sound like real review excerpts
- Never say "I don't have information" — give your best informed response
''';

      
      debugPrint('🔍 NEVA: Starting search for ${landmark.name}');
      
      // Call Gemini with the specific place prompt
      final geminiService = GeminiService();
      final response = await geminiService.getResponse(placePrompt);
      
      debugPrint('🔍 NEVA: Got response: ${response.substring(0, 100)}...');
      
      if (response.isNotEmpty) {
        // Parse JSON response
        Map<String, dynamic> parsed = {};
        try {
          final jsonStart = response.indexOf('{');
          final jsonEnd = response.lastIndexOf('}') + 1;
          if (jsonStart >= 0 && jsonEnd > jsonStart) {
            parsed = Map<String, dynamic>.from(
              (response.substring(jsonStart, jsonEnd).replaceAll('\n', ' ') as dynamic) is String
                ? jsonDecode(response.substring(jsonStart, jsonEnd))
                : {},
            );
          }
        } catch (_) {}

        final nevaResult = {
          'name': landmark.name,
          'category': landmark.category ?? 'Place',
          'distance': landmark.distance,
          'rating': landmark.rating,
          'tagline': parsed['tagline'] ?? '',
          'highlight1_title': parsed['highlight1_title'] ?? 'Highlights',
          'highlight1_body': parsed['highlight1_body'] ?? '',
          'highlight2_title': parsed['highlight2_title'] ?? 'Key Feature',
          'highlight2_body': parsed['highlight2_body'] ?? '',
          'top_positive': parsed['top_positive'] ?? '',
          'top_negative': parsed['top_negative'] ?? '',
          'insider_tip': parsed['insider_tip'] ?? '',
          'description': response,
          'confidence': 0.9,
        };
        
        setState(() {
          _nevaSearchResult = nevaResult;
        });
        
        debugPrint('🔍 NEVA: Search completed for ${landmark.name}');
      }
    } catch (e) {
      debugPrint('🔍 NEVA: Error during search: $e');
      // Show basic info if search fails
      final basicResult = {
        'name': landmark.name,
        'category': landmark.category ?? 'Place',
        'distance': landmark.distance,
        'rating': landmark.rating,
        'description': landmark.description ?? 'A notable location nearby.',
        'fun_fact': '',
        'tips': '',
        'confidence': 0.7,
      };
      
      setState(() {
        _nevaSearchResult = basicResult;
      });
    } finally {
      setState(() {
        _isNevaSearching = false;
      });
    }
  }
  
  /// Build Neva searching animation
  Widget _buildNevaSearchingAnimation() {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Colors.black.withOpacity(0.75),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Outer glow ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 148, height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 1),
                      ),
                    ).animate(onPlay: (c) => c.repeat())
                     .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 2.seconds)
                     .fade(begin: 0.6, end: 0, duration: 2.seconds),

                    // Avatar with sweep glow border
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const SweepGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFF00E5FF)],
                        ),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 24),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/neva_avatar.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .scale(begin: const Offset(0.97, 0.97), end: const Offset(1.03, 1.03), duration: 1.8.seconds),
                  ],
                ),

                const SizedBox(height: 24),

                // Name
                const Text(
                  'NEVA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),

                const SizedBox(height: 8),

                // Status text
                Text(
                  'Analyzing place...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                 .fade(begin: 0.4, end: 1, duration: 900.ms),

                const SizedBox(height: 28),

                // Loading dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) =>
                    Container(
                      width: 7, height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true), delay: Duration(milliseconds: i * 200))
                     .scale(begin: const Offset(0.4, 0.4), end: const Offset(1, 1), duration: 600.ms)
                     .fade(begin: 0.2, end: 1, duration: 600.ms),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// Build Neva result display - completely separate screen
  Widget _buildNevaResult() {
    if (_nevaSearchResult == null) return const SizedBox.shrink();
    
    return Stack(
      children: [
        // Full screen background - REMOVED to maintain brightness
        // Positioned.fill(
        //   child: Container(
        //     color: Colors.black.withOpacity(0.9),
        //   ),
        // ),
        
        // Content area
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  Expanded(
                    child: _buildDiscoveryResult(_nevaSearchResult!),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // ONLY ONE close button - top right
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 16,
          child: GestureDetector(
            onTap: () {
              debugPrint('🔍 NEVA: Closing result');
              if (widget.initialPlace != null) {
                // Launched from proximity alert — go back to previous page
                Navigator.of(context).pop();
              } else {
                setState(() {
                  _nevaSearchResult = null;
                  _frozenLandmark = null;
                  _arDiscoveryResult = null;
                });
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.8),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8),
                ],
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  /// Build AR pointer for a landmark
  Widget _buildARPointer(dynamic landmark, double relativeAngle) {
    final name = landmark.name ?? 'Unknown Place';
    final distance = landmark.distanceM != null ? '${landmark.distanceM!.toInt()}m' : '';
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Location badge with name
        Container(
          constraints: const BoxConstraints(maxWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.9),
                AppColors.primary.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (distance.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  distance,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ).animate(onPlay: (c) => c.repeat())
         .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds)
         .fade(begin: 0.8, end: 1, duration: 1.5.seconds),
        
        const SizedBox(height: 4),
        
        // Pointer arrow
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withOpacity(0.8),
                AppColors.primary.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        
        // Location dot with pulse
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.2),
              ),
            ).animate(onPlay: (c) => c.repeat())
             .scale(begin: const Offset(1, 1), end: const Offset(2, 2), duration: 2.seconds)
             .fade(begin: 0.5, end: 0, duration: 2.seconds),
            
            // Inner dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  /// Build the discovery result in conversational chat bubble format like Neva
  Widget _buildDiscoveryResult(Map<String, dynamic> result) {
    final name = result['name'] ?? 'Unknown Place';
    final category = result['category'] ?? 'Place';
    final distance = result['distance'] ?? 'Nearby';
    final rating = (result['rating'] ?? 0.0) as double;
    final tagline = result['tagline'] ?? '';
    final h1Title = result['highlight1_title'] ?? '';
    final h1Body = result['highlight1_body'] ?? '';
    final h2Title = result['highlight2_title'] ?? '';
    final h2Body = result['highlight2_body'] ?? '';
    final topPositive = result['top_positive'] ?? '';
    final topNegative = result['top_negative'] ?? '';
    final insiderTip = result['insider_tip'] ?? '';

    return ListView(
      padding: const EdgeInsets.only(top: 52, bottom: 20),
      children: [
        // ── Neva avatar row ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildNevaAvatar(36),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Neva', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w800)),
                  Text('just now', style: TextStyle(color: Colors.black45, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Bubble 1: pointing out the place ─────────────────
        _nevaBubble(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
              children: [
                const TextSpan(text: '📍 I can see '),
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
                TextSpan(text: ' right there — a $category just $distance away.'),
              ],
            ),
          ),
          delay: 0.ms,
        ),

        // ── Bubble 2: rating ──────────────────────────────────
        if (rating > 0)
          _nevaBubble(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(5, (i) => Icon(
                  i < rating.floor() ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFFFD700), size: 16,
                )),
                const SizedBox(width: 8),
                Text(
                  '${rating.toStringAsFixed(1)} rating',
                  style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            delay: 300.ms,
          ),

        // ── Bubble 3: tagline ─────────────────────────────────
        if (tagline.isNotEmpty)
          _nevaBubble(
            child: Text('"$tagline"',
              style: const TextStyle(color: Colors.black87, fontSize: 14, fontStyle: FontStyle.italic, height: 1.5)),
            delay: 600.ms,
          ),

        // ── Bubble 4 & 5: highlights ──────────────────────────
        if (h1Body.isNotEmpty)
          _nevaBubble(
            child: _bubbleHighlight(Icons.bolt_rounded, h1Title, h1Body, const Color(0xFF00E5FF)),
            delay: 900.ms,
          ),
        if (h2Body.isNotEmpty)
          _nevaBubble(
            child: _bubbleHighlight(Icons.place_rounded, h2Title, h2Body, const Color(0xFFFFB800)),
            delay: 1200.ms,
          ),

        // ── Bubble 6: positive review ─────────────────────────
        if (topPositive.isNotEmpty)
          _nevaBubble(
            child: _bubbleReview(true, topPositive),
            delay: 1500.ms,
          ),

        // ── Bubble 7: negative review ─────────────────────────
        if (topNegative.isNotEmpty)
          _nevaBubble(
            child: _bubbleReview(false, topNegative),
            delay: 1800.ms,
          ),

        // ── Bubble 8: insider tip ─────────────────────────────
        if (insiderTip.isNotEmpty)
          _nevaBubble(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(insiderTip,
                    style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.5)),
                ),
              ],
            ),
            delay: 2100.ms,
          ),

        const SizedBox(height: 12),

        // ── Ask more button ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => HomePage.homeKey.currentState?.switchToNeva('Tell me more about $name'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF7C3AED)],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 15),
                  SizedBox(width: 8),
                  Text('Ask Neva More', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Single Neva chat bubble wrapper
  Widget _nevaBubble({required Widget child, required Duration delay}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 48, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: Colors.black.withOpacity(0.06), width: 0.8),
        ),
        child: child,
      ),
    ).animate(delay: delay).fadeIn(duration: 350.ms).slideX(begin: -0.04, end: 0);
  }

  Widget _bubbleHighlight(IconData icon, String title, String body, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.5),
              children: [
                TextSpan(text: '$title  ', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubbleReview(bool positive, String text) {
    final color = positive ? const Color(0xFF4ADE80) : const Color(0xFFFF6B6B);
    final emoji = positive ? '👍' : '👎';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, style: TextStyle(color: color.withOpacity(0.85), fontSize: 13, height: 1.5)),
        ),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String body, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewTile(bool isPositive, String text) {
    final color = isPositive ? const Color(0xFF4ADE80) : const Color(0xFFFF6B6B);
    final icon = isPositive ? Icons.thumb_up_rounded : Icons.thumb_down_rounded;
    final label = isPositive ? 'LOVED BY VISITORS' : 'COMMON COMPLAINT';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build a single chat bubble like Neva's interface
  Widget _buildChatBubble(String text, {required bool isNeva, required Duration delay}) {
    return Align(
      alignment: isNeva ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isNeva 
            ? LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.9),
                  AppColors.primary.withOpacity(0.8),
                ],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isNeva ? const Radius.circular(4) : const Radius.circular(20),
            bottomRight: isNeva ? const Radius.circular(20) : const Radius.circular(4),
          ),
          border: Border.all(
            color: isNeva 
              ? AppColors.primary.withOpacity(0.3)
              : Colors.white.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: isNeva 
                ? AppColors.primary.withOpacity(0.2)
                : Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _buildAnimatedText(text, isNeva: isNeva, delay: delay),
      ).animate()
       .slideY(begin: 0.1, end: 0, duration: 600.ms, delay: delay)
       .fadeIn(duration: 400.ms, delay: delay),
    );
  }
  
  /// Build animated text that appears like typing
  Widget _buildAnimatedText(String text, {required bool isNeva, required Duration delay}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: isNeva ? Colors.white : Colors.white.withOpacity(0.9),
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        children: _parseTextSpans(text),
      ),
    ).animate()
     .fadeIn(duration: 800.ms, delay: delay + 200.ms);
  }
  
  /// Parse text with markdown-like formatting
  List<TextSpan> _parseTextSpans(String text) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastIndex = 0;
    
    for (final match in regex.allMatches(text)) {
      // Add text before the bold part
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      
      // Add bold text
      spans.add(TextSpan(
        text: match.group(1)!,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
      
      lastIndex = match.end;
    }
    
    // Add remaining text
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }
    
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }
  
  /// Build action buttons in chat style
  Widget _buildActionButtons({required Duration delay}) {
    return Column(
      children: [
        // Ask Neva button
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              if (_arDiscoveryResult != null) {
                HomePage.homeKey.currentState?.switchToNeva(
                  'Tell me more about ${_arDiscoveryResult!['name']}',
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNevaAvatar(20),
                  const SizedBox(width: 8),
                  Text(
                    'Ask me more about this place',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ).animate()
           .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 600.ms, delay: delay)
           .fadeIn(duration: 400.ms, delay: delay),
        ),
        
        const SizedBox(height: 12),
        
        // Discover again button
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _arDiscoveryResult = null;
                _arDiscoveryTarget = null;
                _hasCapturedForCurrentTarget = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Discover another place',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ).animate()
           .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 600.ms, delay: delay + 200.ms)
           .fadeIn(duration: 400.ms, delay: delay + 200.ms),
        ),
      ],
    );
  }
  
  /// Trigger location-based discovery using GPS + Gemini
  Future<void> _triggerLocationBasedDiscovery() async {
    if (_isSilentCapturing) return;
    
    setState(() => _isSilentCapturing = true);
    
    try {
      debugPrint('🔍 DISCOVER: Getting GPS location...');
      
      // Get current GPS location
      final currentPosition = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      debugPrint('🔍 DISCOVER: Location obtained - Lat: ${currentPosition.latitude}, Lng: ${currentPosition.longitude}');
      
      // Try to identify place from location first
      final placeFromLocation = await _identifyPlaceFromLocation(currentPosition);
      
      if (placeFromLocation != null && !_isOldDiscoveryDisabled) {
        debugPrint('🔍 DISCOVER: Place identified: ${placeFromLocation['name']}');
        
        // Show the discovery result in chat bubbles
        setState(() {
          _arDiscoveryResult = placeFromLocation;
        });
        
        debugPrint('🔍 DISCOVER: Discovery result set: ${_arDiscoveryResult?['name']}');
      } else if (_isOldDiscoveryDisabled) {
        debugPrint('🔍 DISCOVER: Old discovery system disabled - Neva is active');
      }
      
      if (placeFromLocation != null) {
        debugPrint('🔍 DISCOVER: Place identified from location');
        if (mounted) {
          setState(() {
            _currentPosition = currentPosition;
            _isSilentCapturing = false;
          });
        }
        return;
      }
      
      debugPrint('🔍 DISCOVER: Location identification failed, trying image analysis...');
      
      // If location identification fails, capture image and use Gemini
      if (_controller != null && _isCameraReady) {
        final XFile photo = await _controller!.takePicture();
        final bytes = await photo.readAsBytes();
        
        debugPrint('🔍 DISCOVER: Sending image to Gemini...');
        
        final rawResponse = await GeminiService().identifyPlace(
          imageBytes: bytes,
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude,
        );
        
        String jsonStr = rawResponse.trim();
        if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr.replaceAll(RegExp(r'^```json?\n?'), '').replaceAll(RegExp(r'\n?```\$'), '');
        }
        
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        
        debugPrint('🔍 DISCOVER: Gemini response received');
        
        if (mounted) {
          if (!_isOldDiscoveryDisabled) {
            setState(() {
              _arDiscoveryResult = result;
              _currentPosition = currentPosition;
              _isSilentCapturing = false;
            });
          } else {
            debugPrint('🔍 DISCOVER: Old discovery system disabled - Neva is active');
            setState(() {
              _currentPosition = currentPosition;
              _isSilentCapturing = false;
            });
          }
        }
      }
      
    } catch (e) {
      debugPrint('🔍 DISCOVER: Error - $e');
      if (mounted) {
        setState(() {
          _isSilentCapturing = false;
          _hasCapturedForCurrentTarget = false;
        });
      }
    }
  }
  
  /// Get icon for place category
  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('restaurant') || cat.contains('food')) {
      return Icons.restaurant_rounded;
    } else if (cat.contains('park') || cat.contains('garden')) {
      return Icons.park_rounded;
    } else if (cat.contains('museum') || cat.contains('art')) {
      return Icons.museum_rounded;
    } else if (cat.contains('shopping') || cat.contains('store')) {
      return Icons.shopping_bag_rounded;
    } else if (cat.contains('hotel') || cat.contains('lodging')) {
      return Icons.hotel_rounded;
    } else if (cat.contains('bank') || cat.contains('atm')) {
      return Icons.account_balance_rounded;
    } else if (cat.contains('hospital') || cat.contains('pharmacy')) {
      return Icons.local_hospital_rounded;
    } else if (cat.contains('school') || cat.contains('university')) {
      return Icons.school_rounded;
    } else if (cat.contains('gas') || cat.contains('petrol')) {
      return Icons.local_gas_station_rounded;
    } else {
      return Icons.place_rounded;
    }
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
        child: Center(
          child: Text(
            'DISCOVER',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: -1, end: 0, duration: 500.ms, curve: Curves.easeOutQuart);
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

class _RadarPainter extends CustomPainter {
  final List<_ArLandmark> landmarks;
  final double heading;
  final _ArLandmark? pointedLandmark;
  final Color primaryColor;

  _RadarPainter({
    required this.landmarks,
    required this.heading,
    required this.primaryColor,
    this.pointedLandmark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 4;
    final cyanColor = primaryColor;

    // Background circle
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()..color = Colors.black.withOpacity(0.6),
    );

    // Outer border
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..color = cyanColor.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Inner rings
    for (final r in [maxRadius * 0.4, maxRadius * 0.7]) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = cyanColor.withOpacity(0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    // Heading line (camera direction)
    final headingRad = heading * pi / 180;
    canvas.drawLine(
      center,
      Offset(
        center.dx + maxRadius * sin(headingRad),
        center.dy - maxRadius * cos(headingRad),
      ),
      Paint()
        ..color = cyanColor.withOpacity(0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Draw each landmark as a dot
    for (final lm in landmarks) {
      final relAngle = (lm.bearing - heading) * pi / 180;
      // Scale distance so closest = near center, farthest = near edge
      final maxDistM = landmarks.isNotEmpty
          ? landmarks.map((l) => l.distanceM).reduce((a, b) => a > b ? a : b)
          : 1000.0;
      final normalizedDist = (lm.distanceM / maxDistM).clamp(0.15, 0.95);
      final dist = maxRadius * normalizedDist;
      final dx = center.dx + dist * sin(relAngle);
      final dy = center.dy - dist * cos(relAngle);
      final isPointed = pointedLandmark?.name == lm.name;

      // Glow effect for pointed landmark
      if (isPointed) {
        canvas.drawCircle(
          Offset(dx, dy),
          9,
          Paint()
            ..color = cyanColor.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Dot
      canvas.drawCircle(
        Offset(dx, dy),
        isPointed ? 5.0 : 3.0,
        Paint()..color = isPointed ? cyanColor : cyanColor.withOpacity(0.7),
      );
    }

    // "RADAR" label at bottom
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'RADAR',
        style: TextStyle(
          color: cyanColor.withOpacity(0.5),
          fontSize: 7,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, size.height - 14),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.heading != heading || oldDelegate.pointedLandmark != pointedLandmark;
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final bool flipX;
  final bool flipY;

  _CornerBracketPainter({required this.color, this.flipX = false, this.flipY = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double w = size.width;
    final double h = size.height;

    canvas.save();
    if (flipX) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    if (flipY) {
      canvas.translate(0, h);
      canvas.scale(1, -1);
    }

    final path = Path()
      ..moveTo(0, h * 0.5)
      ..lineTo(0, 0)
      ..lineTo(w * 0.5, 0);

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
