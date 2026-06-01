import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_planner_page.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'dart:async';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';

class LivingMapPage extends StatefulWidget {
  const LivingMapPage({super.key});

  @override
  State<LivingMapPage> createState() => _LivingMapPageState();
}

class _LivingMapPageState extends State<LivingMapPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late AnimationController _globeController;
  late List<_SpotlightPoint3D> _globePoints;
  late List<_SpotlightPoint3D> _globePlacePoints;
  bool _showProximityAlert = false;
  String _selectedCategory = 'All';
  double? _userLatitude;
  double? _userLongitude;
  StreamSubscription<geo.Position>? _positionSubscription;
  bool _isLocationServiceEnabled = true;

  // We'll use the state data instead of these dummy lists

  String _currentLocationName = 'Locating...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _globeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _globePoints = _generateWorldMapPoints();
    // Notable cities/places highlighted as yellow pins on the globe
    _globePlacePoints = [
      _SpotlightPoint3D(40.7, -74.0),   // New York
      _SpotlightPoint3D(51.5, -0.1),    // London
      _SpotlightPoint3D(35.7, 139.7),   // Tokyo
      _SpotlightPoint3D(48.9, 2.3),     // Paris
      _SpotlightPoint3D(-33.9, 151.2),  // Sydney
      _SpotlightPoint3D(25.2, 55.3),    // Dubai
      _SpotlightPoint3D(-22.9, -43.2),  // Rio de Janeiro
      _SpotlightPoint3D(-33.9, 18.4),   // Cape Town
      _SpotlightPoint3D(19.1, 72.9),    // Mumbai
      _SpotlightPoint3D(1.3, 103.8),    // Singapore
      _SpotlightPoint3D(41.9, 12.5),    // Rome
      _SpotlightPoint3D(30.0, 31.2),    // Cairo
    ];

    _checkLocationAndInit();
  }

  List<_SpotlightPoint3D> _generateWorldMapPoints() {
    final List<_SpotlightPoint3D> points = [];
    final random = Random(42); // Seeded for consistency

    void addLandmass(double minLat, double maxLat, double minLng, double maxLng, int count) {
      for (int i = 0; i < count; i++) {
        final lat = minLat + random.nextDouble() * (maxLat - minLat);
        final lng = minLng + random.nextDouble() * (maxLng - minLng);
        points.add(_SpotlightPoint3D(lat, lng));
      }
    }

    // North America
    addLandmass(20, 70, -160, -60, 90);
    // South America
    addLandmass(-55, 10, -80, -40, 70);
    // Africa
    addLandmass(-30, 30, -15, 45, 90);
    // Europe & Asia
    addLandmass(10, 75, 0, 140, 180);
    // Australia
    addLandmass(-38, -12, 113, 150, 40);
    // Antarctica
    addLandmass(-85, -75, -180, 180, 50);
    // Greenland
    addLandmass(60, 80, -70, -20, 20);

    return points;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _globeController.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check location when app resumes (user may have enabled it in settings)
    if (state == AppLifecycleState.resumed) {
      _checkLocationAndInit();
    }
  }

  Future<void> _checkLocationAndInit() async {
    // Check location permission first (critical for iOS)
    final permissionGranted = await PermissionService.isLocationGranted();
    if (!permissionGranted) {
      // Request permission if not granted
      await PermissionService.requestLocationPermission();
    }

    // Then check if location service (GPS) is on
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    
    if (mounted) {
      setState(() => _isLocationServiceEnabled = serviceEnabled);
    }
    
    if (serviceEnabled && _positionSubscription == null) {
      _fetchInitialData();
      _startLocationTracking();
    }
  }

  void _startLocationTracking() {
    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 300,
      ),
    ).listen((position) async {
      final locationName = await GooglePlacesService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (mounted) {
        setState(() {
          _userLatitude = position.latitude;
          _userLongitude = position.longitude;
          _currentLocationName = locationName;
        });
      }
    });
  }

  Future<void> _fetchInitialData() async {
    try {
      // Permissions already granted by HomePage
      final position = await PermissionService.getSafePosition();
      if (position == null) {
        _useFallbackLocation();
        return;
      }
      
      // Reverse geocode to get human readable address
      final locationName = await GooglePlacesService.reverseGeocode(
        position.latitude, 
        position.longitude
      );

      if (mounted) {
        setState(() {
          _userLatitude = position.latitude;
          _userLongitude = position.longitude;
          _currentLocationName = locationName;
        });
        context.read<MapBloc>().add(FetchNearbyAttractions(
          latitude: position.latitude,
          longitude: position.longitude,
        ));
        context.read<MapBloc>().add(const FetchCategories());
      }
    } catch (e) {
      debugPrint('Error fetching location: $e');
      _useFallbackLocation();
    }
  }

  void _useFallbackLocation() {
    if (mounted) {
      setState(() {
        _currentLocationName = 'Colombo, Sri Lanka';
        _userLatitude = 6.9271; // Fallback to Colombo
        _userLongitude = 79.8612;
      });
      // Still fetch data with fallback location
      context.read<MapBloc>().add(FetchNearbyAttractions(
        latitude: 6.9271,
        longitude: 79.8612,
      ));
      context.read<MapBloc>().add(const FetchCategories());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // Location disabled warning banner
              if (!_isLocationServiceEnabled)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_off, color: AppColors.warning, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Location is off. Enable location for nearby attractions.',
                              style: TextStyle(color: AppColors.warning, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () => geo.Geolocator.openLocationSettings(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('ENABLE', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Layer 2: Content
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: true,
                    automaticallyImplyLeading: false,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    toolbarHeight: 80,
                    titleSpacing: 24,
                    centerTitle: false,
                    flexibleSpace: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(color: AppColors.background.withOpacity(0.5)),
                      ),
                    ),
                    title: _buildExploringCard(),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _buildGlassCircle(Icons.notifications_none_rounded),
                      ),
                    ],
                  ),
      
                  // Greeting + AI prompt
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildGreeting(),
                          const SizedBox(height: 24),
                          _buildArSpotlight(),
                          const SizedBox(height: 16),
                          _buildOdysseyCTA(),
                        ],
                      ),
                    ),
                  ),
      
                  // Categories
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 28, bottom: 8),
                      child: _buildCategoryScroller(state.categories),
                    ),
                  ),
      
                  // Computed lists
                  ...() {
                    if (state.status == MapStatus.loading || state.status == MapStatus.initial || state.attractions.isEmpty) {
                      return [
                        // Trending Shimmer
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            child: _buildSectionHeader('🔥  Trending Near You', 'See all'),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildShimmerTrendingCards()),
                        
                        // Nearby Shimmer
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader('✨  Nearby Places', 'Explore'),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildShimmerHiddenGemCards()),
                      ];
                    }

                    List<AttractionEntity> trendingPlaces = [];
                    if (_selectedCategory != 'All') {
                      trendingPlaces = state.attractions.take(5).toList();
                    } else {
                      final Map<String, AttractionEntity> categoryMap = {};
                      for (var place in state.attractions) {
                        final cat = place.categoryName ?? 'Attractions';
                        if (!categoryMap.containsKey(cat)) {
                          categoryMap[cat] = place;
                        }
                      }
                      trendingPlaces = categoryMap.values.toList();
                    }

                    final trendingIds = trendingPlaces.map((e) => e.id).toSet();
                    final nearbyPlaces = state.attractions.where((e) => !trendingIds.contains(e.id)).toList();

                    return [
                      // Trending Section
                      if (trendingPlaces.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            child: _buildSectionHeader(
                              '🔥  Trending Near You', 
                              'See all',
                              onTap: () {
                                if (_userLatitude != null && _userLongitude != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SmartTourismMapPage(
                                        initialLat: _userLatitude!,
                                        initialLng: _userLongitude!,
                                        destinationName: _currentLocationName,
                                        initialCategory: _selectedCategory,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildTrendingCards(trendingPlaces)),
                      ],

                      // Nearby Places
                      if (nearbyPlaces.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader(
                              '✨  Nearby Places', 
                              'Explore',
                              onTap: () {
                                if (_userLatitude != null && _userLongitude != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SmartTourismMapPage(
                                        initialLat: _userLatitude!,
                                        initialLng: _userLongitude!,
                                        destinationName: _currentLocationName,
                                        initialCategory: _selectedCategory,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildHiddenGemCards(nearbyPlaces)),
                      ],
                    ];
                  }(),
      
                  // Cluster suggestion
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _buildClusterSuggestion(state.attractions),
                    ),
                  ),
      
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),

              // Proximity alert bottom sheet
            if (_showProximityAlert && state.attractions.isNotEmpty) 
              _buildProximityAlert(state.attractions.first),
          ],
        ),
        );
      },
    );
  }

  Widget _buildExploringCard() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(100),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
            ),
            child: const Icon(Icons.near_me_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'EXPLORING',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 2),
                ),
                _currentLocationName == 'Locating...'
                    ? SizedBox(
                        width: 80,
                        height: 12,
                        child: Shimmer.fromColors(
                          baseColor: Colors.grey[200]!,
                          highlightColor: Colors.grey[50]!,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      )
                    : Text(
                        _currentLocationName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCircle(IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.glassWhite,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        String name = 'Explorer';
        if (state is AuthAuthenticated) {
          name = state.user.displayName.split(' ')[0];
        }

        final hour = DateTime.now().hour;
        String timeGreeting = 'Good Morning';
        if (hour >= 12 && hour < 17) timeGreeting = 'Good Afternoon';
        else if (hour >= 17 || hour < 5) timeGreeting = 'Good Evening';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$timeGreeting, $name',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ).animate().fade(),
            const SizedBox(height: 8),
            const Text(
              'Where shall we\ndiscover today?',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            ).animate().fade(delay: 100.ms).slideY(begin: 0.15, end: 0),
          ],
        );
      },
    );
  }

  /// Full-width AR preview card — simulates an AR camera viewfinder with
  /// floating place-detail cards, pins, and distance markers.
  Widget _buildArSpotlight() {
    return GestureDetector(
      onTap: () => HomePage.homeKey.currentState?.switchToAr(),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          // Dark background simulating a camera viewfinder
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B2838),
              Color(0xFF0F1923),
              Color(0xFF0A1018),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // ── 3D Revolving Holographic World Map Globe ──
              Positioned.fill(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _globeController,
                    builder: (context, _) {
                      return SizedBox(
                        width: 160,
                        height: 160,
                        child: CustomPaint(
                          painter: _SpotlightWorldMapPainter(
                            rotation: _globeController.value * 2 * pi,
                            tilt: 0.35,
                            points: _globePoints,
                            placePoints: _globePlacePoints,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Subtle environment dots (simulating a night cityscape) ──
              ...List.generate(8, (i) {
                final positions = [
                  [0.1, 0.7], [0.25, 0.5], [0.4, 0.65], [0.55, 0.45],
                  [0.7, 0.6], [0.85, 0.4], [0.15, 0.85], [0.6, 0.8],
                ];
                final colors = [
                  const Color(0xFFFFB74D), const Color(0xFF4FC3F7),
                  const Color(0xFFAED581), const Color(0xFFFF8A65),
                  const Color(0xFF81D4FA), const Color(0xFFFFD54F),
                  const Color(0xFFA5D6A7), const Color(0xFFCE93D8),
                ];
                return Positioned(
                  left: positions[i][0] * 350,
                  top: positions[i][1] * 200,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors[i].withOpacity(0.3),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                      .fade(begin: 0.2, end: 0.6, duration: Duration(milliseconds: 1500 + i * 300)),
                );
              }),

              // ── Viewfinder corner brackets ──
              const Positioned(top: 14, left: 14, child: _ArCorner(top: true, left: true)),
              const Positioned(top: 14, right: 14, child: _ArCorner(top: true, left: false)),
              const Positioned(bottom: 14, left: 14, child: _ArCorner(top: false, left: true)),
              const Positioned(bottom: 14, right: 14, child: _ArCorner(top: false, left: false)),

              // ── Floating place card 1 (left side) ──
              Positioned(
                left: 20,
                top: 30,
                child: _buildMiniPlaceCard(
                  name: 'Café Mocha',
                  category: 'Food & Drink',
                  distance: '85 m',
                  rating: '4.6',
                  color: const Color(0xFF66BB6A),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: -5, end: 5, duration: 2800.ms, curve: Curves.easeInOut)
                    .fade(begin: 0.7, end: 1.0, duration: 2800.ms),
              ),

              // ── Floating place card 2 (right side) ──
              Positioned(
                right: 16,
                top: 50,
                child: _buildMiniPlaceCard(
                  name: 'City Museum',
                  category: 'Attraction',
                  distance: '320 m',
                  rating: '4.9',
                  color: const Color(0xFFEF5350),
                ).animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 4, end: -4, duration: 3200.ms, curve: Curves.easeInOut)
                    .moveX(begin: -2, end: 2, duration: 4000.ms, curve: Curves.easeInOut),
              ),

              // ── Floating pin marker 1 (emerald - Coffee) ──
              Positioned(
                left: 145,
                top: 35,
                child: _buildPinMarker(
                  icon: Icons.local_cafe_rounded,
                  color: const Color(0xFF66BB6A),
                ),
              ),

              // ── Floating pin marker 2 (coral - Museum) ──
              Positioned(
                right: 145,
                top: 55,
                child: _buildPinMarker(
                  icon: Icons.museum_rounded,
                  color: const Color(0xFFEF5350),
                ),
              ),

              // ── Floating pin marker 3 (violet - Park, small background) ──
              Positioned(
                left: 180,
                top: 75,
                child: _buildPinMarker(
                  icon: Icons.park_rounded,
                  color: const Color(0xFFAB47BC),
                  small: true,
                ),
              ),

              // ── Floating pin marker 4 (amber - Shopping, far background) ──
              Positioned(
                right: 180,
                top: 25,
                child: _buildPinMarker(
                  icon: Icons.shopping_bag_rounded,
                  color: const Color(0xFFFFB74D),
                  small: true,
                ),
              ),

              // ── Bottom overlay with text + CTA ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF0A1018).withOpacity(0.9),
                        const Color(0xFF0A1018),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Left text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.view_in_ar_rounded, color: Color(0xFF4FC3F7), size: 16),
                                const SizedBox(width: 6),
                                const Text(
                                  'AR VIEW',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF4FC3F7),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF66BB6A),
                                  ),
                                ).animate(onPlay: (c) => c.repeat(reverse: true))
                                    .fade(begin: 0.3, end: 1.0, duration: 900.ms),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Point camera to discover places',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // CTA button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt_rounded, size: 15, color: Color(0xFF0A1018)),
                            SizedBox(width: 6),
                            Text(
                              'Open AR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0A1018),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  /// Mini place-info card used inside the AR preview.
  Widget _buildMiniPlaceCard({
    required String name,
    required String category,
    required String distance,
    required String rating,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.15), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withOpacity(0.2),
            ),
            child: Icon(Icons.location_on_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 10, color: const Color(0xFFFFD700)),
                  const SizedBox(width: 2),
                  Text(
                    rating,
                    style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    distance,
                    style: TextStyle(fontSize: 9, color: color.withOpacity(0.8), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pulsing neon icon bubble marker for the AR preview card.
  Widget _buildPinMarker({
    required IconData icon,
    required Color color,
    bool small = false,
  }) {
    final size = small ? 24.0 : 32.0;
    final iconSize = small ? 12.0 : 16.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0D1520),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          color: color,
          size: iconSize,
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1600.ms)
        .moveY(begin: -2, end: 2, duration: 2000.ms, curve: Curves.easeInOut);
  }

  /// Pulsing "LIVE" pill that signals the AR experience is ready to go.
  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.black.withOpacity(0.25),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulseController,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyIntelligence() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        String baseCurrency = 'USD';
        if (state is AuthAuthenticated) {
          baseCurrency = state.user.preferences['currency'] ?? 'USD';
        }

        return FutureBuilder<Map<String, double>>(
          future: CurrencyService.getExchangeRates(baseCurrency),
          builder: (context, snapshot) {
            final rates = snapshot.data ?? {};
            final topRates = ['USD', 'EUR', 'LKR', 'INR'].where((c) => c != baseCurrency).take(3).toList();

            return GlassCard(
              padding: const EdgeInsets.all(20),
              glowColor: AppColors.actionTeal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CURRENCY INTELLIGENCE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.actionTeal, letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Base: $baseCurrency',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.actionTeal.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.currency_exchange_rounded, color: AppColors.actionTeal, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent)
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: topRates.map((code) {
                        final rate = rates[code] ?? 0.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(code, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textTertiary)),
                            const SizedBox(height: 2),
                            Text(
                              rate.toStringAsFixed(2),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOdysseyCTA() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OdysseyPlannerPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.ratingGold.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(Icons.auto_mode_rounded, color: AppColors.ratingGold, size: 24),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.ratingGold, shape: BoxShape.circle),
                    child: const Icon(Icons.star, size: 8, color: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BUILD AN ODYSSEY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ratingGold,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Personalized Trip Mining',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
          ],
        ),
      ),
    ).animate().fade(delay: 400.ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildCategoryScroller(List<CategoryEntity> categories) {
    final List<CategoryEntity> resolvedCategories = categories.isNotEmpty 
        ? categories 
        : const [
            CategoryEntity(id: '1', name: 'Attractions', sortOrder: 1),
            CategoryEntity(id: '2', name: 'Food & Drink', sortOrder: 2),
            CategoryEntity(id: '3', name: 'Hotels', sortOrder: 3),
            CategoryEntity(id: '4', name: 'Shopping', sortOrder: 4),
            CategoryEntity(id: '5', name: 'Experiences', sortOrder: 5),
            CategoryEntity(id: '6', name: 'Medical', sortOrder: 6),
          ];

    final displayCategories = ['All', ...resolvedCategories.map((c) => c.name).where((name) => name != 'Transport')];
    
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: displayCategories.length,
        itemBuilder: (context, index) {
          final catName = displayCategories[index];
          final isActive = _selectedCategory == catName;
          
          return GestureDetector(
            onTap: () async {
              setState(() => _selectedCategory = catName);
              
              // Fetch nearby places for this category
              final position = await geo.Geolocator.getCurrentPosition();
              String? catId;
              if (catName != 'All') {
                catId = resolvedCategories.firstWhere((c) => c.name == catName).id;
              }
              
              if (mounted) {
                context.read<MapBloc>().add(FetchNearbyAttractions(
                  latitude: position.latitude,
                  longitude: position.longitude,
                  categoryId: catId,
                  categoryName: catName == 'All' ? null : catName,
                ));
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: isActive ? AppColors.primaryGradient : null,
                color: isActive ? null : AppColors.surfaceVariant,
                border: Border.all(
                  color: isActive ? Colors.transparent : AppColors.border,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10)]
                    : null,
              ),
              child: Center(
                child: Text(
                  catName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String action, {VoidCallback? onTap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        GestureDetector(
          onTap: onTap ?? () {},
          child: ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(
              Rect.fromLTWH(0, 0, b.width, b.height),
            ),
            child: Text(
              action,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingCards(List<AttractionEntity> attractions) {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: min(attractions.length, 5),
        itemBuilder: (context, index) {
          final p = attractions[index];
          return _buildPlaceCard(p, index);
        },
      ),
    );
  }

  Widget _buildShimmerTrendingCards() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SizedBox(
        height: 240,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              width: 200,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShimmerHiddenGemCards() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(
          children: List.generate(3, (index) {
            return Container(
              height: 84,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPlaceCard(AttractionEntity place, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: place.id,
          name: place.name,
          category: place.categoryName ?? 'Attraction', 
          rating: place.rating, 
          distance: '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', 
          emoji: '📍', 
          imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
          latitude: place.latitude,
          longitude: place.longitude,
        )),
      ),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16),
        child: Stack(
          children: [
            // Card background image + overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                image: DecorationImage(
                  image: _getImageProvider(
                  place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
                  place.categoryName ?? 'Attraction',
                  place.name,
                ),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon + category
                  Row(
                    children: [
                      const Text('📍', style: TextStyle(fontSize: 28)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white.withOpacity(0.2),
                        ),
                        child: Text(
                          place.categoryName ?? 'LANDMARK',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Name
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Rating & distance
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: AppColors.ratingGold),
                      const SizedBox(width: 4),
                      Text(
                        place.rating.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 3),
                      Text(
                        '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Action
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Text(
                      'Explore →',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.1, end: 0),
    );
  }

  Widget _buildHiddenGemCards(List<AttractionEntity> attractions) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: attractions.take(3).toList().asMap().entries.map((entry) {
          final p = entry.value;
          final i = entry.key;
          return _buildGemRow(p, i);
        }).toList(),
      ),
    );
  }

  Widget _buildGemRow(AttractionEntity place, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: place.id,
          name: place.name,
          category: place.categoryName ?? 'Attraction', 
          rating: place.rating, 
          distance: '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', 
          emoji: '📍', 
          imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
          latitude: place.latitude,
          longitude: place.longitude,
        )),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: place.photoUrls.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: place.photoUrls.first,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 52,
                        height: 52,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.image_rounded, size: 20, color: AppColors.textMuted),
                      ),
                      errorWidget: (_, __, ___) => _buildEmojiThumbnail(place.categoryName),
                    )
                  : _buildEmojiThumbnail(place.categoryName),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: AppColors.warning),
                      const SizedBox(width: 3),
                      Text('${place.rating}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text('${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.05, end: 0),
    );
  }

  Widget _buildClusterSuggestion(List<AttractionEntity> attractions) {
    if (attractions.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.secondaryGradient,
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Mini Tour Nearby',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Route items
          ...attractions.take(3).toList().asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            return Column(
              children: [
                _buildRouteItem('${i + 1}', p.name, '${((p.distanceM ?? 0) / 10).toStringAsFixed(0)} min walk', AppColors.primary),
                if (i < 2 && i < attractions.length - 1) _buildRouteConnector(),
              ],
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
              ),
              child: TextButton(
                onPressed: () {},
                child: Text(
                  'START TOUR',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fade(delay: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildRouteItem(String num, String name, String info, Color color) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.05),
            border: Border.all(color: Colors.black.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(num, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        Text(info, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _buildRouteConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 13),
      child: Container(width: 2, height: 20, color: AppColors.border),
    );
  }

  Widget _buildProximityAlert(AttractionEntity place) {
    return Positioned(
      bottom: 110,
      left: 20,
      right: 20,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        glowColor: AppColors.primary,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.15),
                  ),
                  child: Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROXIMITY ALERT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You are near ${place.name}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showProximityAlert = false),
                  child: Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: AppColors.primaryGradient,
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttractionDetailPage(
                        id: place.id,
                        name: place.name,
                        category: place.categoryName ?? 'Attraction', 
                        rating: place.rating, 
                        distance: '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', 
                        emoji: '📍', 
                        imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
                        latitude: place.latitude,
                        longitude: place.longitude,
                      ))),
                      child: const Text('View Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArCameraPage(
                            initialPlace: {
                              'name': place.name,
                              'category': place.categoryName ?? 'Attraction',
                              'distance': '${((place.distanceM ?? 0)).toStringAsFixed(0)} m',
                              'distanceM': place.distanceM ?? 0,
                              'rating': place.rating ?? 0.0,
                              'latitude': place.latitude,
                              'longitude': place.longitude,
                            },
                          ),
                        ),
                      ),
                      child: Text('Start AR', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().slideY(begin: 1, end: 0, duration: 500.ms, curve: Curves.easeOutBack).fade(),
    );
  }

  ImageProvider _getImageProvider(String? url, String category, String name) {
    return PlaceImageHelper.getImageProvider(url, category, name);
  }

  Widget _buildEmojiThumbnail(String? category) {
    final cat = (category ?? '').toLowerCase();
    final String emoji;
    if (cat.contains('food') || cat.contains('drink') || cat.contains('restaurant') || cat.contains('cafe')) {
      emoji = '🍽';
    } else if (cat.contains('shop') || cat.contains('mall') || cat.contains('market')) {
      emoji = '🛍';
    } else if (cat.contains('hotel') || cat.contains('accommodation')) {
      emoji = '🏨';
    } else if (cat.contains('park') || cat.contains('nature') || cat.contains('garden')) {
      emoji = '🌿';
    } else if (cat.contains('museum') || cat.contains('heritage') || cat.contains('historic')) {
      emoji = '🏛';
    } else if (cat.contains('beach') || cat.contains('coast') || cat.contains('sea')) {
      emoji = '🏖';
    } else if (cat.contains('temple') || cat.contains('religious') || cat.contains('church')) {
      emoji = '⛩';
    } else {
      emoji = '📌';
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
    );
  }
}

/// L-shaped viewfinder bracket used to frame the AR spotlight card,
/// evoking a camera/AR scanning overlay.
class _ArCorner extends StatelessWidget {
  final bool top;
  final bool left;
  const _ArCorner({required this.top, required this.left});

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: Colors.white.withOpacity(0.5), width: 2);
    return SizedBox(
      width: 16,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: top ? side : BorderSide.none,
            bottom: top ? BorderSide.none : side,
            left: left ? side : BorderSide.none,
            right: left ? BorderSide.none : side,
          ),
        ),
      ),
    );
  }
}

/// Smaller viewfinder corner brackets for the mini AR preview inside the
/// homepage AR spotlight card.
class _MiniCorner extends StatelessWidget {
  final bool top;
  final bool left;
  const _MiniCorner({required this.top, required this.left});

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.6), width: 1.5);
    return SizedBox(
      width: 10,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: top ? side : BorderSide.none,
            bottom: top ? BorderSide.none : side,
            left: left ? side : BorderSide.none,
            right: left ? BorderSide.none : side,
          ),
        ),
      ),
    );
  }
}

class _SpotlightWorldMapPainter extends CustomPainter {
  final double rotation;
  final double tilt; // tilt angle in radians
  final List<_SpotlightPoint3D> points;
  final List<_SpotlightPoint3D> placePoints;

  _SpotlightWorldMapPainter({
    required this.rotation,
    required this.tilt,
    required this.points,
    required this.placePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Draw outer glow and sphere boundary
    final spherePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withOpacity(0.01),
          const Color(0xFF00E5FF).withOpacity(0.08),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, spherePaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw grid lines (parallels and meridians)
    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw parallels (latitude lines) every 30 degrees
    for (double latDeg = -60; latDeg <= 60; latDeg += 30) {
      final latRad = latDeg * pi / 180;
      final rLat = radius * cos(latRad);
      final yLat = radius * sin(latRad);

      final cy = center.dy + yLat * cos(tilt);
      final rect = Rect.fromCenter(
        center: Offset(center.dx, cy),
        width: rLat * 2,
        height: (rLat * 2 * sin(tilt)).abs(),
      );
      canvas.drawOval(rect, linePaint);
    }

    // Draw meridians (longitude lines) every 45 degrees
    for (double lngDeg = 0; lngDeg < 180; lngDeg += 45) {
      final lngRad = (lngDeg * pi / 180) + rotation;
      
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: (radius * 2 * sin(lngRad)).abs(), height: radius * 2),
        linePaint,
      );
      canvas.restore();
    }

    // Draw world map points (dots)
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (final pt in points) {
      // Rotate around Y-axis (spin)
      final rotLng = pt.lng + rotation;
      
      // 3D coordinates before tilt
      final x3d = radius * cos(pt.lat) * sin(rotLng);
      final y3d = radius * sin(pt.lat);
      final z3d = radius * cos(pt.lat) * cos(rotLng);

      // Apply tilt around X-axis (pitch)
      final xTilted = x3d;
      final yTilted = y3d * cos(tilt) - z3d * sin(tilt);
      final zTilted = y3d * sin(tilt) + z3d * cos(tilt);

      // Depth transparency (front = solid/bright, back = dimmed)
      final isFront = zTilted >= 0;
      final opacity = isFront 
          ? (0.15 + 0.5 * (zTilted / radius)).clamp(0.1, 0.7)
          : (0.02 + 0.05 * (1.0 + zTilted / radius)).clamp(0.01, 0.08);

      pointPaint.color = const Color(0xFF00E5FF).withOpacity(opacity);
      final size = isFront ? (1.0 + 1.2 * (zTilted / radius)) : 0.6;

      canvas.drawCircle(
        Offset(center.dx + xTilted, center.dy + yTilted),
        size,
        pointPaint,
      );
    }

    // Draw highlighted place points (yellow dots with pulsing ring)
    final placePaint = Paint()..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final pt in placePoints) {
      // Rotate around Y-axis (spin)
      final rotLng = pt.lng + rotation;
      
      // 3D coordinates before tilt
      final x3d = radius * cos(pt.lat) * sin(rotLng);
      final y3d = radius * sin(pt.lat);
      final z3d = radius * cos(pt.lat) * cos(rotLng);

      // Apply tilt around X-axis (pitch)
      final xTilted = x3d;
      final yTilted = y3d * cos(tilt) - z3d * sin(tilt);
      final zTilted = y3d * sin(tilt) + z3d * cos(tilt);

      // We only draw them if they are on the front side (facing viewer) for clean occlusion
      if (zTilted >= 0) {
        final opacity = (0.5 + 0.4 * (zTilted / radius)).clamp(0.2, 0.9);
        
        // Draw outer ring
        ringPaint.color = const Color(0xFFFFD54F).withOpacity(opacity * 0.4);
        canvas.drawCircle(
          Offset(center.dx + xTilted, center.dy + yTilted),
          6.0 * (zTilted / radius),
          ringPaint,
        );

        // Draw inner solid dot
        placePaint.color = const Color(0xFFFFD54F).withOpacity(opacity);
        canvas.drawCircle(
          Offset(center.dx + xTilted, center.dy + yTilted),
          3.0 * (zTilted / radius),
          placePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightWorldMapPainter old) {
    return old.rotation != rotation || old.tilt != tilt || old.placePoints != placePoints;
  }
}

class _SpotlightPoint3D {
  final double lat; // in radians
  final double lng; // in radians

  _SpotlightPoint3D(double latDeg, double lngDeg)
      : lat = latDeg * pi / 180,
        lng = lngDeg * pi / 180;
}
