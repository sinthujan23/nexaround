import 'dart:math';
import 'dart:ui';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
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
import 'package:nexaround_app/core/constants/countries.dart';
import 'package:nexaround_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/ar_mode/presentation/pages/ar_camera_page.dart';
import 'package:nexaround_app/features/food_radar/presentation/pages/discover_page.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nexaround_app/features/travel_stories/data/models/travel_story.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/travel_story_card.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/post_story_sheet.dart';
import 'package:nexaround_app/features/travel_stories/presentation/widgets/stories_comments_dialog.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/travel_stories_page.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/travel_journal_page.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/location_search_modal.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/animated_neva_banner.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/discovery_engine_sheet.dart';
import 'package:nexaround_app/features/planning/presentation/pages/museums_list_page.dart';
import 'package:nexaround_app/core/services/avatar_service.dart';

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
  double? _lastFetchedLatitude;
  double? _lastFetchedLongitude;
  StreamSubscription<geo.Position>? _positionSubscription;
  bool _isLocationServiceEnabled = true;
  bool _isLocationOverridden = false;

  // We'll use the state data instead of these dummy lists

  String _currentLocationName = 'Locating...';
  List<AttractionEntity>? _miniTourPlaces;
  bool _loadingMiniTour = false;
  bool _isPreFetching = false;

  String? _currentDistrict;
  String? _lastFetchedDistrict;
  List<AttractionEntity> _geminiTrendingPlaces = [];
  bool _loadingGeminiTrending = false;
  List<TravelStory> _travelStories = [];
  bool _isFetchingRouteDistances = false;
  Set<String> _routeDistanceFetchedIds = {};

  String? _geminiTrendingMarkdown;
  final Map<String, Map<String, String>> _parsedAiDetails = {};
  List<AiExperience> _aiExperiences = [];
  final Map<String, String> _unresolvedPhotos = {};
  String? _geminiError;
  final Map<String, double> _routeDistanceCache = {};

  @override
  void initState() {
    super.initState();
    _loadTravelStories();
    CacheService.cacheAttractions([]);
    CacheService.clearLastFetchCoords();
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
      _SpotlightPoint3D(40.7, -74.0), // New York
      _SpotlightPoint3D(51.5, -0.1), // London
      _SpotlightPoint3D(35.7, 139.7), // Tokyo
      _SpotlightPoint3D(48.9, 2.3), // Paris
      _SpotlightPoint3D(-33.9, 151.2), // Sydney
      _SpotlightPoint3D(25.2, 55.3), // Dubai
      _SpotlightPoint3D(-22.9, -43.2), // Rio de Janeiro
      _SpotlightPoint3D(-33.9, 18.4), // Cape Town
      _SpotlightPoint3D(19.1, 72.9), // Mumbai
      _SpotlightPoint3D(1.3, 103.8), // Singapore
      _SpotlightPoint3D(41.9, 12.5), // Rome
      _SpotlightPoint3D(30.0, 31.2), // Cairo
    ];

    CacheService.discoveryResultNotifier.addListener(_onDiscoveryResultChanged);
    _checkLocationAndInit();
  }

  List<_SpotlightPoint3D> _generateWorldMapPoints() {
    final List<_SpotlightPoint3D> points = [];
    final random = Random(42); // Seeded for consistency

    void addLandmass(
      double minLat,
      double maxLat,
      double minLng,
      double maxLng,
      int count,
    ) {
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
    CacheService.discoveryResultNotifier.removeListener(_onDiscoveryResultChanged);
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
    _positionSubscription =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 100,
          ),
        ).listen((position) async {
          if (_isLocationOverridden) return;

          // ── 500m Distance-Threshold Throttling (Smart Geofencing) ──
          // If the user moves less than 500m, update the live blue dot only.
          // Do NOT send any network, reverse-geocode, or place requests!
          if (_lastFetchedLatitude != null && _lastFetchedLongitude != null) {
            final distM = geo.Geolocator.distanceBetween(
              _lastFetchedLatitude!,
              _lastFetchedLongitude!,
              position.latitude,
              position.longitude,
            );
            if (distM < 500) {
              if (mounted) {
                setState(() {
                  _userLatitude = position.latitude;
                  _userLongitude = position.longitude;
                });
              }
              return;
            }
          }

          _lastFetchedLatitude = position.latitude;
          _lastFetchedLongitude = position.longitude;
          
          final details = await GooglePlacesService.reverseGeocodeDetailed(
            position.latitude,
            position.longitude,
          );
          final locationName = details['location_name'] ?? 'Nearby';
          final district = details['district'] ?? 'Nearby';

          if (mounted) {
            setState(() {
              _userLatitude = position.latitude;
              _userLongitude = position.longitude;
              _currentLocationName = locationName;
              _currentDistrict = district;
            });

            // Fetch new places for the new neighborhood (Redis > DB > Google)
            context.read<MapBloc>().add(
              FetchNearbyAttractions(
                latitude: position.latitude,
                longitude: position.longitude,
                categoryName: _selectedCategory == 'All' ? null : _selectedCategory,
              ),
            );

            _fetchMiniTourPlaces(position.latitude, position.longitude);
            _preFetchArPlaces(position.latitude, position.longitude);
          }
        });
  }

  bool _isTrendingSpot(AttractionEntity place) {
    final name = place.name.toLowerCase();
    final tags = place.tags.map((t) => t.toLowerCase()).toList();

    // Exclude utility keywords in the name
    final utilityKeywords = [
      'pharmacy',
      'hospital',
      'clinic',
      'medical',
      'doctor',
      'dentist',
      'bank',
      'atm',
      'office',
      'school',
      'college',
      'university',
      'class',
      'gas station',
      'petrol',
      'fuel',
      'garage',
      'repair',
      'grocery',
      'supermarket',
      'mart',
      'store',
      'shop',
      'hardware',
      'laundry',
      'residential',
      'apartment',
      'flat',
      'villa',
      'complex',
      'house',
    ];

    for (final kw in utilityKeywords) {
      if (name.contains(kw)) return false;
    }

    // Exclude official Google Places types/tags
    final utilityTags = [
      'pharmacy',
      'hospital',
      'doctor',
      'dentist',
      'bank',
      'atm',
      'school',
      'university',
      'gas_station',
      'grocery_or_supermarket',
      'supermarket',
      'store',
      'local_government_office',
      'general_contractor',
      'physiotherapist',
      'real_estate_agency',
    ];

    if (tags.any((t) => utilityTags.contains(t))) return false;

    return true;
  }

  Future<void> _fetchGeminiTrending(
    String district,
    double lat,
    double lng,
  ) async {
    // Gemini trending is now disabled on the map screen in favor of
    // the Database/Redis Discover method.
    return;
  }

  void _resolveUnresolvedCardPhotos() {
    // Unresolved photo search loop disabled to eliminate legacy findplacefromtext calls
  }

  Future<void> _searchPhotoForUnresolved(String name) async {
    // Disabled to prevent legacy Google Places API charges
  }

  bool _shareSignificantWords(String name1, String name2) {
    final stopWords = {
      'and',
      'the',
      'of',
      'in',
      'at',
      'with',
      'for',
      'a',
      'an',
      '&',
      'to',
      'or',
      'on',
      'by',
      'harbor',
      'harbour',
    };
    final words1 = name1
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();
    final words2 = name2
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();

    final intersection = words1.intersection(words2);
    if (intersection.isNotEmpty) {
      if (intersection.length >= 2) return true;
      if (words1.length == 1 || words2.length == 1) return true;
    }
    return false;
  }

  void _parseMarkdownDetails(String markdown) {
    _parsedAiDetails.clear();
    _aiExperiences.clear();

    // Robust split: handle ### , ## , and ** headings from Gemini
    final headerPattern = RegExp(r'#{2,3}\s+');
    final segments = markdown.split(headerPattern);
    if (segments.length <= 1) {
      // Fallback: try splitting on bold markers (**Name**)
      final boldPattern = RegExp(r'\*\*([^*]+)\*\*');
      final boldMatches = boldPattern.allMatches(markdown).toList();
      if (boldMatches.length >= 3) {
        // Reconstruct segments from bold headers
        final reconstructed = <String>[];
        for (int i = 0; i < boldMatches.length; i++) {
          final end = i + 1 < boldMatches.length
              ? boldMatches[i + 1].start
              : markdown.length;
          final name = boldMatches[i].group(1) ?? '';
          final body = markdown.substring(boldMatches[i].end, end);
          reconstructed.add('$name\n$body');
        }
        _parseSegments(reconstructed, markdown);
        return;
      }
      return;
    }
    _parseSegments(segments.sublist(1), markdown);
  }

  void _parseSegments(List<String> segments, String markdown) {

    final hiddenGemsIndex = markdown.toLowerCase().indexOf('hidden gem');

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      // Try to find the original position in the full markdown
      final segmentIndex = markdown.indexOf(segment.substring(0, segment.length.clamp(0, 30)));
      final isGem = hiddenGemsIndex != -1 && segmentIndex > hiddenGemsIndex;

      final lines = segment.split('\n');
      var rawName = lines[0].trim();
      if (rawName.startsWith('[') && rawName.endsWith(']')) {
        rawName = rawName.substring(1, rawName.length - 1).trim();
      } else if (rawName.startsWith('[') && rawName.contains(']')) {
        final closingBracket = rawName.indexOf(']');
        rawName = rawName.substring(1, closingBracket).trim();
      }

      final lowerName = rawName.toLowerCase().trim();
      if (lowerName.contains("why it's worth leaving home for") ||
          lowerName.contains("why locals love it") ||
          lowerName.contains("why you'll love it") ||
          lowerName.contains("event or experience name") ||
          lowerName.contains("hidden gem name")) {
        continue;
      }

      final Map<String, String> details = {};
      String currentKey = '';
      StringBuffer currentValue = StringBuffer();

      for (int j = 1; j < lines.length; j++) {
        final line = lines[j].trim();
        if (line.isEmpty) continue;
        if (line.startsWith('---')) continue;

        final lowerLine = line.toLowerCase();
        if (lowerLine.startsWith("why you'll love it:") ||
            lowerLine.startsWith("why locals love it:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'why';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("distance:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'distance';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("travel time:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'travelTime';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("when:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'when';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("cost:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'cost';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("best for:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'bestFor';
          currentValue = StringBuffer()
            ..write(line.substring(line.indexOf(':') + 1).trim());
        } else if (lowerLine.startsWith("confidence score:")) {
          if (currentKey.isNotEmpty)
            details[currentKey] = currentValue.toString().trim();
          currentKey = 'confidence';
          final rawVal = line.substring(line.indexOf(':') + 1).trim();
          final cleanVal = rawVal
              .split(RegExp(r'\s*\-\s*'))
              .first
              .replaceAll(RegExp(r'[\s\-]+$'), '')
              .trim();
          currentValue = StringBuffer()..write(cleanVal);
        } else {
          if (currentKey.isNotEmpty) {
            currentValue.write(' ' + line);
          }
        }
      }
      if (currentKey.isNotEmpty) {
        details[currentKey] = currentValue.toString().trim();
      }

      _parsedAiDetails[lowerName] = details;
      _aiExperiences.add(
        AiExperience(
          name: rawName,
          type: isGem ? 'gem' : 'event',
          why: details['why'] ?? '',
          distance: details['distance'] ?? '',
          travelTime: details['travelTime'] ?? '',
          when: details['when'] ?? '',
          cost: details['cost'] ?? '',
          bestFor: details['bestFor'] ?? '',
          confidence: details['confidence'] ?? '',
        ),
      );
    }
    _resolveUnresolvedCardPhotos();
  }

  Future<void> _fetchInitialData() async {
    try {
      // Permissions already granted by HomePage
      final position = await PermissionService.getSafePosition();
      if (position == null) {
        _useFallbackLocation();
        return;
      }

      _lastFetchedLatitude = position.latitude;
      _lastFetchedLongitude = position.longitude;

      // Reverse geocode to get human readable address and district
      final details = await GooglePlacesService.reverseGeocodeDetailed(
        position.latitude,
        position.longitude,
      );
      final locationName = details['location_name'] ?? 'Nearby';
      final district = details['district'] ?? 'Nearby';

      if (mounted) {
        setState(() {
          _userLatitude = position.latitude;
          _userLongitude = position.longitude;
          _currentLocationName = locationName;
          _currentDistrict = district;
        });

        // Load places cleanly from Database & Cache (0 Gemini cost)
        context.read<MapBloc>().add(
          FetchNearbyAttractions(
            latitude: position.latitude,
            longitude: position.longitude,
            useLegacy: false,
          ),
        );
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
      _lastFetchedLatitude = 6.9271;
      _lastFetchedLongitude = 79.8612;

      setState(() {
        _currentLocationName = 'Colombo, Sri Lanka';
        _currentDistrict = 'Colombo District';
        _userLatitude = 6.9271; // Fallback to Colombo
        _userLongitude = 79.8612;
      });

      // Fetch data with fallback location from Database & Cache (0 Gemini cost)
      context.read<MapBloc>().add(
        FetchNearbyAttractions(
          latitude: 6.9271,
          longitude: 79.8612,
          useLegacy: false,
        ),
      );
      context.read<MapBloc>().add(const FetchCategories());
      _fetchMiniTourPlaces(6.9271, 79.8612);
      _preFetchArPlaces(6.9271, 79.8612);
    }
  }

  Future<void> _forceRefreshAroundYou() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refreshing places around you...')),
    );
    await CacheService.clearHybridPlacesCache();
    GooglePlacesService.clearErrors();
    await _fetchInitialData();
  }

  Widget _buildAroundYouRefreshButton() {
    return GestureDetector(
      onTap: () {
        final homeState = context.findAncestorStateOfType<HomePageState>();
        if (homeState != null) {
          homeState.switchToDiscover();
        } else {
          _showDiscoveryEngineSheet(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'More',
              style: TextStyle(
                color: AppColors.brandGreen,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.brandGreen, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchMiniTourPlaces(double lat, double lng) async {
    if (_loadingMiniTour) return;
    
    // Check MapBloc state first — if attractions are already loaded, use them (0 network calls)
    try {
      final stateAttractions = context.read<MapBloc>().state.attractions;
      if (stateAttractions.isNotEmpty) {
        final existing = stateAttractions.where((p) {
          final cat = (p.categoryName ?? '').toLowerCase();
          final name = p.name.toLowerCase();
          return cat.contains('poi') || cat.contains('attraction') || cat.contains('museum') || cat.contains('park') || cat.contains('nature') || cat.contains('beach') || name.contains('park') || name.contains('temple');
        }).take(5).toList();
        if (existing.isNotEmpty) {
          setState(() {
            _miniTourPlaces = existing;
            _loadingMiniTour = false;
          });
          return;
        }
      }
    } catch (_) {}

    setState(() => _loadingMiniTour = true);
    try {
      final places = await GooglePlacesService.fetchNearbyPlaces(
        latitude: lat,
        longitude: lng,
        radius: 2500,
        categoryName: 'POI',
        useLegacy: false,
      );

      final uniquePlaces = <String, AttractionEntity>{};
      for (final p in places) {
        if (p.distanceM != null && p.distanceM! <= 3000) {
          final normName = p.name.trim().toLowerCase();
          if (!uniquePlaces.containsKey(normName) &&
              !uniquePlaces.values.any((x) => x.id == p.id)) {
            uniquePlaces[normName] = p;
          }
        }
      }

      final usable = uniquePlaces.values.toList()
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
    // Disabled background prefetching to save unnecessary Google/backend calls.
    // AR mode fetches its required places on-demand when the user opens AR view.
    return;
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
        final masterAttractions = state.allAttractions.isNotEmpty ? state.allAttractions : state.attractions;
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_off,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Location is off. Enable location for nearby attractions.',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                geo.Geolocator.openLocationSettings(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.warning,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            child: const Text(
                              'ENABLE',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
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
                    floating: false,
                    pinned: true,
                    automaticallyImplyLeading: false,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    toolbarHeight: 64,
                    titleSpacing: 24,
                    centerTitle: false,
                    flexibleSpace: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          color: AppColors.background.withOpacity(0.85),
                        ),
                      ),
                    ),
                    title: _buildExploringCard(),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Emergency Icon
                            _buildGlassCircle(
                              Icons.emergency_rounded,
                              bgColor: AppColors.error.withOpacity(0.15),
                              iconColor: AppColors.error,
                              onTap: () {
                                final homeState = context.findAncestorStateOfType<HomePageState>();
                                if (homeState != null) {
                                  homeState.switchToDiscover(initialTab: 6);
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            // Profile Avatar
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, authState) {
                                final user = authState is AuthAuthenticated ? authState.user : null;
                                return GestureDetector(
                                  onTap: () {
                                    final homeState = context.findAncestorStateOfType<HomePageState>();
                                    if (homeState != null) {
                                      homeState.switchToProfile();
                                    }
                                  },
                                  child: UserAvatarView(
                                    user: user,
                                    size: 38,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Bell Icon
                            ValueListenableBuilder<int>(
                              valueListenable: CacheService.notificationsNotifier,
                              builder: (_, __, ___) => _buildGlassCircle(
                                Icons.notifications_none_rounded,
                                badge: CacheService.unreadNotifications(),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsPage(),
                                  ),
                                ),
                              ),
                            ),
                          ],
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

                  ...() {
                    if (state.status == MapStatus.loading ||
                        state.status == MapStatus.initial ||
                        masterAttractions.isEmpty) {
                      return [
                        // Travel Stories (Where Was I?)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader(
                              'Travel Stories',
                              null,
                              customAction: _buildTravelStoriesHeaderAction(),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildTravelStoriesFeed()),

                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: _buildSectionHeader(
                              !_isLocationOverridden
                                  ? 'Around You'
                                  : (_currentLocationName == 'Locating...' || _currentLocationName.isEmpty || _currentLocationName == 'Unknown' 
                                      ? 'Around You' 
                                      : 'Around $_currentLocationName'),
                              null,
                              imageIconPath: 'assets/images/near.png',
                              customAction: _buildAroundYouRefreshButton(),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _buildShimmerHiddenGemCards(),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            child: _buildMuseumBanner(),
                          ),
                        ),

                        /*
                        // Curated For You Shimmer
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: _buildSectionHeader(
                              'Curated For You',
                              null,
                              imageIconPath: 'assets/images/popular.png',
                              customAction: _buildNevaReportButton(),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildShimmerTrendingCards()),
                        */
                      ];
                    }

                    // Filter out private residences and personal markers to keep only public/walkable spots
                    bool isPublicSpot(AttractionEntity place) {
                      final name = place.name.toLowerCase();
                      final desc = (place.description ?? '').toLowerCase();
                      final tags = place.tags
                          .map((t) => t.toLowerCase())
                          .toList();

                      final privateKeywords = [
                        'home',
                        'house',
                        'residence',
                        "'s place",
                        'my place',
                        'my home',
                        'private',
                        'personal',
                        'apartment',
                        'flat',
                        'villa',
                        'homestay',
                        'guest house',
                        'guesthouse',
                        '3bhk',
                        '2bhk',
                        '4bhk',
                        '1bhk',
                        'cottage',
                        'bungalow',
                        'stay',
                      ];

                      // Check name/description for private indicators
                      for (final keyword in privateKeywords) {
                        if (name.contains(keyword)) {
                          // Allow public historic/museum houses
                          if (name.contains('museum') ||
                              name.contains('historic') ||
                              name.contains('heritage') ||
                              name.contains('public')) {
                            continue;
                          }
                          return false;
                        }
                      }

                      // Filter out residential tags
                      if (tags.any(
                        (t) =>
                            t.contains('home') ||
                            t.contains('private') ||
                            t.contains('residential') ||
                            t.contains('personal'),
                      )) {
                        return false;
                      }

                      return true;
                    }

                    final publicAttractions = masterAttractions
                        .where(isPublicSpot)
                        .toList();
                    final trendingPlaces = _geminiTrendingPlaces.isNotEmpty
                        ? _geminiTrendingPlaces
                        : (List<AttractionEntity>.from(publicAttractions)..sort(
                            (a, b) =>
                                _trendingScore(b).compareTo(_trendingScore(a)),
                          ));

                    final showTrendingLoading =
                        _loadingGeminiTrending && _geminiTrendingPlaces.isEmpty;

                    return [
                      // Travel Stories (Where Was I?)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                          child: _buildSectionHeader(
                            'Travel Stories',
                            null,
                            customAction: _buildTravelStoriesHeaderAction(),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildTravelStoriesFeed()),

                      if (publicAttractions.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: _buildSectionHeader(
                              !_isLocationOverridden
                                  ? 'Around You'
                                  : (_currentLocationName == 'Locating...' || _currentLocationName.isEmpty || _currentLocationName == 'Unknown' 
                                      ? 'Around You' 
                                      : 'Around $_currentLocationName'),
                              null,
                              imageIconPath: 'assets/images/near.png',
                              customAction: _buildAroundYouRefreshButton(),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _buildHiddenGemCards(publicAttractions, state.status),
                        ),
                      ],

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: _buildMuseumBanner(),
                        ),
                      ),

                      /*
                      // Curated For You
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                          child: _buildSectionHeader(
                            'Curated For You',
                            null,
                            imageIconPath: 'assets/images/popular.png',
                            customAction: _buildNevaReportButton(),
                          ),
                        ),
                      ),
                      if (_loadingGeminiTrending && _aiExperiences.isEmpty)
                        SliverToBoxAdapter(child: _buildShimmerTrendingCards())
                      else if (_aiExperiences.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _buildTrendingPlacesList(state),
                        )
                      else if (_geminiError != null)
                        SliverToBoxAdapter(
                          child: _buildCuratedErrorCard(),
                        )
                      else
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            child: Text(
                              'No popular recommendations found nearby.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      */
                    ];
                  }(),

                  // Cluster suggestion
                  ...() {
                    if (_miniTourPlaces != null &&
                        _miniTourPlaces!.length >= 3) {
                      return <Widget>[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: _buildClusterSuggestion(_miniTourPlaces!),
                          ),
                        ),
                      ];
                    }

                    if (_loadingMiniTour) {
                      return <Widget>[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child:
                                Container(
                                      width: double.infinity,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 34,
                                                  height: 34,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  width: 100,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade300,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ...List.generate(
                                            3,
                                            (_) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 6,
                                                  ),
                                              child: Container(
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    .animate(onPlay: (c) => c.repeat())
                                    .shimmer(
                                      duration: 1200.ms,
                                      color: Colors.white54,
                                    ),
                          ),
                        ),
                      ];
                    }

                    return <Widget>[
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                    ];
                  }(),

                  const SliverToBoxAdapter(child: SizedBox(height: 75)),
                ],
              ),
              
              // Floating Neva Banner (below App Bar on the right)
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                right: 0,
                child: AnimatedNevaBanner(
                  onTap: () {
                    _showDiscoveryEngineSheet(context);
                  },
                ),
              ),

              // Proximity alert bottom sheet
              if (_showProximityAlert && masterAttractions.isNotEmpty)
                _buildProximityAlert(masterAttractions.first),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMuseumBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MuseumsListPage()),
        ),
        child: Container(
          height: 102,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF020617),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Right side: modern museum image fading into the dark card background
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 150,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/museum_banner_bg.png',
                          fit: BoxFit.cover,
                        ),
                        // Linear gradient overlay to fade the image out to the left
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                Colors.transparent,
                                Color(0xFF0F172A), // Matches start color of card gradient
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Content Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'TOP MUSEUMS OF THE WORLD',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  color: AppColors.brandGreen),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Curated Master Guides',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                wordSpacing: 4.0,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Expert routes for 5h, 1 day or 2 days',
                              style: TextStyle(fontSize: 11, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white38, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildExploringCard() {
    return GestureDetector(
      onTap: () => _showLocationSearchModal(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.brandGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.brandGreen.withOpacity(0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.near_me_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'EXPLORING',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandGreen,
                        letterSpacing: 2,
                      ),
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
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  void _showLocationSearchModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const LocationSearchModal(),
    ).then((result) async {
      if (result != null && result is Map) {
        final double lat = result['latitude'];
        final double lng = result['longitude'];
        final String name = result['name'];
        final String district = result['district'];
        
        setState(() {
          _isLocationOverridden = true;
          _userLatitude = lat;
          _userLongitude = lng;
          _currentLocationName = name;
          _currentDistrict = district;
          
          CacheService.overriddenLatitude = lat;
          CacheService.overriddenLongitude = lng;
          
          // Clear previous data so UI shows loading state
          _geminiTrendingPlaces = [];
          _aiExperiences = [];
          _miniTourPlaces = null;
        });

        // Clear cache so it forces a fresh fetch
        await CacheService.clearHybridPlacesCache();
        GooglePlacesService.clearErrors();

        // Trigger updates for new location
        if (mounted) {
          _lastFetchedLatitude = lat;
          _lastFetchedLongitude = lng;
          _fetchMiniTourPlaces(lat, lng);
          
          // Re-fetch "Around You" map places from Database / Redis
          context.read<MapBloc>().add(
            FetchNearbyAttractions(
              latitude: lat,
              longitude: lng,
              radius: 5000,
              forceRefresh: true,
            ),
          );
        }
      } else if (result == 'clear_override') {
        // Clear override and show loading briefly
        setState(() {
          _isLocationOverridden = false;
          _currentLocationName = 'Locating...';
          CacheService.overriddenLatitude = null;
          CacheService.overriddenLongitude = null;
        });

        // Force an immediate GPS update instead of waiting for the stream
        try {
          final position = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.high,
          );
          
          final details = await GooglePlacesService.reverseGeocodeDetailed(
            position.latitude,
            position.longitude,
          );
          final locationName = details['location_name'] ?? 'Nearby';
          final district = details['district'] ?? 'Nearby';

          if (mounted) {
            _lastFetchedLatitude = position.latitude;
            _lastFetchedLongitude = position.longitude;

            setState(() {
              _userLatitude = position.latitude;
              _userLongitude = position.longitude;
              _currentLocationName = locationName;
              _currentDistrict = district;
              
              // Clear previous data so UI shows loading state
              _geminiTrendingPlaces = [];
              _aiExperiences = [];
              _miniTourPlaces = null;
            });
            
            // Clear cache so it forces a fresh fetch
            await CacheService.clearHybridPlacesCache();
            GooglePlacesService.clearErrors();
            
            _fetchMiniTourPlaces(position.latitude, position.longitude);
            context.read<MapBloc>().add(
              FetchNearbyAttractions(
                latitude: position.latitude,
                longitude: position.longitude,
                radius: 5000,
              ),
            );
          }
        } catch (e) {
          debugPrint('Error getting current location on override clear: $e');
        }
        
        _checkLocationAndInit();
      }
    });
  }

  void _onDiscoveryResultChanged() {
    if (mounted && CacheService.discoveryResultNotifier.value != null) {
      _showDiscoveryEngineSheet(context);
    }
  }

  void _showDiscoveryEngineSheet(BuildContext parentContext) {
    final readyResult = CacheService.discoveryResultNotifier.value;
    if (readyResult != null) {
      CacheService.discoveryResultNotifier.value = null; // Clear the badge
    }

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DiscoveryEngineSheet(
        locationName: _currentLocationName,
        district: _currentDistrict,
        latitude: _userLatitude,
        longitude: _userLongitude,
        initialResult: readyResult,
        onPlaceSelected: (placeName) async {
          if (!mounted) return;
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: Text('Locating $placeName...'),
              duration: const Duration(seconds: 1),
            ),
          );
          
          try {
            final results = await GooglePlacesService.searchPlaces(
              query: placeName,
              latitude: _userLatitude ?? 6.9271,
              longitude: _userLongitude ?? 79.8612,
            );
            
            if (!mounted) return;
            
            if (results.isNotEmpty) {
              final matchedPlace = results.first;
              Navigator.push(
                parentContext,
                MaterialPageRoute(
                  builder: (_) => SmartTourismMapPage(
                    initialLat: matchedPlace.latitude,
                    initialLng: matchedPlace.longitude,
                    destinationName: matchedPlace.name,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(content: Text('Could not locate $placeName on the map.')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(content: Text('Error finding place.')),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildGlassCircle(
    IconData icon, {
    VoidCallback? onTap,
    int badge = 0,
    Widget? customChild,
    Color? bgColor,
    Color? iconColor,
  }) {
    final circle = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor ?? AppColors.glassWhite,
            border: Border.all(color: bgColor != null ? bgColor.withOpacity(0.4) : AppColors.glassBorder),
          ),
          child: customChild ?? Icon(icon, color: iconColor ?? (bgColor != null ? Colors.white : AppColors.textPrimary), size: 20),
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
        if (hour >= 12 && hour < 17)
          timeGreeting = 'Good Afternoon';
        else if (hour >= 17 || hour < 5)
          timeGreeting = 'Good Evening';

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
      onTap: () => (context.findAncestorStateOfType<HomePageState>() ?? HomePage.homeKey.currentState)?.switchToAr(),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          // Dark background simulating a camera viewfinder
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2838), Color(0xFF0F1923), Color(0xFF0A1018)],
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
                  [0.1, 0.7],
                  [0.25, 0.5],
                  [0.4, 0.65],
                  [0.55, 0.45],
                  [0.7, 0.6],
                  [0.85, 0.4],
                  [0.15, 0.85],
                  [0.6, 0.8],
                ];
                final colors = [
                  const Color(0xFFFFB74D),
                  const Color(0xFF4FC3F7),
                  const Color(0xFFAED581),
                  const Color(0xFFFF8A65),
                  const Color(0xFF81D4FA),
                  const Color(0xFFFFD54F),
                  const Color(0xFFA5D6A7),
                  const Color(0xFFCE93D8),
                ];
                return Positioned(
                  left: positions[i][0] * 350,
                  top: positions[i][1] * 200,
                  child:
                      Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors[i].withOpacity(0.3),
                            ),
                          )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(
                            begin: 0.2,
                            end: 0.6,
                            duration: Duration(milliseconds: 1500 + i * 300),
                          ),
                );
              }),

              // ── Viewfinder corner brackets ──
              const Positioned(
                top: 14,
                left: 14,
                child: _ArCorner(top: true, left: true),
              ),
              const Positioned(
                top: 14,
                right: 14,
                child: _ArCorner(top: true, left: false),
              ),
              const Positioned(
                bottom: 14,
                left: 14,
                child: _ArCorner(top: false, left: true),
              ),
              const Positioned(
                bottom: 14,
                right: 14,
                child: _ArCorner(top: false, left: false),
              ),

              // ── Floating place card 1 (left side) ──
              Positioned(
                left: 20,
                top: 30,
                child:
                    _buildMiniPlaceCard(
                          name: 'Café Mocha',
                          category: 'Food & Drink',
                          distance: '85 m',
                          rating: '4.6',
                          color: AppColors.brandGreen,
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(
                          begin: -5,
                          end: 5,
                          duration: 2800.ms,
                          curve: Curves.easeInOut,
                        )
                        .fade(begin: 0.7, end: 1.0, duration: 2800.ms),
              ),

              // ── Floating place card 2 (right side) ──
              Positioned(
                right: 16,
                top: 50,
                child:
                    _buildMiniPlaceCard(
                          name: 'City Museum',
                          category: 'Attraction',
                          distance: '320 m',
                          rating: '4.9',
                          color: const Color(0xFFEF5350),
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(
                          begin: 4,
                          end: -4,
                          duration: 3200.ms,
                          curve: Curves.easeInOut,
                        )
                        .moveX(
                          begin: -2,
                          end: 2,
                          duration: 4000.ms,
                          curve: Curves.easeInOut,
                        ),
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
                                const Icon(
                                  Icons.view_in_ar_rounded,
                                  color: Color(0xFF4FC3F7),
                                  size: 16,
                                ),
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
                                    )
                                    .animate(
                                      onPlay: (c) => c.repeat(reverse: true),
                                    )
                                    .fade(
                                      begin: 0.3,
                                      end: 1.0,
                                      duration: 900.ms,
                                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              size: 15,
                              color: Color(0xFF0A1018),
                            ),
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
        boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12)],
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
                  Icon(
                    Icons.star_rounded,
                    size: 10,
                    color: const Color(0xFFFFD700),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    rating,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    distance,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
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
            child: Icon(icon, color: color, size: iconSize),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1.1, 1.1),
          duration: 1600.ms,
        )
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
            final topRates = [
              'USD',
              'EUR',
              'LKR',
              'INR',
            ].where((c) => c != baseCurrency).take(3).toList();

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
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.actionTeal,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Base: $baseCurrency',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.actionTeal.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.currency_exchange_rounded,
                          color: AppColors.actionTeal,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: topRates.map((code) {
                        final rate = rates[code] ?? 0.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              code,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              rate.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
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
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF003D3E), Color(0xFF001F20)],
          ),
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
                  child: const Icon(
                    Icons.explore_rounded,
                    color: AppColors.brandGreen,
                    size: 24,
                  ),
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
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
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
              onTap: () => (context.findAncestorStateOfType<HomePageState>() ?? HomePage.homeKey.currentState)?.switchToPlans(),
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
            color: AppColors.brandGreen.withOpacity(0.5),
            blurRadius: 6,
          ),
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
            CategoryEntity(id: '1', name: 'Food & Drink', sortOrder: 1),
            CategoryEntity(id: '2', name: 'POI', sortOrder: 2),
            CategoryEntity(id: '3', name: 'Shopping', sortOrder: 3),
            CategoryEntity(id: '4', name: 'Experiences', sortOrder: 4),
            CategoryEntity(id: '5', name: 'Medical', sortOrder: 5),
          ];

    final displayCategories = [
      'All',
      ...resolvedCategories
          .map((c) => c.name)
          .where((name) => name != 'Transport'),
    ];

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

              double lat = _userLatitude ?? 0.0;
              double lng = _userLongitude ?? 0.0;

              if (lat == 0.0 || lng == 0.0) {
                final position = await geo.Geolocator.getCurrentPosition();
                lat = position.latitude;
                lng = position.longitude;
              }

              String? catId;
              if (catName != 'All') {
                catId = resolvedCategories
                    .firstWhere((c) => c.name == catName)
                    .id;
              }

              if (mounted) {
                context.read<MapBloc>().add(
                  FetchNearbyAttractions(
                    latitude: lat,
                    longitude: lng,
                    categoryId: catId,
                    categoryName: catName == 'All' ? null : catName,
                    useLegacy: false,
                  ),
                );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isActive
                    ? AppColors.brandGreen
                    : AppColors.surfaceVariant,
                border: Border.all(
                  color: isActive ? Colors.transparent : AppColors.border,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.brandGreen.withOpacity(0.3),
                          blurRadius: 10,
                        ),
                      ]
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

  String _selectedCountryFilter = 'Global';
  String _modalSearchQuery = '';

  void _showCountryFilterBottomSheet() {
    _modalSearchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 12),
                    child: Row(
                      children: const [
                        Text(
                          'Filter by Country',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        onChanged: (val) {
                          setModalState(() {
                            _modalSearchQuery = val.trim();
                          });
                        },
                        style: const TextStyle(color: Colors.black87),
                        decoration: const InputDecoration(
                          hintText: 'Search country...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        ListTile(
                          leading: const Text('🌐', style: TextStyle(fontSize: 18)),
                          title: const Text('Global (All)', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                          trailing: _selectedCountryFilter == 'Global'
                              ? const Icon(Icons.check, color: AppColors.brandGreen)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedCountryFilter = 'Global';
                            });
                            _loadTravelStories();
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(height: 1),
                        ...countriesList
                            .where((c) => _modalSearchQuery.isEmpty || c.toLowerCase().contains(_modalSearchQuery.toLowerCase()))
                            .map((country) {
                          final isSelected = _selectedCountryFilter == country;
                          return ListTile(
                            title: Text(country, style: const TextStyle(color: Colors.black87)),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: AppColors.brandGreen)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedCountryFilter = country;
                              });
                              _loadTravelStories();
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTravelStoriesHeaderAction() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _showCountryFilterBottomSheet,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedCountryFilter == 'Global'
                    ? '🌐 Global'
                    : (_selectedCountryFilter.length > 14
                        ? '${_selectedCountryFilter.substring(0, 12)}...'
                        : _selectedCountryFilter),
                style: const TextStyle(
                  color: AppColors.brandGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: AppColors.brandGreen, size: 20),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _showPostStorySheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF00695C), // dark teal
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '+ Share',
              style: TextStyle(
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

  Future<void> _loadTravelStories() async {
    try {
      final stories = await TravelStoriesService().getStories(
        country: _selectedCountryFilter == 'Global' ? null : _selectedCountryFilter,
      );
      if (mounted) {
        setState(() {
          _travelStories = stories.where((s) => !s.isJournal).toList();
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load travel stories: $e');
    }
  }

  void _navigateToTravelStories(int startIndex) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TravelStoriesPage(
          stories: _travelStories,
          initialIndex: startIndex,
          onStoryDeleted: (storyId) {
            setState(() {
              _travelStories.removeWhere((s) => s.id == storyId);
            });
          },
        ),
      ),
    );
    // Refresh stories from server when returning, so we pick up
    // changes from other users (new stories, deletions, etc.)
    _loadTravelStories();
  }

  void _showPostStorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return PostStorySheet(
          userLatitude: _userLatitude ?? 6.9271,
          userLongitude: _userLongitude ?? 79.8612,
          onStorySubmitted: (newStory) async {
            // Send to backend first to persist in DB and get the real UUID
            final savedStory = await TravelStoriesService().addStory(newStory);
            if (mounted) {
              setState(() {
                _travelStories.insert(0, savedStory ?? newStory);
              });
            }
          },
        );
      },
    );
  }

  void _showCommentsDialog(TravelStory story) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StoriesCommentsDialog(
          story: story,
          imageIndex: 0,
          onCommentAdded: (commentText, imgIndex) {
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildTravelStoriesFeed() {
    if (_travelStories.isEmpty) {
      return Container(
        height: 160,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 36,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No travel stories posted yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap "+ Share" to post your experience!',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 425,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 12, 6, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _travelStories.length,
        itemBuilder: (context, index) {
          final story = _travelStories[index];
          return TravelStoryCard(
            story: story,
            onLikeTap: () {
              TravelStoriesService().toggleLike(story.id);
            },
            onCommentTap: () => _showCommentsDialog(story),
            onLocationTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exploring ${story.locationName}...'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            onTap: () => _navigateToTravelStories(index),
          );
        },
      ),
    );
  }


  Widget _buildSectionHeader(
    String title,
    String? action, {
    String? imageIconPath,
    VoidCallback? onTap,
    VoidCallback? onTitleTap,
    Widget? customAction,
  }) {
    final headerContent = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (imageIconPath != null) ...[
          Image.asset(
            imageIconPath,
            width: 36,
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (onTitleTap != null) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppColors.textSecondary,
          ),
        ],
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        onTitleTap != null
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTitleTap,
                child: headerContent,
              )
            : headerContent,
        if (customAction != null)
          customAction
        else if (action != null && action.isNotEmpty)
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

  Widget _buildNevaReportButton() {
    final hasReport = _geminiTrendingMarkdown != null;

    Widget buttonContent = GestureDetector(
      onTap: hasReport ? _showAiReportBottomSheet : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: hasReport
                ? [
                    AppColors.primary.withOpacity(0.9),
                    AppColors.actionTeal.withOpacity(0.9),
                  ]
                : [Colors.grey.shade800, Colors.grey.shade900],
          ),
          border: Border.all(
            color: hasReport
                ? AppColors.actionTeal.withOpacity(0.5)
                : Colors.white24,
            width: 1,
          ),
          boxShadow: hasReport
              ? [
                  BoxShadow(
                    color: AppColors.actionTeal.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular Neva Avatar
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/images/neva_avatar.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Report icon
            Icon(
              Icons.analytics_outlined,
              size: 14,
              color: hasReport ? Colors.white : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              'Report',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: hasReport ? Colors.white : Colors.grey.shade400,
              ),
            ),
            if (hasReport) ...[
              const SizedBox(width: 4),
              // Pulse/Live indicator dot
              Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.5, 1.5),
                    duration: 800.ms,
                  )
                  .fadeIn(duration: 800.ms),
            ],
          ],
        ),
      ),
    );

    if (hasReport) {
      // Pulsating scale loop animation
      return buttonContent
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(
            begin: const Offset(0.97, 0.97),
            end: const Offset(1.03, 1.03),
            duration: 1200.ms,
            curve: Curves.easeInOutSine,
          );
    }

    return buttonContent;
  }

  _LocalEvent? _getEventForPlace(AttractionEntity place) {
    final name = place.name.toLowerCase();
    final tags = place.tags.map((t) => t.toLowerCase()).toList();
    final cat = (place.categoryName ?? '').toLowerCase();

    if (name.contains('park') ||
        tags.any(
          (t) =>
              t.contains('park') ||
              t.contains('nature') ||
              t.contains('garden'),
        )) {
      return _LocalEvent(
        title: 'Farmers Market & Food Fest',
        time: 'Sat & Sun · 9 AM - 6 PM',
        isOngoing:
            DateTime.now().weekday == DateTime.saturday ||
            DateTime.now().weekday == DateTime.sunday,
      );
    }
    if (name.contains('museum') ||
        name.contains('art') ||
        name.contains('gallery') ||
        tags.any(
          (t) =>
              t.contains('museum') ||
              t.contains('art') ||
              t.contains('gallery') ||
              t.contains('culture'),
        )) {
      return _LocalEvent(
        title: 'Art Exhibition & History Tour',
        time: 'Daily · 10 AM - 5 PM',
        isOngoing: true,
      );
    }
    if (name.contains('cafe') ||
        name.contains('coffee') ||
        name.contains('restaurant') ||
        name.contains('pub') ||
        name.contains('bar') ||
        cat.contains('food')) {
      return _LocalEvent(
        title: 'Live Acoustic Session',
        time: 'Tonight · 7 PM - 10 PM',
        isOngoing: true,
      );
    }
    if (name.contains('stadium') ||
        name.contains('hall') ||
        name.contains('center') ||
        name.contains('college') ||
        name.contains('school') ||
        tags.any(
          (t) =>
              t.contains('stadium') ||
              t.contains('college') ||
              t.contains('education'),
        )) {
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
      time: 'Popular on You',
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
    final double buzz = (log(place.reviewCount + 1) / ln10 / 3.0).clamp(
      0.0,
      1.0,
    );

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

  Widget _buildCuratedErrorCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () {
          if (_currentDistrict != null &&
              _userLatitude != null &&
              _userLongitude != null) {
            setState(() {
              _geminiError = null;
              _lastFetchedDistrict = null;
            });
            _fetchGeminiTrending(
              _currentDistrict!,
              _userLatitude!,
              _userLongitude!,
            );
          }
        },
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1E2E),
                const Color(0xFF0D1117),
              ],
            ),
            border: Border.all(
              color: Colors.redAccent.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withOpacity(0.15),
                  border: Border.all(
                    color: Colors.redAccent.withOpacity(0.3),
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Could not load recommendations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check your connection and try again',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingPlacesList(MapState state) {
    // Pre-filter AI experiences to only those that resolve to a real Google Place
    final resolvedExperiences = <AiExperience>[];
    final resolvedMap = <AiExperience, AttractionEntity>{};

    for (final exp in _aiExperiences) {
      final lowerExpName = exp.name.toLowerCase().trim();
      AttractionEntity? resolvedPlace;
      
      // Try to find a resolved Google Place matching the AI recommendation name
      for (final p in _geminiTrendingPlaces) {
        final lowerPName = p.name.toLowerCase().trim();
        if (lowerPName == lowerExpName ||
            lowerPName.contains(lowerExpName) ||
            lowerExpName.contains(lowerPName) ||
            _shareSignificantWords(lowerPName, lowerExpName)) {
          resolvedPlace = p;
          break;
        }
      }

      if (resolvedPlace == null) {
        for (final p in state.allAttractions.isNotEmpty ? state.allAttractions : state.attractions) {
          final lowerPName = p.name.toLowerCase().trim();
          if (lowerPName == lowerExpName ||
              lowerPName.contains(lowerExpName) ||
              lowerExpName.contains(lowerPName) ||
              _shareSignificantWords(lowerPName, lowerExpName)) {
            resolvedPlace = p;
            break;
          }
        }
      }

      if (resolvedPlace != null) {
        resolvedExperiences.add(exp);
        resolvedMap[exp] = resolvedPlace;
      }
    }

    if (resolvedExperiences.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Text(
          'No popular recommendations found nearby.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: resolvedExperiences.length,
        itemBuilder: (context, index) {
          final exp = resolvedExperiences[index];
          final resolvedPlace = resolvedMap[exp]!;
          return _buildPlaceCard(resolvedPlace, index);
        },
      ),
    );
  }

  Widget _buildAiExperienceList() {
    return SizedBox(
      height: 245,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _aiExperiences.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildAiReportCard();
          }
          final exp = _aiExperiences[index - 1];
          return _buildAiExperienceCard(exp, index - 1);
        },
      ),
    );
  }

  Widget _buildAiExperienceCard(AiExperience exp, int index) {
    final isEvent = exp.type == 'event';
    final badgeColor = isEvent ? AppColors.actionTeal : AppColors.ratingGold;
    final badgeBg = isEvent
        ? AppColors.actionTeal.withOpacity(0.1)
        : AppColors.ratingGold.withOpacity(0.1);

    String matchText = '90%';
    if (exp.confidence.isNotEmpty) {
      final cleanConf = exp.confidence
          .replaceAll('/100', '')
          .replaceAll('%', '')
          .trim();
      if (int.tryParse(cleanConf) != null) {
        matchText = '$cleanConf%';
      } else {
        matchText = exp.confidence;
      }
    }

    return GestureDetector(
          onTap: () => _showAiExperienceDetailsBottomSheet(exp),
          child: Container(
            width: 220,
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Badge Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: badgeBg,
                      ),
                      child: Text(
                        isEvent ? 'EVENT' : 'GEM',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.actionTeal.withOpacity(0.08),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 10,
                            color: AppColors.actionTeal,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            matchText,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.actionTeal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Title
                Text(
                  exp.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                // When Info
                if (exp.when.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: AppColors.actionTeal,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            exp.when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Distance Info
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 11,
                      color: AppColors.actionTeal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        exp.distance.isNotEmpty
                            ? '${exp.distance}${exp.travelTime.isNotEmpty ? ' (${exp.travelTime})' : ''}'
                            : 'Nearby',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 8),
                // Description / Why you'll love it
                Text(
                  exp.why,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary.withOpacity(0.85),
                    height: 1.3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fade(delay: Duration(milliseconds: 80 * index))
        .slideX(begin: 0.1, end: 0);
  }

  void _showAiExperienceDetailsBottomSheet(AiExperience exp) {
    final lowerName = exp.name.toLowerCase().trim();
    AttractionEntity? matchedPlace;
    for (final p in _geminiTrendingPlaces) {
      if (p.name.toLowerCase().trim() == lowerName) {
        matchedPlace = p;
        break;
      }
    }

    final hasImage = matchedPlace != null && matchedPlace.photoUrls.isNotEmpty;
    final imageUrl = hasImage ? matchedPlace.photoUrls.first : null;
    final resolvedUrl = imageUrl != null && imageUrl.startsWith('/')
        ? '${ApiConstants.baseUrl}$imageUrl'
        : imageUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Hero Image / Gradient Block
                Stack(
                  children: [
                    Container(
                      height: 180,
                      width: double.infinity,
                      child: resolvedUrl != null && resolvedUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: resolvedUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.actionTeal,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  Container(color: AppColors.surfaceVariant),
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF007A7C),
                                    Color(0xFF121212),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Opacity(
                                  opacity: 0.15,
                                  child: Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Drag indicator
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    // Close button
                    Positioned(
                      top: 15,
                      right: 15,
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        radius: 18,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black87,
                            size: 18,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
                // Details area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color:
                                    (exp.type == 'event'
                                            ? AppColors.actionTeal
                                            : AppColors.ratingGold)
                                        .withOpacity(0.15),
                                border: Border.all(
                                  color:
                                      (exp.type == 'event'
                                              ? AppColors.actionTeal
                                              : AppColors.ratingGold)
                                          .withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                exp.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: exp.type == 'event'
                                      ? AppColors.actionTeal
                                      : AppColors.ratingGold,
                                ),
                              ),
                            ),
                            if (exp.confidence.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: AppColors.actionTeal.withOpacity(0.15),
                                  border: Border.all(
                                    color: AppColors.actionTeal.withOpacity(
                                      0.3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Match Score: ${exp.confidence}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.actionTeal,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          exp.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        if (matchedPlace != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.ratingGold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${matchedPlace.rating}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Metadata Grid
                        _buildDetailMetadataRow(
                          Icons.calendar_today_rounded,
                          'When',
                          exp.when,
                        ),
                        _buildDetailMetadataRow(
                          Icons.location_on_rounded,
                          'Distance',
                          exp.distance.isNotEmpty ? exp.distance : 'Nearby',
                        ),
                        if (exp.travelTime.isNotEmpty)
                          _buildDetailMetadataRow(
                            Icons.directions_run_rounded,
                            'Travel Time',
                            exp.travelTime,
                          ),
                        _buildDetailMetadataRow(
                          Icons.attach_money_rounded,
                          'Cost',
                          exp.cost.isNotEmpty ? exp.cost : 'N/A',
                        ),
                        if (exp.bestFor.isNotEmpty)
                          _buildDetailMetadataRow(
                            Icons.people_rounded,
                            'Best For',
                            exp.bestFor,
                          ),

                        const SizedBox(height: 20),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 16),

                        // Why you'll love it
                        Text(
                          exp.type == 'event'
                              ? "Why You'll Love It"
                              : "Why Locals Love It",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          exp.why,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.black87.withOpacity(0.8),
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Locate on Map Action Button
                        _buildLocateOnMapButton(exp, matchedPlace),
                        const SizedBox(height: 40),
                      ],
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

  Widget _buildDetailMetadataRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.actionTeal),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocateOnMapButton(
    AiExperience exp,
    AttractionEntity? matchedPlace,
  ) {
    bool locating = false;
    return StatefulBuilder(
      builder: (context, setSheetState) {
        return ElevatedButton.icon(
          onPressed: locating
              ? null
              : () async {
                  if (matchedPlace != null) {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SmartTourismMapPage(
                          initialLat: matchedPlace.latitude,
                          initialLng: matchedPlace.longitude,
                          destinationName: matchedPlace.name,
                        ),
                      ),
                    );
                  } else {
                    setSheetState(() => locating = true);
                    try {
                      final results = await GooglePlacesService.searchPlaces(
                        query: exp.name,
                        latitude: _userLatitude ?? 6.9271,
                        longitude: _userLongitude ?? 79.8612,
                      );
                      if (!mounted) return;
                      Navigator.pop(context);
                      if (results.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SmartTourismMapPage(
                              initialLat: results.first.latitude,
                              initialLng: results.first.longitude,
                              destinationName: results.first.name,
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SmartTourismMapPage(
                              initialLat: _userLatitude ?? 6.9271,
                              initialLng: _userLongitude ?? 79.8612,
                              destinationName: exp.name,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Locating experience error: $e');
                      if (!mounted) return;
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SmartTourismMapPage(
                            initialLat: _userLatitude ?? 6.9271,
                            initialLng: _userLongitude ?? 79.8612,
                            destinationName: exp.name,
                          ),
                        ),
                      );
                    }
                  }
                },
          icon: locating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.map_rounded),
          label: Text(locating ? 'Searching Map...' : 'Locate on Map'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.actionTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAiReportCard() {
    return GestureDetector(
      onTap: _showAiReportBottomSheet,
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F1E36), // Deep premium dark blue
              Color(0xFF050B14),
            ],
          ),
          border: Border.all(
            color: AppColors.actionTeal.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.actionTeal.withOpacity(0.15),
              blurRadius: 15,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Decorative light glow
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.actionTeal.withOpacity(0.15),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.actionTeal.withOpacity(0.15),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🤖', style: TextStyle(fontSize: 24)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.actionTeal.withOpacity(0.2),
                          ),
                          child: const Text(
                            'NEXAROUND AI',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.actionTeal,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      "AI Experience Report",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "See why leaving home today is worth it.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.2,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.actionTeal,
                      ),
                      child: const Center(
                        child: Text(
                          'Read Report →',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
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
    );
  }

  void _showAiReportBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  // Handle/drag indicator
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          const Text(
                            'NexAround AI Discovery',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.black87),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Markdown body
                  Expanded(
                    child: Markdown(
                      data: _geminiTrendingMarkdown ?? '',
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: Colors.black87.withOpacity(0.85),
                          fontSize: 14,
                          height: 1.4,
                        ),
                        h1: const TextStyle(
                          color: Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.5,
                        ),
                        h2: const TextStyle(
                          color: AppColors.actionTeal,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.5,
                        ),
                        h3: const TextStyle(
                          color: AppColors.ratingGold,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                        listBullet: const TextStyle(
                          color: AppColors.actionTeal,
                          fontSize: 14,
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppColors.border,
                              width: 1.0,
                            ),
                          ),
                        ),
                        blockSpacing: 16.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerTrendingCards() {
    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Skeleton Carousel
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: Colors.grey[200]!,
                highlightColor: Colors.white,
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
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Premium Glassmorphism Overlay
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Container(
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ),
            ),
          ),
          
          // The beautiful message badge
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Container(
              width: 280,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white, width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: const Color(0xFFE91E63).withOpacity(0.08),
                    blurRadius: 40,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE91E63)), // Pink theme for Curated
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Discovering experiences for you...',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This may take a few moments',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerHiddenGemCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Skeleton Carousel
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
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
          
          // Premium Glassmorphism Overlay
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                child: Container(
                  color: Colors.white.withOpacity(0.45),
                ),
              ),
            ),
          ),
          
          // The beautiful message badge
          Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF00BFA5).withOpacity(0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00BFA5)), // Teal theme for Around You
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Discovering Locations for you...',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'This may take a few moments',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _getAccurateDistanceM(AttractionEntity place) {
    // Prefer cached route distance (actual road distance from Google Directions)
    if (_routeDistanceCache.containsKey(place.id)) {
      return _routeDistanceCache[place.id]!;
    }
    if (_userLatitude != null &&
        _userLongitude != null &&
        place.latitude != 0 &&
        place.longitude != 0) {
      return geo.Geolocator.distanceBetween(
        _userLatitude!,
        _userLongitude!,
        place.latitude,
        place.longitude,
      );
    }
    return place.distanceM?.toDouble() ?? 0.0;
  }

  String _getAccurateDistanceString(
    AttractionEntity place, [
    AiExperience? matchedExp,
  ]) {
    if (matchedExp != null &&
        (place.distanceM == null || place.distanceM == 0) &&
        place.latitude == 0) {
      return matchedExp.distance.isNotEmpty ? matchedExp.distance : 'Nearby';
    }
    final distM = _getAccurateDistanceM(place);
    final isRouteDistance = _routeDistanceCache.containsKey(place.id);
    final distKm = (distM / 1000).toStringAsFixed(1);
    return isRouteDistance ? '$distKm km' : '~$distKm km';
  }

  /// Batch-fetch actual road distances for a list of places using Google Directions API.
  Future<void> _batchFetchRouteDistances(List<AttractionEntity> places) async {
    return; // OPTIMIZATION: Disable background Directions API calls to save Maps API billing.
    if (_userLatitude == null || _userLongitude == null) return;
    if (_isFetchingRouteDistances) return;
    
    // Filter out places we've already fetched or are cached
    final toFetch = places.where((p) {
      if (p.latitude == 0 && p.longitude == 0) return false;
      if (_routeDistanceCache.containsKey(p.id)) return false;
      if (_routeDistanceFetchedIds.contains(p.id)) return false;
      return true;
    }).toList();
    
    if (toFetch.isEmpty) return;
    
    _isFetchingRouteDistances = true;
    final Map<String, double> newDistances = {};
    
    for (final place in toFetch) {
      _routeDistanceFetchedIds.add(place.id);
      try {
        final result = await GooglePlacesService.getDirections(
          originLat: _userLatitude!,
          originLng: _userLongitude!,
          destLat: place.latitude,
          destLng: place.longitude,
          profile: 'driving',
        );
        if (result != null) {
          final distM = result['distance_meters'] as double? ?? 0.0;
          if (distM > 0) {
            newDistances[place.id] = distM;
          }
        }
      } catch (e) {
        debugPrint('Route distance fetch failed for ${place.name}: $e');
      }
    }
    
    _isFetchingRouteDistances = false;
    
    // Single batched setState for all fetched distances
    if (newDistances.isNotEmpty && mounted) {
      setState(() {
        _routeDistanceCache.addAll(newDistances);
      });
    }
  }

  Widget _buildPlaceCard(AttractionEntity place, int index) {
    final lowerName = place.name.toLowerCase().trim();
    AiExperience? matchedExp;
    for (final exp in _aiExperiences) {
      if (exp.name.toLowerCase().trim() == lowerName) {
        matchedExp = exp;
        break;
      }
    }
    final isEvent = matchedExp != null
        ? matchedExp.type == 'event'
        : (_getEventForPlace(place) != null);
    final isGem = matchedExp != null ? matchedExp.type == 'gem' : false;

    return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttractionDetailPage(
                  id: place.id,
                  name: place.name,
                  category: place.categoryName ?? (isEvent ? 'Event' : 'Gem'),
                  rating: place.rating,
                  distance: _getAccurateDistanceString(place, matchedExp),
                  emoji: isEvent ? '📅' : '✨',
                  imageUrl: place.photoUrls.isNotEmpty
                      ? place.photoUrls.first
                      : null,
                  latitude: place.latitude,
                  longitude: place.longitude,
                  reviewCount: place.reviewCount,
                  aiWhy: matchedExp?.why,
                  aiWhen: matchedExp?.when,
                  aiCost: matchedExp?.cost,
                  aiBestFor: matchedExp?.bestFor,
                  aiConfidence: matchedExp?.confidence,
                ),
              ),
            );
          },
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
                  Positioned.fill(
                    child: (() {
                      final hasImage = place.photoUrls.isNotEmpty;
                      final imageUrl = hasImage ? place.photoUrls.first : null;
                      final resolvedUrl =
                          imageUrl != null && imageUrl.startsWith('/')
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
                                _getCategoryIcon(
                                  place.categoryName ?? 'Attraction',
                                  place.name,
                                ),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white24,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  buildFallbackBackground(),
                            )
                          : buildFallbackBackground();
                    })(),
                  ),
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
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('📍', style: TextStyle(fontSize: 28)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: isEvent
                                    ? AppColors.actionTeal.withOpacity(0.85)
                                    : isGem
                                    ? AppColors.ratingGold.withOpacity(0.85)
                                    : Colors.white.withOpacity(0.2),
                              ),
                              child: Text(
                                isEvent
                                    ? 'EVENT'
                                    : isGem
                                    ? 'GEM'
                                    : (place.categoryName ?? 'LANDMARK')
                                          .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (matchedExp != null &&
                                matchedExp.confidence.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white.withOpacity(0.25),
                                ),
                                child: Text(
                                  (() {
                                    final cleanConf = matchedExp!.confidence
                                        .replaceAll('/100', '')
                                        .replaceAll('%', '')
                                        .trim();
                                    if (int.tryParse(cleanConf) != null) {
                                      return '$cleanConf%';
                                    }
                                    return matchedExp!.confidence;
                                  })(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Spacer(),
                        (() {
                          final eventInfo = _getEventOrTrendingInfo(place);
                          final displayTitle = matchedExp != null
                              ? matchedExp.when
                              : eventInfo.title;
                          final isEventCard = matchedExp != null
                              ? matchedExp.type == 'event'
                              : (_getEventForPlace(place) != null);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isEventCard
                                  ? Colors.red.withOpacity(0.4)
                                  : AppColors.brandGreen.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isEventCard
                                    ? Colors.red.withOpacity(0.6)
                                    : AppColors.brandGreen.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isEventCard
                                      ? Icons.calendar_today_rounded
                                      : Icons.auto_awesome_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
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
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.ratingGold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${place.rating}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.location_on_rounded,
                              size: 12,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                _getAccurateDistanceString(place, matchedExp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
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
        )
        .animate()
        .fade(delay: Duration(milliseconds: 100 * index))
        .slideX(begin: 0.1, end: 0);
  }

  void _showAiPlaceDetailsBottomSheet(
    AttractionEntity place,
    Map<String, String> aiDetails,
  ) {
    final distText = _getAccurateDistanceString(place);
    final hasImage = place.photoUrls.isNotEmpty;
    final imageUrl = hasImage ? place.photoUrls.first : null;
    final resolvedUrl = imageUrl != null && imageUrl.startsWith('/')
        ? '${ApiConstants.baseUrl}$imageUrl'
        : imageUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1018), // Dark theme matching app
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Hero Image / Gradient Block
                Stack(
                  children: [
                    Container(
                      height: 180,
                      width: double.infinity,
                      child: resolvedUrl != null && resolvedUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: resolvedUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white24,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  Container(color: AppColors.surfaceVariant),
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0F1E36),
                                    Color(0xFF050B14),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Opacity(
                                  opacity: 0.15,
                                  child: Icon(
                                    _getCategoryIcon(
                                      place.categoryName ?? 'Attraction',
                                      place.name,
                                    ),
                                    size: 80,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              const Color(0xFF0A1018),
                              const Color(0xFF0A1018).withOpacity(0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Drag indicator
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    // Close button
                    Positioned(
                      top: 15,
                      right: 15,
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withOpacity(0.4),
                        radius: 18,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
                // Details area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ListView(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: AppColors.actionTeal.withOpacity(0.15),
                                border: Border.all(
                                  color: AppColors.actionTeal.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                place.categoryName?.toUpperCase() ??
                                    'ATTRACTION',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.actionTeal,
                                ),
                              ),
                            ),
                            if (aiDetails['confidence'] != null) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: AppColors.ratingGold.withOpacity(0.15),
                                  border: Border.all(
                                    color: AppColors.ratingGold.withOpacity(
                                      0.3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Confidence: ${aiDetails['confidence']}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ratingGold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          place.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: AppColors.ratingGold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${place.rating}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'WHY YOU\'LL LOVE IT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.actionTeal,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          aiDetails['why'] ??
                              'A highly rated local recommendation.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 12),
                        // Grid of key info
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (aiDetails['when'] != null)
                              Expanded(
                                child: _buildInfoGridCell(
                                  'When',
                                  aiDetails['when']!,
                                  Icons.access_time_filled_rounded,
                                ),
                              ),
                            if (aiDetails['cost'] != null)
                              Expanded(
                                child: _buildInfoGridCell(
                                  'Cost',
                                  aiDetails['cost']!,
                                  Icons.attach_money_rounded,
                                ),
                              ),
                            if (aiDetails['bestFor'] != null)
                              Expanded(
                                child: _buildInfoGridCell(
                                  'Best For',
                                  aiDetails['bestFor']!,
                                  Icons.people_alt_rounded,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        // Navigate / Details Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttractionDetailPage(
                                    id: place.id,
                                    name: place.name,
                                    category:
                                        place.categoryName ?? 'Attraction',
                                    rating: place.rating,
                                    distance: distText,
                                    emoji: '📍',
                                    imageUrl: place.photoUrls.isNotEmpty
                                        ? place.photoUrls.first
                                        : null,
                                    latitude: place.latitude,
                                    longitude: place.longitude,
                                    reviewCount: place.reviewCount,
                                    aiWhy: aiDetails['why'],
                                    aiWhen: aiDetails['when'],
                                    aiCost: aiDetails['cost'],
                                    aiBestFor: aiDetails['bestFor'],
                                    aiConfidence: aiDetails['confidence'],
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.explore, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Explore details & Navigation',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
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

  Widget _buildInfoGridCell(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.actionTeal),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _getCategoryImagePath(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('nature')) return 'assets/images/cat_nature.png';
    if (cat.contains('hotel') || cat.contains('stay'))
      return 'assets/images/cat_hotels.png';
    if (cat.contains('shop')) return 'assets/images/cat_shopping.png';
    if (cat.contains('food')) return 'assets/images/cat_food.png';
    if (cat.contains('medical') || cat.contains('hospital'))
      return 'assets/images/cat_medical.png';
    if (cat.contains('poi') ||
        cat.contains('historic') ||
        cat.contains('history') ||
        cat.contains('museum') ||
        cat.contains('attraction'))
      return 'assets/images/cat_historical.png';
    return 'assets/images/cat_nature.png'; // default
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
      case 'Food & Drink':
        return Colors.orange.withOpacity(0.15);
      case 'POI':
      case 'Attractions':
      case 'Nature':
        return Colors.teal.withOpacity(0.15);
      case 'Shopping':
        return Colors.blue.withOpacity(0.15);
      case 'Medical':
      case 'Hospital':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.white.withOpacity(0.10);
    }
  }

  Color _getCategoryBorderColor(String category) {
    switch (category) {
      case 'Food':
      case 'Food & Drink':
        return Colors.orange.withOpacity(0.40);
      case 'POI':
      case 'Attractions':
      case 'Nature':
        return Colors.teal.withOpacity(0.40);
      case 'Shopping':
        return Colors.blue.withOpacity(0.40);
      case 'Medical':
      case 'Hospital':
        return Colors.red.withOpacity(0.40);
      default:
        return Colors.white.withOpacity(0.25);
    }
  }

  String _getDirectionString(
    double? userLat,
    double? userLng,
    double placeLat,
    double placeLng,
  ) {
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

  Widget _buildCategoryCard(
    String categoryName,
    List<AttractionEntity> places,
    int index,
    MapStatus status,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Frosted Glass Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(
                  0.25,
                ), // Dark frosted glass style
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _getCategoryBorderColor(categoryName),
                  width: 1.0,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withOpacity(0.35), // darker frosted look
                    _getCategoryColor(categoryName),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),
          // 2. 3D Pop-out Category Icon (rendered behind text, but on top of card background)
          Positioned(
            top: -42,
            right: -16,
            child: Image.asset(
              _getCategoryImagePath(categoryName),
              width: 125,
              height: 125,
              fit: BoxFit.contain,
            ),
          ),
          // 3. Card Content (defines size of the stack)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category Header Badge & Distance meter row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
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
                    Padding(
                      padding: const EdgeInsets.only(
                        right: 90,
                      ), // Shift left to clear the larger top-right 3D icon
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getCategoryBorderColor(
                            categoryName,
                          ).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getCategoryBorderColor(
                              categoryName,
                            ).withOpacity(0.35),
                            width: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.radar_rounded,
                              size: 11,
                              color: _getCategoryBorderColor(
                                categoryName,
                              ).withOpacity(0.95),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              categoryName == 'Attractions' ||
                                      categoryName == 'Medical'
                                  ? '0-50 km'
                                  : '0-15 km',
                              style: TextStyle(
                                color: _getCategoryBorderColor(
                                  categoryName,
                                ).withOpacity(0.95),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Places horizontal carousel!
                places.isEmpty
                    ? (status == MapStatus.loading
                        ? SizedBox(
                            height: 200,
                            child: Shimmer.fromColors(
                              baseColor: Colors.white.withOpacity(0.06),
                              highlightColor: Colors.white.withOpacity(0.18),
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: 3,
                                itemBuilder: (context, idx) {
                                  return Container(
                                    width: 170,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  );
                                },
                              ),
                            ),
                          )
                        : () {
                            final String err = categoryName == 'Attractions'
                                ? GooglePlacesService.lastAttractionsError
                                : (categoryName == 'Medical'
                                    ? GooglePlacesService.lastMedicalError
                                    : '');
                            return SizedBox(
                              height: 200,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        categoryName == 'Medical'
                                            ? Icons.local_hospital_outlined
                                            : Icons.map_outlined,
                                        color: Colors.white.withOpacity(0.35),
                                        size: 36,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        err.isNotEmpty
                                            ? err
                                            : 'No $categoryName found within 50 km.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.55),
                                          fontSize: 12.5,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }())
                    : SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: () {
                            final Set<String> seenIds = {};
                            final List<AttractionEntity> uniquePlaces = [];
                            for (final p in places) {
                              if (!seenIds.contains(p.id)) {
                                seenIds.add(p.id);
                                uniquePlaces.add(p);
                              }
                            }
                            return uniquePlaces.take(15).length;
                          }(),
                          itemBuilder: (context, idx) {
                            final Set<String> seenIds = {};
                            final List<AttractionEntity> uniquePlaces = [];
                            for (final p in places) {
                              if (!seenIds.contains(p.id)) {
                                seenIds.add(p.id);
                                uniquePlaces.add(p);
                              }
                            }
                            final finalPlaces = uniquePlaces.take(15).toList();
                            final place = finalPlaces[idx];
                            return _buildCategoryPlaceCard(place, categoryName);
                          },
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHiddenGemCards(List<AttractionEntity> attractions, MapStatus status) {
    if (attractions.isEmpty) return const SizedBox.shrink();

    final Map<String, List<AttractionEntity>> grouped = {
      'Food & Drink': [],
      'POI': [],
      'Shopping': [],
      'Medical': [],
    };

    int compareDistanceAndRating(AttractionEntity a, AttractionEntity b) {
      final distA = _getAccurateDistanceM(a);
      final distB = _getAccurateDistanceM(b);
      if ((distA - distB).abs() < 100) {
        final rateA = a.rating ?? 0.0;
        final rateB = b.rating ?? 0.0;
        return rateB.compareTo(rateA);
      }
      return distA.compareTo(distB);
    }

    for (final place in attractions) {
      final distM = _getAccurateDistanceM(place);
      final distKm = distM / 1000.0;

      final catName = (place.categoryName ?? '').toLowerCase();
      final name = place.name.toLowerCase();
      final tags = place.tags.map((t) => t.toString().toLowerCase()).toList();

      bool matchesFood = false;
      bool matchesPOI = false;
      bool matchesShopping = false;
      bool matchesMedical = false;

      // 1. Food & Drink matching logic
      if (catName.contains('food') || catName.contains('restaurant') || catName.contains('cafe') || 
          catName.contains('dining') || catName.contains('meal') || name.contains('restaurant') || name.contains('cafe')) {
        matchesFood = true;
      }

      // 2. POI matching logic (Attractions + Nature combined)
      if (catName.contains('poi') || catName.contains('attraction') || catName.contains('museum') || catName.contains('park') || 
          catName.contains('experience') || catName.contains('landmark') || catName.contains('culture') ||
          catName.contains('temple') || catName.contains('art') || catName.contains('zoo') ||
          catName.contains('nature') || catName.contains('beach') || catName.contains('garden') ||
          catName.contains('lake') || catName.contains('river') || catName.contains('waterfall') || catName.contains('forest') ||
          name.contains('temple') || name.contains('park') || name.contains('museum') || name.contains('beach') ||
          name.contains('lake') || name.contains('waterfall') || name.contains('garden') || name.contains('forest') ||
          tags.contains('park') || tags.contains('beach') || tags.contains('natural_feature') ||
          tags.contains('national_park') || tags.contains('hiking_area') || tags.contains('nature_reserve') ||
          tags.contains('botanical_garden') || tags.contains('tourist_attraction') || tags.contains('historical_landmark')) {
        matchesPOI = true;
      }

      // Exclusion checks for POI category to filter out play schools, surgeries, salons, etc.
      if (matchesPOI) {
        final attractionExclusions = [
          'school', 'university', 'college', 'academy', 'preschool', 'kindergarten',
          'surgery', 'clinic', 'medical', 'dental', 'doctor', 'dentist', 'hospital',
          'spa', 'salon', 'wellness', 'massage', 'beauty', 'hair', 'nail',
          'bank', 'atm', 'store', 'shop', 'office', 'pharmacy', 'supermarket',
          'grocery', 'gas station'
        ];
        final attractionExcludeTags = [
          'spa', 'beauty_salon', 'hair_care', 'doctor', 'dentist', 'hospital', 
          'medical_clinic', 'pharmacy', 'school', 'university', 'bank', 'atm', 
          'gas_station', 'store', 'shopping_mall'
        ];
        if (attractionExclusions.any((kw) => name.contains(kw)) ||
            tags.any((t) => attractionExcludeTags.contains(t))) {
          matchesPOI = false;
        }
      }

      // 3. Shopping matching logic
      if (catName.contains('shop') || catName.contains('mall') || catName.contains('market') || 
          catName.contains('store') || catName.contains('fashion')) {
        matchesShopping = true;
      }

      // Exclusion checks for Shopping category
      if (matchesShopping) {
        final shoppingExclusions = [
          'school', 'university', 'college', 'academy', 'preschool', 'kindergarten',
          'surgery', 'clinic', 'medical', 'hospital', 'doctor', 'dentist'
        ];
        final shoppingExcludeTags = [
          'school', 'university', 'hospital', 'doctor', 'dentist'
        ];
        if (shoppingExclusions.any((kw) => name.contains(kw)) ||
            tags.any((t) => shoppingExcludeTags.contains(t))) {
          matchesShopping = false;
        }
      }

      // 4. Medical matching logic (Medical + Hospital combined)
      final bool hasMedicalSignal =
          catName == 'medical' ||
          catName == 'hospital' ||
          name.contains('medical') ||
          name.contains('hospital') ||
          name.contains('clinic') ||
          name.contains('pharmacy') ||
          name.contains('dispensary') ||
          name.contains('health centre') ||
          name.contains('health center') ||
          tags.contains('hospital') ||
          tags.contains('multi_speciality_hospital') ||
          tags.contains('pharmacy') ||
          tags.contains('doctor') ||
          tags.contains('dentist') ||
          tags.contains('physiotherapist') ||
          tags.contains('veterinary_care') ||
          tags.contains('health') ||
          tags.contains('medical_center') ||
          (catName.contains('medical') || catName.contains('clinic') ||
           catName.contains('pharmacy') || catName.contains('doctor'));

      if (hasMedicalSignal) {
        const nonMedicalTags = [
          'school', 'university', 'secondary_school', 'primary_school',
          'bank', 'finance', 'accounting', 'atm',
          'food', 'restaurant', 'bakery', 'cafe', 'bar',
          'store', 'shopping_mall', 'grocery_or_supermarket',
          'lodging', 'real_estate_agency',
          'transit_station', 'bus_station', 'train_station',
        ];
        final bool isNonMedical = tags.any((t) => nonMedicalTags.contains(t));
        if (!isNonMedical) {
          matchesMedical = true;
        }
      }

      double filterDistKm = distKm;
      if (_userLatitude != null && _userLongitude != null && place.latitude != 0 && place.longitude != 0) {
        filterDistKm = geo.Geolocator.distanceBetween(
          _userLatitude!, _userLongitude!, place.latitude, place.longitude
        ) / 1000.0;
      }

      if (matchesFood && filterDistKm <= 5.0) {
        if (!grouped['Food & Drink']!.any((x) => x.id == place.id)) {
          grouped['Food & Drink']!.add(place);
        }
      }
      if (matchesPOI && filterDistKm <= 50.0) {
        if (!grouped['POI']!.any((x) => x.id == place.id)) {
          grouped['POI']!.add(place);
        }
      }
      if (matchesShopping && filterDistKm <= 15.0) {
        if (!grouped['Shopping']!.any((x) => x.id == place.id)) {
          grouped['Shopping']!.add(place);
        }
      }
      if (matchesMedical && filterDistKm <= 50.0) {
        if (!grouped['Medical']!.any((x) => x.id == place.id)) {
          grouped['Medical']!.add(place);
        }
      }
    }

    List<AttractionEntity> selectBalancedPlaces({
      required List<AttractionEntity> allPlaces,
      required double r1,
      required double r2,
      required double r3,
      required String category,
    }) {
      // 1. Filter places to only show rating >= 4.0 stars (client request)
      List<AttractionEntity> filteredPlaces = allPlaces.where((p) => (p.rating ?? 0.0) >= 4.0).toList();
      // Fallback if empty to avoid completely blank panels
      if (filteredPlaces.isEmpty) {
        filteredPlaces = allPlaces;
      }

      bool isMall(AttractionEntity p) {
        final lowerName = p.name.toLowerCase();
        final lowerTags = p.tags.map((t) => t.toString().toLowerCase()).toList();
        return lowerName.contains('mall') || lowerTags.contains('shopping_mall');
      }

      filteredPlaces.sort((a, b) {
        if (category == 'Shopping') {
          final aMall = isMall(a);
          final bMall = isMall(b);
          if (aMall && !bMall) return -1;
          if (!aMall && bMall) return 1;
        }
        return compareDistanceAndRating(a, b);
      });

      final List<AttractionEntity> nearList = [];
      final List<AttractionEntity> midList = [];
      final List<AttractionEntity> farList = [];

      for (final p in filteredPlaces) {
        final distKm = _getAccurateDistanceM(p) / 1000.0;
        if (distKm < r1) {
          nearList.add(p);
        } else if (distKm < r2) {
          midList.add(p);
        } else if (distKm <= r3) {
          farList.add(p);
        }
      }

      int nearTaken = nearList.length < 5 ? nearList.length : 5;
      int midTaken = midList.length < 5 ? midList.length : 5;
      int farTaken = farList.length < 5 ? farList.length : 5;

      int totalTaken = nearTaken + midTaken + farTaken;
      int remainingSlots = 15 - totalTaken;

      if (remainingSlots > 0) {
        final extraNear = nearList.length - nearTaken;
        if (extraNear > 0) {
          final toTake = extraNear < remainingSlots ? extraNear : remainingSlots;
          nearTaken += toTake;
          remainingSlots -= toTake;
        }
      }

      if (remainingSlots > 0) {
        final extraMid = midList.length - midTaken;
        if (extraMid > 0) {
          final toTake = extraMid < remainingSlots ? extraMid : remainingSlots;
          midTaken += toTake;
          remainingSlots -= toTake;
        }
      }

      if (remainingSlots > 0) {
        final extraFar = farList.length - farTaken;
        if (extraFar > 0) {
          final toTake = extraFar < remainingSlots ? extraFar : remainingSlots;
          farTaken += toTake;
          remainingSlots -= toTake;
        }
      }

      final List<AttractionEntity> selected = [];
      selected.addAll(nearList.take(nearTaken));
      selected.addAll(midList.take(midTaken));
      selected.addAll(farList.take(farTaken));

      selected.sort((a, b) {
        if (category == 'Shopping') {
          final aMall = isMall(a);
          final bMall = isMall(b);
          if (aMall && !bMall) return -1;
          if (!aMall && bMall) return 1;
        }
        return compareDistanceAndRating(a, b);
      });
      return selected;
    }

    for (final cat in grouped.keys) {
      double r1 = 2.0;
      double r2 = 10.0;
      double r3 = 50.0;

      if (cat == 'Food & Drink') {
        r1 = 1.0;
        r2 = 3.0;
        r3 = 5.0;
      } else if (cat == 'Shopping') {
        r1 = 1.0;
        r2 = 5.0;
        r3 = 15.0;
      } else if (cat == 'POI' || cat == 'Medical') {
        r1 = 2.0;
        r2 = 10.0;
        r3 = 50.0;
      }

      grouped[cat] = selectBalancedPlaces(
        allPlaces: grouped[cat] ?? [],
        r1: r1,
        r2: r2,
        r3: r3,
        category: cat,
      );
    }

    final allGroupedPlaces = grouped.values.expand((x) => x).toList();
    if (allGroupedPlaces.isNotEmpty && !_isFetchingRouteDistances) {
      // Schedule after build to avoid triggering rebuilds during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _batchFetchRouteDistances(allGroupedPlaces);
      });
    }

    final maxItems = grouped.values.map((l) => l.length).fold(0, (max, v) => v > max ? v : max);
    final double listHeight = (112.0 + (maxItems * 44.0)).clamp(240.0, 780.0);

    return SizedBox(
      height: listHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        children: [
          _buildCategoryPanel('Food & Drink', grouped['Food & Drink']!, status),
          const SizedBox(width: 16),
          _buildCategoryPanel('POI', grouped['POI']!, status),
          const SizedBox(width: 16),
          _buildCategoryPanel('Shopping', grouped['Shopping']!, status),
          const SizedBox(width: 16),
          _buildCategoryPanel('Medical', grouped['Medical']!, status),
        ],
      ),
    );
  }

  Widget _buildCategoryPanel(String categoryName, List<AttractionEntity> places, MapStatus status) {
    Color themeColor;
    Color lightTint;
    switch (categoryName) {
      case 'Food & Drink':
        themeColor = Colors.orange;
        lightTint = const Color(0xFFFFF3E0);
        break;
      case 'POI':
      case 'Attractions':
      case 'Nature':
        themeColor = Colors.teal;
        lightTint = const Color(0xFFE0F2F1);
        break;
      case 'Shopping':
        themeColor = Colors.blue;
        lightTint = const Color(0xFFE3F2FD);
        break;
      case 'Medical':
      case 'Hospital':
        themeColor = const Color(0xFFE53935);
        lightTint = const Color(0xFFFFEBEE);
        break;
      default:
        themeColor = Colors.grey;
        lightTint = const Color(0xFFF5F5F5);
    }

    if (status == MapStatus.loading) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.92),
                Colors.white.withOpacity(0.70),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: themeColor.withOpacity(0.24),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: CircularProgressIndicator(color: themeColor)),
          ),
      );
    }
    
    if (places.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.92),
                Colors.white.withOpacity(0.70),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: themeColor.withOpacity(0.24),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'No $categoryName nearby',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    final String maxRange;
    if (categoryName == 'Attractions' || categoryName == 'Hospital') {
      maxRange = '0-50 kms';
    } else if (categoryName == 'Food' || categoryName == 'Food & Drink') {
      maxRange = '0-5 kms';
    } else {
      maxRange = '0-15 kms';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: themeColor.withOpacity(0.24),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lightTint.withOpacity(0.92),
              Colors.white.withOpacity(0.80),
            ],
          ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -14,
                right: -6,
                child: Opacity(
                  opacity: 0.85,
                  child: Image.asset(
                    _getCategoryImagePath(categoryName),
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: themeColor.withOpacity(0.20), width: 0.8),
                            ),
                            child: Text(
                              categoryName,
                              style: TextStyle(color: themeColor, fontSize: 16, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: themeColor.withOpacity(0.35),
                                  width: 1.2,
                                ),
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: themeColor.withOpacity(0.60),
                                  width: 1.0,
                                ),
                              ),
                            ),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: themeColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Text(
                          maxRange,
                          style: TextStyle(color: themeColor.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: places.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final place = places[index];
                          final distKm = _getAccurateDistanceM(place) / 1000.0;
                          final distStr = distKm < 1.0 ? '${(distKm * 1000).toInt()}m' : '${distKm.toStringAsFixed(1)}km';
                          final direction = _getDirectionString(_userLatitude, _userLongitude, place.latitude ?? 0.0, place.longitude ?? 0.0);
                          final ratingVal = place.rating;

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: themeColor.withOpacity(0.18),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AttractionDetailPage(
                                        id: place.id,
                                        name: place.name,
                                        category: place.categoryName ?? 'Gem',
                                        rating: place.rating,
                                        distance: distStr,
                                        emoji: '📍',
                                        imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
                                        latitude: place.latitude,
                                        longitude: place.longitude,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          place.name,
                                          style: const TextStyle(
                                            color: Color(0xFF1E293B),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (ratingVal != null && ratingVal > 0) ...[
                                        Icon(
                                          Icons.star_rounded,
                                          size: 13,
                                          color: AppColors.warning,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          ratingVal.toStringAsFixed(1),
                                          style: const TextStyle(
                                            color: Color(0xFF334155),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          '•',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        distStr,
                                        style: TextStyle(
                                          color: themeColor.withOpacity(0.9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: themeColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: themeColor.withOpacity(0.20),
                                            width: 0.7,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              direction,
                                              style: TextStyle(
                                                color: themeColor,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 11,
                                              color: themeColor,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildClusterSuggestion(List<AttractionEntity> attractions) {
    // Commented out by client request (will restore in the future)
    return const SizedBox.shrink();
    if (attractions.isEmpty) return const SizedBox.shrink();

    // Deduplicate attractions to make sure no two stops on the walk route are the same
    final List<AttractionEntity> uniqueAttractions = [];
    final Set<String> seenNames = {};
    final Set<String> seenIds = {};
    for (final p in attractions) {
      final normName = p.name.trim().toLowerCase();
      if (!seenNames.contains(normName) && !seenIds.contains(p.id)) {
        seenNames.add(normName);
        seenIds.add(p.id);
        uniqueAttractions.add(p);
      }
    }

    if (uniqueAttractions.isEmpty) return const SizedBox.shrink();

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
                child: const Icon(
                  Icons.route_rounded,
                  color: Colors.white,
                  size: 18,
                ),
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
          ...uniqueAttractions.take(5).toList().asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final totalStops = min(uniqueAttractions.length, 5);

            final dist = p.distanceM;
            final distLabel = dist == null
                ? '—'
                : (dist < 1000
                      ? '${dist.toInt()} m'
                      : '${(dist / 1000).toStringAsFixed(1)} km');
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
                border: Border.all(
                  color: AppColors.brandGreen.withOpacity(0.35),
                ),
              ),
              child: TextButton(
                onPressed: () => launchMiniTour(
                  context,
                  lat: _userLatitude,
                  lng: _userLongitude,
                  areaName: _currentLocationName,
                  preFetchedPlaces: uniqueAttractions,
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
    );
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
            child: Text(
              num,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          info,
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
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
      child:
          GlassCard(
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
                          child: Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
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
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showProximityAlert = false),
                          child: Icon(
                            Icons.close_rounded,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
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
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AttractionDetailPage(
                                    id: place.id,
                                    name: place.name,
                                    category:
                                        place.categoryName ?? 'Attraction',
                                    rating: place.rating,
                                    distance: _getAccurateDistanceString(place),
                                    emoji: '📍',
                                    imageUrl: place.photoUrls.isNotEmpty
                                        ? place.photoUrls.first
                                        : null,
                                    latitude: place.latitude,
                                    longitude: place.longitude,
                                    reviewCount: place.reviewCount,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'View Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.secondary.withOpacity(0.4),
                              ),
                            ),
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArCameraPage(
                                    initialPlace: {
                                      'name': place.name,
                                      'category':
                                          place.categoryName ?? 'Attraction',
                                      'distance':
                                          '${(_getAccurateDistanceM(place)).toStringAsFixed(0)} m',
                                      'distanceM': _getAccurateDistanceM(place),
                                      'rating': place.rating ?? 0.0,
                                      'latitude': place.latitude,
                                      'longitude': place.longitude,
                                    },
                                  ),
                                ),
                              ),
                              child: Text(
                                'Start AR',
                                style: TextStyle(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
              .animate()
              .slideY(
                begin: 1,
                end: 0,
                duration: 500.ms,
                curve: Curves.easeOutBack,
              )
              .fade(),
    );
  }

  IconData _getCategoryIcon(String category, String name) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();

    if (cat.contains('food') ||
        cat.contains('drink') ||
        cat.contains('restaurant') ||
        cat.contains('cafe') ||
        nm.contains('cafe') ||
        nm.contains('restaurant')) {
      if (cat.contains('cafe') ||
          cat.contains('coffee') ||
          nm.contains('cafe') ||
          nm.contains('coffee')) {
        return Icons.coffee_rounded;
      }
      if (cat.contains('street') ||
          cat.contains('fast') ||
          nm.contains('burger') ||
          nm.contains('pizza')) {
        return Icons.local_pizza_rounded;
      }
      return Icons.restaurant_rounded;
    }

    if (cat.contains('shop') ||
        cat.contains('mall') ||
        cat.contains('market') ||
        cat.contains('store')) {
      if (cat.contains('clothing') ||
          cat.contains('fashion') ||
          nm.contains('fashion') ||
          nm.contains('boutique')) {
        return Icons.shopping_bag_rounded;
      }
      if (cat.contains('market') ||
          cat.contains('local') ||
          nm.contains('market') ||
          nm.contains('bazaar')) {
        return Icons.storefront_rounded;
      }
      return Icons.shopping_cart_rounded;
    }

    if (cat.contains('hotel') ||
        cat.contains('accommodation') ||
        cat.contains('stay') ||
        cat.contains('lodging')) {
      return Icons.hotel_rounded;
    }

    if (cat.contains('park') ||
        cat.contains('nature') ||
        cat.contains('garden') ||
        cat.contains('forest') ||
        cat.contains('beach')) {
      return Icons.park_rounded;
    }

    if (cat.contains('museum') ||
        cat.contains('gallery') ||
        nm.contains('museum') ||
        nm.contains('gallery')) {
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
    if (cat.contains('food') ||
        cat.contains('drink') ||
        cat.contains('restaurant') ||
        cat.contains('cafe')) {
      emoji = '🍽';
    } else if (cat.contains('shop') ||
        cat.contains('mall') ||
        cat.contains('market')) {
      emoji = '🛍';
    } else if (cat.contains('hotel') || cat.contains('accommodation')) {
      emoji = '🏨';
    } else if (cat.contains('park') ||
        cat.contains('nature') ||
        cat.contains('garden')) {
      emoji = '🌿';
    } else if (cat.contains('museum') ||
        cat.contains('heritage') ||
        cat.contains('historic')) {
      emoji = '🏛';
    } else if (cat.contains('beach') ||
        cat.contains('coast') ||
        cat.contains('sea')) {
      emoji = '🏖';
    } else if (cat.contains('temple') ||
        cat.contains('religious') ||
        cat.contains('church')) {
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

  Widget _buildCategoryPlaceCard(AttractionEntity place, String categoryName) {
    final distText = _getAccurateDistanceString(place);
    final dirText = _getDirectionString(
      _userLatitude,
      _userLongitude,
      place.latitude,
      place.longitude,
    );

    final hasImage = place.photoUrls.isNotEmpty;
    final imageUrl = hasImage ? place.photoUrls.first : null;
    final resolvedUrl = imageUrl != null && imageUrl.startsWith('/')
        ? '${ApiConstants.baseUrl}$imageUrl'
        : imageUrl;

    Widget buildFallbackBackground() {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.05),
              Colors.white.withOpacity(0.12),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Center(
          child: Opacity(
            opacity: 0.15,
            child: Icon(
              _getCategoryIcon(categoryName, place.name),
              size: 50,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttractionDetailPage(
            id: place.id,
            name: place.name,
            category: place.categoryName ?? categoryName,
            rating: place.rating,
            distance: distText,
            emoji: '📍',
            imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
            latitude: place.latitude,
            longitude: place.longitude,
            reviewCount: place.reviewCount,
          ),
        ),
      ),
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo background
              resolvedUrl != null && resolvedUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: resolvedUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.black.withOpacity(0.3),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => buildFallbackBackground(),
                    )
                  : buildFallbackBackground(),
              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.black.withOpacity(0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Text Content
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Rating
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: AppColors.ratingGold, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          '${place.rating ?? 4.0}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 4),
                    // Title
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Distance & Direction Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            distText,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (dirText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getCategoryBorderColor(categoryName).withOpacity(0.35),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _getCategoryBorderColor(categoryName).withOpacity(0.6),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              dirText,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
    final side = BorderSide(
      color: const Color(0xFF00E5FF).withOpacity(0.6),
      width: 1.5,
    );
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
        Rect.fromCenter(
          center: Offset.zero,
          width: (radius * 2 * sin(lngRad)).abs(),
          height: radius * 2,
        ),
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
    return old.rotation != rotation ||
        old.tilt != tilt ||
        old.placePoints != placePoints;
  }
}

class _SpotlightPoint3D {
  final double lat; // in radians
  final double lng; // in radians

  _SpotlightPoint3D(double latDeg, double lngDeg)
    : lat = latDeg * pi / 180,
      lng = lngDeg * pi / 180;
}

class AiExperience {
  final String name;
  final String type; // 'event' or 'gem'
  final String why;
  final String distance;
  final String travelTime;
  final String when;
  final String cost;
  final String bestFor;
  final String confidence;

  AiExperience({
    required this.name,
    required this.type,
    required this.why,
    required this.distance,
    required this.travelTime,
    required this.when,
    required this.cost,
    required this.bestFor,
    required this.confidence,
  });
}
