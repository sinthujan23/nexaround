import 'dart:math';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
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
import 'package:nexaround_app/features/mini_tour/presentation/widgets/mini_tour_launcher.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'dart:async';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';

class _LocalEvent {
  final String title;
  final String time;
  final bool isOngoing;
  _LocalEvent({required this.title, required this.time, this.isOngoing = true});
}

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
  List<AttractionEntity>? _miniTourPlaces;
  bool _loadingMiniTour = false;
  bool _isPreFetching = false;

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
        _fetchMiniTourPlaces(position.latitude, position.longitude);
        _preFetchArPlaces(position.latitude, position.longitude);
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
          useLegacy: true,
        ));
        context.read<MapBloc>().add(const FetchCategories());
        _fetchMiniTourPlaces(position.latitude, position.longitude);
        _preFetchArPlaces(position.latitude, position.longitude);
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
        useLegacy: true,
      ));
      context.read<MapBloc>().add(const FetchCategories());
      _fetchMiniTourPlaces(6.9271, 79.8612);
      _preFetchArPlaces(6.9271, 79.8612);
    }
  }

  Future<void> _fetchMiniTourPlaces(double lat, double lng) async {
    if (_loadingMiniTour) return;
    setState(() => _loadingMiniTour = true);
    try {
      final places = await GooglePlacesService.fetchNearbyPlaces(
        latitude: lat,
        longitude: lng,
        radius: 2500,
        categoryName: 'Attractions',
        useLegacy: true,
      );
      
      final usable = places
          .where((p) => p.distanceM != null && p.distanceM! <= 3000)
          .toList()
        ..sort((a, b) {
          if (b.rating != a.rating) return b.rating.compareTo(a.rating);
          return a.distanceM!.compareTo(b.distanceM!);
        });

      if (mounted) {
        setState(() {
          _miniTourPlaces = usable;
          _loadingMiniTour = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching mini tour places for preview: $e');
      if (mounted) {
        setState(() => _loadingMiniTour = false);
      }
    }
  }

  Future<void> _preFetchArPlaces(double lat, double lng) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (_isPreFetching) {
      debugPrint('🚀 AR: Background pre-fetching already in progress, skipping duplicate call.');
      return;
    }
    _isPreFetching = true;
    debugPrint('🚀 Starting background AR pre-fetching (ranges sequential, categories parallel)...');
    
    final ranges = [2000, 5000, 10000, 25000, 50000];
    final categories = [
      null,
      'Food & Drink',
      'Shopping',
      'Attractions',
      'Hotels',
      'Medical',
      'Beach',
    ];

    Future.microtask(() async {
      try {
        debugPrint('🚀 Starting sequential background AR pre-fetching...');
        
        for (final radius in ranges) {
          if (!mounted) return;
          debugPrint('📥 Pre-fetching ALL categories for radius $radius m in parallel...');

          // Fetch all categories for this range simultaneously
          final results = await Future.wait(
            categories.map((cat) async {
              try {
                final places = await GooglePlacesService.fetchNearbyPlaces(
                  latitude: lat,
                  longitude: lng,
                  radius: radius,
                  categoryName: cat,
                );
                return places;
              } catch (e) {
                debugPrint('Error pre-fetching $cat at radius $radius: $e');
                return <dynamic>[];
              }
            }),
          );

          // Merge all category results and cache them immediately
          final allPlaces = results.expand((x) => x).toList();
          if (allPlaces.isNotEmpty) {
            final attractionJsons = allPlaces.map((p) => {
              'id': p.id,
              'name': p.name,
              'description': p.description,
              'history': p.history,
              'latitude': p.latitude,
              'longitude': p.longitude,
              'category_id': p.categoryId,
              'category_name': p.categoryName,
              'address': p.address,
              'opening_hours': p.openingHours,
              'entry_fee': p.entryFee,
              'currency': p.currency,
              'rating': p.rating,
              'review_count': p.reviewCount,
              'photo_urls': p.photoUrls,
              'tags': p.tags,
              'geofence_radius_m': p.geofenceRadiusM,
              'distance_m': p.distanceM,
              'is_active': p.isActive,
              'created_at': p.createdAt.toIso8601String(),
            }).toList();
            
            await CacheService.mergeAndCacheAttractions(attractionJsons);
            debugPrint('✅ Cached ${allPlaces.length} places for radius $radius m');
          }
        }
        debugPrint('✅ Background AR pre-fetching complete.');
      } finally {
        _isPreFetching = false;
      }
    });
  }

  int _getDiscoverTabIndex(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('food')) return 0;
    if (cat.contains('attraction') || cat.contains('experience')) return 1;
    if (cat.contains('shop')) return 2;
    return 0; // Default to food
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
                        child: ValueListenableBuilder<int>(
                          valueListenable: CacheService.notificationsNotifier,
                          builder: (_, __, ___) => _buildGlassCircle(
                            Icons.notifications_none_rounded,
                            badge: CacheService.unreadNotifications(),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const NotificationsPage()),
                            ),
                          ),
                        ),
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
      
                  // Computed lists
                  ...() {
                    if (state.status == MapStatus.loading || state.status == MapStatus.initial || state.attractions.isEmpty) {
                      return [
                        // Trending Shimmer
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader('🔥  Trending Near You', null),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildShimmerTrendingCards()),

                        // Nearby Shimmer
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader('✨  Near You', null),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildShimmerHiddenGemCards()),
                      ];
                    }

                    // Filter out private residences and personal markers to keep only public/walkable spots
                    bool isPublicSpot(AttractionEntity place) {
                      final name = place.name.toLowerCase();
                      final desc = (place.description ?? '').toLowerCase();
                      final tags = place.tags.map((t) => t.toLowerCase()).toList();
                      
                      final privateKeywords = [
                        'home', 'house', 'residence', "'s place", 'my place', 'my home', 
                        'private', 'personal', 'apartment', 'flat', 'villa'
                      ];
                      
                      // Check name/description for private indicators
                      for (final keyword in privateKeywords) {
                        if (name.contains(keyword)) {
                          // Allow public historic/museum houses
                          if (name.contains('museum') || name.contains('historic') || name.contains('heritage') || name.contains('public')) {
                            continue;
                          }
                          return false;
                        }
                      }
                      
                      // Filter out residential tags
                      if (tags.any((t) => t.contains('home') || t.contains('private') || t.contains('residential') || t.contains('personal'))) {
                        return false;
                      }
                      
                      return true;
                    }

                    final publicAttractions = state.attractions.where(isPublicSpot).toList();
                    final trendingPlaces = List<AttractionEntity>.from(publicAttractions)
                      ..sort((a, b) => _trendingScore(b).compareTo(_trendingScore(a)));

                    return [
                      // Trending Near You
                      if (trendingPlaces.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader(
                              '🔥  Trending Near You', 
                              'See all',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildTrendingCards(trendingPlaces)),
                      ],

                      // Near You
                      if (publicAttractions.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader(
                              '✨  Near You', 
                              null,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildHiddenGemCards(publicAttractions)),
                      ],
                    ];
                  }(),
      
                  // Cluster suggestion
                  ...() {
                    if (_loadingMiniTour || _miniTourPlaces == null || _miniTourPlaces!.length < 3) {
                      return <Widget>[const SliverToBoxAdapter(child: SizedBox.shrink())];
                    }

                    return <Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _buildClusterSuggestion(_miniTourPlaces!),
                        ),
                      ),
                    ];
                  }(),
      
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

  Widget _buildGlassCircle(IconData icon, {VoidCallback? onTap, int badge = 0}) {
    final circle = ClipRRect(
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
    if (onTap == null && badge == 0) return circle;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
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
                  color: AppColors.brandGreen,
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
                  color: AppColors.brandGreen,
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
                                    color: AppColors.brandGreen,
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
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandGreen.withOpacity(0.3),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Compass emblem
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandGreen.withOpacity(0.16),
                    border: Border.all(
                      color: AppColors.brandGreen.withOpacity(0.5),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(Icons.explore_rounded,
                      color: AppColors.brandGreen, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BUILD AN ODYSSEY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandGreen,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Chart your journey with AI',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandGreen,
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _odysseyRouteLine(),
            const SizedBox(height: 12),
            // View all generated trip plans → Plans section (My Odysseys tab).
            // Its own tap handler so it doesn't trigger the card's "build" action.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => HomePage.homeKey.currentState?.switchToPlans(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.list_alt_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'VIEW MY ODYSSEYS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fade(delay: 400.ms).slideX(begin: 0.1, end: 0);
  }

  /// A green dotted "voyage" route with stops, evoking an odyssey/journey.
  Widget _odysseyRouteLine() {
    Widget dot({double size = 7}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.brandGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppColors.brandGreen.withOpacity(0.5), blurRadius: 6),
            ],
          ),
        );
    Widget dashes() => Expanded(
          child: LayoutBuilder(
            builder: (ctx, c) {
              final int n = (c.maxWidth / 9).floor().clamp(3, 40).toInt();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  n,
                  (_) => Container(
                    width: 4,
                    height: 2,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              );
            },
          ),
        );
    return Row(
      children: [
        dot(),
        const SizedBox(width: 6),
        dashes(),
        const SizedBox(width: 6),
        dot(),
        const SizedBox(width: 6),
        dashes(),
        const SizedBox(width: 6),
        dot(),
        const SizedBox(width: 6),
        dashes(),
        const SizedBox(width: 6),
        dot(size: 9),
      ],
    );
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
                  useLegacy: true,
                ));
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isActive ? AppColors.brandGreen : AppColors.surfaceVariant,
                border: Border.all(
                  color: isActive ? Colors.transparent : AppColors.border,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.3), blurRadius: 10)]
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

  Widget _buildSectionHeader(String title, String? action, {VoidCallback? onTap}) {
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
        if (action != null && action.isNotEmpty)
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



  _LocalEvent? _getEventForPlace(AttractionEntity place) {
    final name = place.name.toLowerCase();
    final tags = place.tags.map((t) => t.toLowerCase()).toList();
    final cat = (place.categoryName ?? '').toLowerCase();

    if (name.contains('park') || tags.any((t) => t.contains('park') || t.contains('nature') || t.contains('garden'))) {
      return _LocalEvent(
        title: 'Farmers Market & Food Fest',
        time: 'Sat & Sun · 9 AM - 6 PM',
        isOngoing: DateTime.now().weekday == DateTime.saturday || DateTime.now().weekday == DateTime.sunday,
      );
    }
    if (name.contains('museum') || name.contains('art') || name.contains('gallery') || tags.any((t) => t.contains('museum') || t.contains('art') || t.contains('gallery') || t.contains('culture'))) {
      return _LocalEvent(
        title: 'Art Exhibition & History Tour',
        time: 'Daily · 10 AM - 5 PM',
        isOngoing: true,
      );
    }
    if (name.contains('cafe') || name.contains('coffee') || name.contains('restaurant') || name.contains('pub') || name.contains('bar') || cat.contains('food')) {
      return _LocalEvent(
        title: 'Live Acoustic Session',
        time: 'Tonight · 7 PM - 10 PM',
        isOngoing: true,
      );
    }
    if (name.contains('stadium') || name.contains('hall') || name.contains('center') || name.contains('college') || name.contains('school') || tags.any((t) => t.contains('stadium') || t.contains('college') || t.contains('education'))) {
      return _LocalEvent(
        title: 'Community Music Fest',
        time: 'Live Now · 4 PM - 9 PM',
        isOngoing: true,
      );
    }
    return null;
  }

  _LocalEvent _getEventOrTrendingInfo(AttractionEntity place) {
    final event = _getEventForPlace(place);
    if (event != null) return event;
    return _LocalEvent(
      title: 'Popular Local Gathering',
      time: 'Trending Near You',
      isOngoing: false,
    );
  }

  bool _hasEventOpportunity(AttractionEntity place) {
    return _getEventForPlace(place) != null;
  }

  /// Ranks a place for the "Trending Near You" row. A place trends when many
  /// people rate it highly (social proof) AND it's close by. Pure function of
  /// already-loaded data — no network calls, so this is instant and free.
  double _trendingScore(AttractionEntity place) {
    // Quality: rating (0–5) → 0–1.
    final double quality = place.rating.clamp(0.0, 5.0) / 5.0;

    // Buzz: review count, log-scaled so 500 reviews ≫ 5 reviews but doesn't
    // 100× dominate. log10(reviews + 1) / 3 ≈ 1.0 around 1000 reviews.
    final double buzz =
        (log(place.reviewCount + 1) / ln10 / 3.0).clamp(0.0, 1.0);

    // Proximity: closer = higher. Full credit at 0 m, none beyond 5 km. When
    // distance is unknown (null/0) this is 1.0, so quality + buzz decide.
    final double dist = (place.distanceM ?? 0).toDouble();
    final double proximity = (1.0 - dist / 5000.0).clamp(0.0, 1.0);

    // Event Bonus: If the place has tags/types indicating it is an event venue,
    // we add a strong multiplier/bonus.
    final bool isEventVenue = _hasEventOpportunity(place);
    final double eventBonus = isEventVenue ? 0.35 : 0.0;

    return (quality * 0.35) + (buzz * 0.35) + (proximity * 0.15) + eventBonus;
  }

  Widget _buildTrendingCards(List<AttractionEntity> attractions) {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: min(attractions.length, 10),
        itemBuilder: (context, index) {
          final p = attractions[index];
          return _buildPlaceCard(p, index);
        },
      ),
    );
  }

  Widget _buildShimmerTrendingCards() {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        itemBuilder: (context, index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey[200]!,
            highlightColor: Colors.grey[50]!,
            period: const Duration(milliseconds: 1500),
            child: Container(
              width: 200,
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 60,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 100,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 45,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 40,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 80,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShimmerHiddenGemCards() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: List.generate(2, (index) {
                  return Container(
                    height: index == 0 ? 160.0 : 120.0,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: List.generate(2, (index) {
                  return Container(
                    height: index == 0 ? 130.0 : 150.0,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  );
                }),
              ),
            ),
          ],
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Background Image or Fallback
              Positioned.fill(
                child: (() {
                  final hasImage = place.photoUrls.isNotEmpty;
                  final imageUrl = hasImage ? place.photoUrls.first : null;
                  final resolvedUrl = imageUrl != null && imageUrl.startsWith('/')
                      ? '${ApiConstants.baseUrl}$imageUrl'
                      : imageUrl;

                  Widget buildFallbackBackground() {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.withOpacity(0.3),
                            AppColors.surfaceVariant,
                          ],
                        ),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Center(
                        child: Opacity(
                          opacity: 0.15,
                          child: Icon(
                            _getCategoryIcon(place.categoryName ?? 'Attraction', place.name),
                            size: 100,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }

                  return resolvedUrl != null && resolvedUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: resolvedUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
                            ),
                          ),
                          errorWidget: (_, __, ___) => buildFallbackBackground(),
                        )
                      : buildFallbackBackground();
                })(),
              ),
              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.black.withOpacity(0.2),
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

                  // Dynamic Event Badge
                  (() {
                    final eventInfo = _getEventOrTrendingInfo(place);
                    final hasEvent = _getEventForPlace(place) != null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasEvent ? Colors.red.withOpacity(0.25) : AppColors.brandGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasEvent ? Colors.red.withOpacity(0.4) : AppColors.brandGreen.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasEvent ? Icons.campaign_rounded : Icons.trending_up_rounded,
                            size: 11,
                            color: hasEvent ? Colors.redAccent[100] : AppColors.brandGreen,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              eventInfo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  })(),

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
                        '${place.rating} (${place.reviewCount})',
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
      ),
    ),
  ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.1, end: 0);
  }

  String _getCategoryImagePath(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('nature')) return 'assets/images/cat_nature.png';
    if (cat.contains('hotel') || cat.contains('stay')) return 'assets/images/cat_hotels.png';
    if (cat.contains('shop')) return 'assets/images/cat_shopping.png';
    if (cat.contains('food')) return 'assets/images/cat_food.png';
    if (cat.contains('medical') || cat.contains('hospital')) return 'assets/images/cat_medical.png';
    if (cat.contains('historic') || cat.contains('history') || cat.contains('museum')) return 'assets/images/cat_historical.png';
    return 'assets/images/cat_nature.png'; // default
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
        return Colors.orange.withOpacity(0.08);
      case 'Attractions':
        return Colors.teal.withOpacity(0.08);
      case 'Shopping':
        return Colors.blue.withOpacity(0.08);
      case 'Medical':
        return Colors.red.withOpacity(0.08);
      default:
        return Colors.white.withOpacity(0.08);
    }
  }

  Color _getCategoryBorderColor(String category) {
    switch (category) {
      case 'Food':
        return Colors.orange.withOpacity(0.2);
      case 'Attractions':
        return Colors.teal.withOpacity(0.2);
      case 'Shopping':
        return Colors.blue.withOpacity(0.2);
      case 'Medical':
        return Colors.red.withOpacity(0.2);
      default:
        return Colors.white.withOpacity(0.2);
    }
  }

  String _getDirectionString(double? userLat, double? userLng, double placeLat, double placeLng) {
    if (userLat == null || userLng == null) return '';
    final latDiff = placeLat - userLat;
    final lngDiff = placeLng - userLng;
    
    // Simple 8-point compass calculation
    final angle = atan2(lngDiff, latDiff) * 180 / pi;
    final normalizedAngle = (angle + 360) % 360;
    
    if (normalizedAngle >= 337.5 || normalizedAngle < 22.5) return 'N';
    if (normalizedAngle >= 22.5 && normalizedAngle < 67.5) return 'NE';
    if (normalizedAngle >= 67.5 && normalizedAngle < 112.5) return 'E';
    if (normalizedAngle >= 112.5 && normalizedAngle < 157.5) return 'SE';
    if (normalizedAngle >= 157.5 && normalizedAngle < 202.5) return 'S';
    if (normalizedAngle >= 202.5 && normalizedAngle < 247.5) return 'SW';
    if (normalizedAngle >= 247.5 && normalizedAngle < 292.5) return 'W';
    return 'NW';
  }

  Widget _buildCategoryCard(String categoryName, List<AttractionEntity> places, int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Card Container
        Container(
          margin: const EdgeInsets.only(bottom: 24, top: 12), // Margin to allow top/bottom pop-out
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06), // Frosted glass style
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _getCategoryBorderColor(categoryName),
              width: 1.0,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.12),
                _getCategoryColor(categoryName),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Category Header Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getCategoryBorderColor(categoryName),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        categoryName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Places list
                    Padding(
                      padding: const EdgeInsets.only(right: 32), // Added padding to avoid overlapping the protruding icon
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: () {
                          // Make sure we have exactly 5 items to show per box to align heights
                          final List<AttractionEntity> displayList = [];
                          if (places.isNotEmpty) {
                            while (displayList.length < 5) {
                              displayList.addAll(places);
                            }
                          }
                          final finalPlaces = displayList.take(5).toList();

                          return finalPlaces.map((place) {
                            final distText = '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km';
                            final dirText = _getDirectionString(_userLatitude, _userLongitude, place.latitude, place.longitude);

                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttractionDetailPage(
                                    id: place.id,
                                    name: place.name,
                                    category: place.categoryName ?? 'Attraction',
                                    rating: place.rating,
                                    distance: distText,
                                    emoji: '📍',
                                    imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
                                    latitude: place.latitude,
                                    longitude: place.longitude,
                                  ),
                                ),
                              ),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.location_on_rounded,
                                        size: 14,
                                        color: AppColors.brandGreen.withOpacity(0.8),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        place.name,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        distText,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (dirText.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _getCategoryBorderColor(categoryName).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _getCategoryBorderColor(categoryName).withOpacity(0.3),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          dirText,
                                          style: TextStyle(
                                            color: _getCategoryBorderColor(categoryName).withOpacity(0.9),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList();
                        }(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 3D Pop-out Category Icon
        Positioned(
          top: -2,
          right: -4,
          child: Image.asset(
            _getCategoryImagePath(categoryName),
            width: 52,
            height: 52,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }

  Widget _buildHiddenGemCards(List<AttractionEntity> attractions) {
    if (attractions.isEmpty) return const SizedBox.shrink();

    // Group by category name mapping
    final Map<String, List<AttractionEntity>> grouped = {};
    for (final place in attractions) {
      String category = place.categoryName ?? 'Places';
      final catLower = category.toLowerCase();

      if (catLower.contains('food') || catLower.contains('drink') || catLower.contains('restaurant') || catLower.contains('cafe')) {
        category = 'Food';
      } else if (catLower.contains('shop') || catLower.contains('mall') || catLower.contains('market') || catLower.contains('store')) {
        category = 'Shopping';
      } else if (catLower.contains('medical') || catLower.contains('hospital') || catLower.contains('clinic') || catLower.contains('doctor') || catLower.contains('pharmacy')) {
        category = 'Medical';
      } else {
        category = 'Attractions';
      }
      grouped.putIfAbsent(category, () => []).add(place);
    }
    final List<AttractionEntity> genericPlaces = grouped['Places'] ?? [];
    grouped.remove('Places');

    // Ensure all 4 categories have at least 3 places.
    final orderedCategories = ['Food', 'Attractions', 'Shopping', 'Medical'];
    
    // First guarantee every category exists in the map
    for (final cat in orderedCategories) {
      grouped.putIfAbsent(cat, () => []);
    }

    // Now populate empty categories with generic places so they have content
    for (final cat in orderedCategories) {
      if (grouped[cat]!.isEmpty && genericPlaces.isNotEmpty) {
        final takeCount = genericPlaces.length >= 5 ? 5 : genericPlaces.length;
        grouped[cat]!.addAll(genericPlaces.sublist(0, takeCount));
        genericPlaces.removeRange(0, takeCount);
      }
    }

    // Reuse borrow logic
    for (final cat in orderedCategories) {
      if (grouped[cat]!.isEmpty) {
        String? bestCat;
        int maxLen = 0;
        for (final otherCat in orderedCategories) {
          if (otherCat != cat && grouped[otherCat]!.length > maxLen) {
            maxLen = grouped[otherCat]!.length;
            bestCat = otherCat;
          }
        }
        if (bestCat != null && grouped[bestCat]!.isNotEmpty) {
          grouped[cat]!.addAll(grouped[bestCat]!);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _buildCategoryCard('Food', grouped['Food']!, 0),
          _buildCategoryCard('Attractions', grouped['Attractions']!, 1),
          _buildCategoryCard('Shopping', grouped['Shopping']!, 2),
          _buildCategoryCard('Medical', grouped['Medical']!, 3),
        ],
      ),
    );
  }


  Widget _buildClusterSuggestion(List<AttractionEntity> attractions) {
    if (attractions.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      glowColor: AppColors.brandGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Take a walk',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Route items
          ...attractions.take(5).toList().asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final totalStops = min(attractions.length, 5);

            final dist = p.distanceM;
            final distLabel = dist == null
                ? '—'
                : (dist < 1000 ? '${dist.toInt()} m' : '${(dist / 1000).toStringAsFixed(1)} km');
            final walkMin = dist == null ? 0 : (dist / 80).round();
            final walkLabel = walkMin <= 0 ? '' : ' · $walkMin min walk';
            final info = '$distLabel$walkLabel';

            return Column(
              children: [
                _buildRouteItem('${i + 1}', p.name, info, AppColors.primary),
                if (i < totalStops - 1) _buildRouteConnector(),
              ],
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.brandGreen.withOpacity(0.35)),
              ),
              child: TextButton(
                onPressed: () => launchMiniTour(
                  context,
                  lat: _userLatitude,
                  lng: _userLongitude,
                  areaName: _currentLocationName,
                  preFetchedPlaces: attractions,
                ),
                child: const Text(
                  'START TOUR',
                  style: TextStyle(
                    color: AppColors.brandGreen,
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

  IconData _getCategoryIcon(String category, String name) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();
    
    if (cat.contains('food') || cat.contains('drink') || cat.contains('restaurant') || cat.contains('cafe') || nm.contains('cafe') || nm.contains('restaurant')) {
      if (cat.contains('cafe') || cat.contains('coffee') || nm.contains('cafe') || nm.contains('coffee')) {
        return Icons.coffee_rounded;
      }
      if (cat.contains('street') || cat.contains('fast') || nm.contains('burger') || nm.contains('pizza')) {
        return Icons.local_pizza_rounded;
      }
      return Icons.restaurant_rounded;
    }
    
    if (cat.contains('shop') || cat.contains('mall') || cat.contains('market') || cat.contains('store')) {
      if (cat.contains('clothing') || cat.contains('fashion') || nm.contains('fashion') || nm.contains('boutique')) {
        return Icons.shopping_bag_rounded;
      }
      if (cat.contains('market') || cat.contains('local') || nm.contains('market') || nm.contains('bazaar')) {
        return Icons.storefront_rounded;
      }
      return Icons.shopping_cart_rounded;
    }
    
    if (cat.contains('hotel') || cat.contains('accommodation') || cat.contains('stay') || cat.contains('lodging')) {
      return Icons.hotel_rounded;
    }
    
    if (cat.contains('park') || cat.contains('nature') || cat.contains('garden') || cat.contains('forest') || cat.contains('beach')) {
      return Icons.park_rounded;
    }
    
    if (cat.contains('museum') || cat.contains('gallery') || nm.contains('museum') || nm.contains('gallery')) {
      return Icons.museum_rounded;
    }
    
    return Icons.attractions_rounded;
  }

  ImageProvider _getImageProvider(String? url, String category, String name) {
    return PlaceImageHelper.getImageProvider(url, category, name);
  }

  ImageProvider? _getNetworkImageProvider(String? url) {
    if (url == null || url.isEmpty || url == 'null') return null;
    String resolvedUrl = url;
    if (resolvedUrl.startsWith('/')) {
      resolvedUrl = '${ApiConstants.baseUrl}$resolvedUrl';
    }
    return CachedNetworkImageProvider(resolvedUrl);
  }

  bool _shouldShowImageForPlace(AttractionEntity place) {
    return true;
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
