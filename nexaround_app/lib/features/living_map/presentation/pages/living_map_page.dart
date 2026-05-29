import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
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
    _checkLocationAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
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
                          _buildAIPromptBar(),
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
                Text(
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

  Widget _buildAIPromptBar() {
    final prompt = 'What\'s the local vibe and hidden gems around $_currentLocationName? Give me your best insider tips!';
    return GestureDetector(
      onTap: () => HomePage.homeKey.currentState?.switchToNeva(prompt),
      child: GlassCard(
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.primary,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Image.asset(
                'assets/images/neva_avatar.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEET NEVA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"Neva, what\'s the secret vibe here?"',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Icon(Icons.mic_rounded, color: AppColors.primary, size: 18),
          ),
        ],
      ),
    ),
    ).animate().fade(delay: 300.ms).slideY(begin: 0.1, end: 0);
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




