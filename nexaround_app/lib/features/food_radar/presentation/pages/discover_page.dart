import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/google_maps_page.dart';
import 'package:nexaround_app/core/widgets/converted_currency_text.dart';

import 'package:nexaround_app/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_state.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_event.dart';
import 'package:nexaround_app/features/budget/domain/entities/budget.dart' as budget_entity;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';

import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/core/utils/place_sections.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class DiscoverPage extends StatefulWidget {
  final int initialTab;
  final bool isActive;
  final int requestCount;
  const DiscoverPage({
    super.key,
    this.initialTab = 0,
    this.isActive = false,
    this.requestCount = 0,
  });

  /// The Discovery tabs, in order. The six place sections come first and
  /// Emergency sits apart at the end — it is the panic surface, not a category.
  static const List<String> tabs = [
    'POI',
    'Nature',
    'Food',
    'Shopping',
    'Medical',
    'Hospital',
    'Emergency',
  ];

  static final int emergencyTabIndex = tabs.indexOf('Emergency');

  /// Tab index for an Around You section name.
  ///
  /// Around You and Discovery order their categories differently, and the two
  /// used to be bridged by a nested ternary of literal indices — which silently
  /// pointed at the wrong tab the moment a category was inserted.
  static int tabIndexFor(String category) {
    switch (category) {
      case 'Food':
      case 'Food & Drink':
        return tabs.indexOf('Food');
      case 'POI':
      case 'Attractions':
      case 'Experiences':
        return tabs.indexOf('POI');
      case 'Nature':
      case 'Beach':
        return tabs.indexOf('Nature');
      case 'Shopping':
        return tabs.indexOf('Shopping');
      case 'Medical':
        return tabs.indexOf('Medical');
      case 'Hospital':
        return tabs.indexOf('Hospital');
      default:
        return 0;
    }
  }

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with SingleTickerProviderStateMixin {
  late int _selectedTab;
  late AnimationController _radarController;
  final ScrollController _tabScrollController = ScrollController();
  Position? _currentPosition;

  List<AttractionEntity> _poiList = [];
  List<AttractionEntity> _natureList = [];
  List<AttractionEntity> _foodList = [];
  List<AttractionEntity> _shoppingList = [];
  List<AttractionEntity> _medicalList = [];
  List<AttractionEntity> _hospitalList = [];

  // Emergency tab state
  List<Map<String, dynamic>> _nearbyHospitals = [];
  Map<String, dynamic>? _emergencyInfo;
  bool _isLoadingEmergency = false;

  // Selected sub-categories for filtering
  String? _selectedPoiCategory;
  String? _selectedNatureCategory;
  String? _selectedFoodCategory;
  String? _selectedShoppingCategory;
  String? _selectedMedicalCategory;
  String? _selectedHospitalCategory;

  List<String> get _tabs => DiscoverPage.tabs;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, _tabs.length - 1);
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _loadEmergencyCache();
    context.read<BudgetBloc>().add(FetchBudget());
    // IndexedStack builds every tab page up front, so this widget exists (and
    // initState runs) the moment the app opens on the Explore tab, well before
    // the user has ever looked at Discover. Firing the fetch unconditionally
    // here fired a second, redundant round of the same requests Around You
    // was already making at that exact moment. didUpdateWidget (below) already
    // fires this the instant the tab actually becomes active, so a deep link
    // straight into Discover (isActive true from the start) still fetches
    // immediately here — nothing is lost, only the duplicate is.
    if (widget.isActive) _initLocationAndFetch();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTab(_selectedTab));
  }

  @override
  void dispose() {
    _radarController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DiscoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab || widget.requestCount != oldWidget.requestCount) {
      setState(() {
        _selectedTab = widget.initialTab.clamp(0, _tabs.length - 1);
        _clearSubCategories();
      });
      _fetchForTab(_selectedTab);
      if (_tabs[_selectedTab] == 'Emergency') _fetchEmergencyData();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTab(_selectedTab));
    }
    if (widget.isActive && !oldWidget.isActive) {
      _initLocationAndFetch();
    }
  }

  /// Drop every sub-category chip. Called whenever the tab changes: a chip left
  /// selected on a tab the user has navigated away from silently filters that
  /// tab's list the next time they come back to it.
  void _clearSubCategories() {
    _selectedPoiCategory = null;
    _selectedNatureCategory = null;
    _selectedFoodCategory = null;
    _selectedShoppingCategory = null;
    _selectedMedicalCategory = null;
    _selectedHospitalCategory = null;
  }

  void _scrollToTab(int index) {
    if (_tabScrollController.hasClients) {
      final targetOffset = (index * 95.0).clamp(0.0, _tabScrollController.position.maxScrollExtent);
      _tabScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _initLocationAndFetch() async {
    try {
      Position position;
      if (CacheService.overriddenLatitude != null && CacheService.overriddenLongitude != null) {
        position = Position(
          latitude: CacheService.overriddenLatitude!,
          longitude: CacheService.overriddenLongitude!,
          timestamp: DateTime.now(),
          accuracy: 100,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      } else {
        position = await Geolocator.getCurrentPosition();
      }
      if (!mounted) return;
      setState(() => _currentPosition = position);
      _fetchForTab(_selectedTab);
      if (_tabs[_selectedTab] == 'Emergency') _fetchEmergencyData();
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _fetchForTab(int index) {
    if (_currentPosition == null && CacheService.getLastFetchLat() == null) return;

    // `_currentPosition` is already the resolved answer — the explored location
    // if the user picked one, a live fix otherwise (_initLocationAndFetch) — so
    // it has to win. `last_fetch_lat` is cache bookkeeping, "where we last
    // completed a full network fetch", and it only advances on that one path
    // (map_bloc's saveLastFetchCoords); every cache short-circuit returns before
    // it. Reading it first is what showed Colombo's places while exploring
    // Kinniya, and kept showing them: if the refetch found nothing, the
    // coordinate never advanced. It stays only as the cold-start fallback for
    // when there is no fix and no override yet.
    final lat = _currentPosition?.latitude ?? CacheService.getLastFetchLat();
    final lng = _currentPosition?.longitude ?? CacheService.getLastFetchLng();
    if (lat == null || lng == null) return;

    // Tab label to the canonical category the API expects. Emergency has no
    // entry: it runs its own hospital lookup with its own radius.
    const tabCategories = {
      'POI': 'POI',
      'Nature': 'Nature',
      'Food': 'Food & Drink',
      'Shopping': 'Shopping',
      'Medical': 'Medical',
      'Hospital': 'Hospital',
    };
    final String? category = tabCategories[_tabs[index]];

    if (category != null) {
      context.read<MapBloc>().add(FetchNearbyAttractions(
        latitude: lat,
        longitude: lng,
        categoryName: category,
        useLegacy: _tabs[index] == 'POI',
      ));
      // Around You is the quick-access surface for these same tabs, so both
      // read the same band-aware result rather than each deriving its own.
      context.read<MapBloc>().add(FetchBandedPlaces(
        latitude: lat,
        longitude: lng,
      ));
    }
  }


  static const String _emergencyCacheKey = 'cached_emergency_data';

  Future<void> _loadEmergencyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_emergencyCacheKey);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final hospitals = (data['hospitals'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];
      final info = data['info'] != null
          ? Map<String, dynamic>.from(data['info'] as Map)
          : null;
      if (mounted) {
        setState(() {
          _nearbyHospitals = hospitals;
          _emergencyInfo = info;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEmergencyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emergencyCacheKey, jsonEncode({
        'hospitals': _nearbyHospitals,
        'info': _emergencyInfo,
      }));
    } catch (_) {}
  }

  Future<void> _fetchEmergencyData() async {
    // Same precedence as _fetchForTab, and it matters more here: a hospital list
    // for the wrong city is worse than no list at all.
    final lat = _currentPosition?.latitude ?? CacheService.getLastFetchLat();
    final lng = _currentPosition?.longitude ?? CacheService.getLastFetchLng();
    if (lat == null || lng == null || _isLoadingEmergency) return;
    // Load cache first for instant display
    await _loadEmergencyCache();
    setState(() => _isLoadingEmergency = true);

    try {
      // Fetch nearby hospitals from backend (Redis > PostgreSQL DB > Google Nearby Search)
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/places/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': 5000,
          'category': 'Hospital',
          'limit': 5,
        },
      );
      final List<Map<String, dynamic>> hospitals = [];
      final Set<String> seenHospitalKeys = {};
      if (response.statusCode == 200) {
        final data = response.data;
        final places = data['places'] as List? ?? [];
        for (final place in places) {
          final rawName = (place['name'] as String? ?? 'Hospital').trim();
          final placeId = (place['id'] as String? ?? '').trim();
          final normName = rawName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (seenHospitalKeys.contains(normName) || (placeId.isNotEmpty && seenHospitalKeys.contains(placeId))) {
            continue;
          }
          if (normName.isNotEmpty) seenHospitalKeys.add(normName);
          if (placeId.isNotEmpty) seenHospitalKeys.add(placeId);

          final plat = (place['latitude'] as num?)?.toDouble() ?? lat;
          final plng = (place['longitude'] as num?)?.toDouble() ?? lng;
          final d = Geolocator.distanceBetween(lat, lng, plat, plng);
          final distKm = d / 1000;

          hospitals.add({
            'name': rawName,
            'address': place['address'] ?? '',
            'dist': '${distKm.toStringAsFixed(1)} km',
            'open': place['opening_hours']?['open_now'],
            'placeId': placeId,
            'lat': plat,
            'lng': plng,
          });
          if (hospitals.length >= 5) break;
        }
        hospitals.sort((a, b) {
          final da = double.tryParse((a['dist'] as String).replaceAll(' km', '')) ?? 999;
          final db = double.tryParse((b['dist'] as String).replaceAll(' km', '')) ?? 999;
          return da.compareTo(db);
        });
      }

      // Use the exact reverse-geocoded location name (matching homepage top-left)
      String locationName = CacheService.getLastFetchLocationName() ?? '';
      String countryName = 'Sri Lanka';
      if (locationName.isEmpty || locationName == 'Nearby' || locationName == 'Locating...') {
        final detailed = await GooglePlacesService.reverseGeocodeDetailed(lat, lng);
        locationName = detailed['location_name'] ?? 'Nearby';
        countryName = detailed['country'] ?? 'Sri Lanka';
      }

      final geminiPrompt =
          'I am a traveller currently in "$locationName, $countryName" (GPS coordinates: $lat, $lng). '
          'Give me ONLY a JSON object with these fields (no markdown): '
          '{ "country": "$countryName", "city": "$locationName", "emergency_numbers": [{"label":"Police","number":"..."},{"label":"Ambulance","number":"..."},{"label":"Fire","number":"..."},{"label":"Tourist Helpline","number":"..."}], '
          '"phrases": [{"english":"Help!","local":"..."},{"english":"I need a doctor","local":"..."},{"english":"Where is the hospital?","local":"..."},{"english":"Call the police","local":"..."}] }';

      final rawGemini = await GeminiService().getResponse(geminiPrompt);
      Map<String, dynamic>? info;
      try {
        String json = rawGemini.trim();
        if (json.contains('```')) {
          json = json.replaceAll(RegExp(r'```json?\n?'), '').replaceAll(RegExp(r'\n?```'), '');
        }
        info = jsonDecode(json) as Map<String, dynamic>;
        info['city'] = locationName;
        info['country'] = countryName;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _nearbyHospitals = hospitals;
          _emergencyInfo = info;
          _isLoadingEmergency = false;
        });
        _saveEmergencyCache();
      }
    } catch (e) {
      debugPrint('Emergency fetch error: $e');
      if (mounted) setState(() => _isLoadingEmergency = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocListener<MapBloc, MapState>(
          listener: (context, state) {},
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => AppColors.primaryGradient.createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                      child: const Text(
                        'Discover',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab selector
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SizedBox(
                  height: 40,
                  child: ListView.builder(
                    controller: _tabScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) {
                      final isActive = _selectedTab == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTab = index;
                            _clearSubCategories();
                          });
                          _fetchForTab(index);
                          if (_tabs[index] == 'Emergency') _fetchEmergencyData();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isActive ? AppColors.brandGreen : AppColors.surfaceVariant,
                            border: Border.all(color: isActive ? Colors.transparent : AppColors.border),
                            boxShadow: isActive
                                ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.3), blurRadius: 10)]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              _tabs[index],
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
                ),
              ),

              // Content
              Expanded(
                child: BlocBuilder<MapBloc, MapState>(
                  builder: (context, state) {
                    final activeTab = _tabs[_selectedTab];
                    final sections = PlaceSections.sectionsFrom(state);

                    // Only shimmer while this specific tab has nothing to show
                    // yet. Gating on the global status alone used to shimmer
                    // every tab together (even ones whose data had already
                    // arrived) and re-blanked a tab that already had good data
                    // during a background refresh. A tab still being enriched
                    // in the background (MapState.enrichingCategories) also
                    // keeps shimmering instead of flashing empty right before
                    // the richer result lands.
                    final activeSectionKey =
                        activeTab == 'Food' ? 'Food & Drink' : activeTab;
                    final isCategoryLoading =
                        state.loadingBandCategories.contains(activeSectionKey) ||
                        state.enrichingCategories.contains(activeSectionKey);
                    final isLoading = activeTab != 'Emergency' &&
                        (state.status == MapStatus.loading || state.status == MapStatus.initial || isCategoryLoading) &&
                        (sections[activeSectionKey] ?? []).isEmpty;

                    if (activeTab == 'POI') {
                      _poiList = sections['POI'] ?? [];
                      if (_selectedPoiCategory != null) {
                        _poiList = _poiList.where((a) {
                          final cat = (a.categoryName ?? '').toLowerCase();
                          final name = a.name.toLowerCase();
                          final tags = PlaceSections.tagsOf(a);
                          if (_selectedPoiCategory == 'Landmarks') {
                            return cat.contains('landmark') || cat.contains('monument') || cat.contains('historic') || name.contains('landmark') || name.contains('monument') || name.contains('statue') || name.contains('palace') || name.contains('fort');
                          } else if (_selectedPoiCategory == 'Culture') {
                            return cat.contains('culture') || cat.contains('temple') || cat.contains('church') || cat.contains('place of worship') || cat.contains('historic') || name.contains('temple') || name.contains('cathedral') || name.contains('church') || name.contains('monument') || tags.contains('hindu_temple') || tags.contains('place_of_worship');
                          } else if (_selectedPoiCategory == 'Museums') {
                            return cat.contains('museum') || cat.contains('gallery') || name.contains('museum') || name.contains('gallery') || tags.contains('museum') || tags.contains('art_gallery');
                          } else if (_selectedPoiCategory == 'Leisure') {
                            return tags.contains('zoo') || tags.contains('aquarium') || tags.contains('amusement_park') || tags.contains('water_park') || tags.contains('planetarium') || tags.contains('performing_arts_theater') || cat.contains('zoo') || cat.contains('experience') || name.contains('zoo') || name.contains('aquarium') || name.contains('theatre') || name.contains('theater');
                          }
                          return true;
                        }).toList();
                      }
                      _poiList.sort((a, b) {
                        int ratingComp = b.rating.compareTo(a.rating);
                        if (ratingComp != 0) return ratingComp;
                        return (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
                      });
                      _poiList = _deduplicateAttractions(_poiList);
                    } else if (activeTab == 'Nature') {
                      _natureList = sections['Nature'] ?? [];
                      if (_selectedNatureCategory != null) {
                        _natureList = _natureList.where((a) {
                          final cat = (a.categoryName ?? '').toLowerCase();
                          final name = a.name.toLowerCase();
                          final tags = PlaceSections.tagsOf(a);
                          if (_selectedNatureCategory == 'Beaches') {
                            return cat.contains('beach') || cat.contains('coast') || cat.contains('sea') || name.contains('beach') || name.contains('coast') || name.contains('bay') || tags.contains('beach');
                          } else if (_selectedNatureCategory == 'Parks') {
                            return cat.contains('park') || cat.contains('garden') || name.contains('park') || name.contains('garden') || tags.contains('park') || tags.contains('national_park') || tags.contains('botanical_garden') || tags.contains('garden');
                          } else if (_selectedNatureCategory == 'Waterfalls') {
                            return cat.contains('waterfall') || name.contains('waterfall') || name.contains('falls');
                          } else if (_selectedNatureCategory == 'Lakes') {
                            return cat.contains('lake') || cat.contains('river') || name.contains('lake') || name.contains('river') || name.contains('lagoon') || name.contains('reservoir') || tags.contains('lake') || tags.contains('river');
                          } else if (_selectedNatureCategory == 'Wildlife') {
                            return name.contains('sanctuary') || name.contains('safari') || name.contains('wildlife') || tags.contains('wildlife_park') || tags.contains('wildlife_refuge') || tags.contains('hiking_area');
                          }
                          return true;
                        }).toList();
                      }
                      _natureList.sort((a, b) {
                        int ratingComp = b.rating.compareTo(a.rating);
                        if (ratingComp != 0) return ratingComp;
                        return (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
                      });
                      _natureList = _deduplicateAttractions(_natureList);
                    } else if (activeTab == 'Food') {
                      _foodList = sections['Food & Drink'] ?? [];
                      if (_selectedFoodCategory != null) {
                        _foodList = _foodList.where((a) {
                          final cat = (a.categoryName ?? '').toLowerCase();
                          final name = a.name.toLowerCase();
                          if (_selectedFoodCategory == 'Street Food') {
                            return cat.contains('street') || cat.contains('fast') || cat.contains('takeaway') || cat.contains('snack') || name.contains('street') || name.contains('burger') || name.contains('kiosk');
                          } else if (_selectedFoodCategory == 'Fine Dining') {
                            final isCafeOrStreet = cat.contains('cafe') || cat.contains('coffee') || cat.contains('street') || cat.contains('fast') || cat.contains('takeaway') || name.contains('cafe') || name.contains('street');
                            return !isCafeOrStreet && (cat.contains('dining') || cat.contains('restaurant') || cat.contains('bistro') || cat.contains('hotel') || name.contains('fine') || name.contains('restaurant') || name.contains('hotel') || name.contains('grill'));
                          } else if (_selectedFoodCategory == 'Cafés') {
                            return cat.contains('cafe') || cat.contains('coffee') || cat.contains('tea') || cat.contains('bakery') || cat.contains('dessert') || name.contains('cafe') || name.contains('coffee') || name.contains('bakery');
                          }
                          return true;
                        }).toList();
                      }
                      _foodList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
                      _foodList = _deduplicateAttractions(_foodList);
                    } else if (activeTab == 'Shopping') {
                      _shoppingList = sections['Shopping'] ?? [];
                      if (_selectedShoppingCategory != null) {
                        _shoppingList = _shoppingList.where((a) {
                          final cat = (a.categoryName ?? '').toLowerCase();
                          final name = a.name.toLowerCase();
                          if (_selectedShoppingCategory == 'Tech') {
                            return cat.contains('electronic') || cat.contains('tech') || cat.contains('phone') || cat.contains('computer') || name.contains('tech') || name.contains('mobile') || name.contains('electronic');
                          } else if (_selectedShoppingCategory == 'Local') {
                            return cat.contains('market') || cat.contains('gift') || cat.contains('souvenir') || cat.contains('craft') || cat.contains('local') || name.contains('market') || name.contains('bazaar') || name.contains('gift');
                          }
                          return true;
                        }).toList();
                      }
                      _shoppingList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
                      _shoppingList = _deduplicateAttractions(_shoppingList);
                    } else if (activeTab == 'Medical') {
                      _medicalList = sections['Medical'] ?? [];
                      if (_selectedMedicalCategory != null) {
                        _medicalList = _medicalList.where((a) {
                          final cat = (a.categoryName ?? '').toLowerCase();
                          final name = a.name.toLowerCase();
                          final tags = PlaceSections.tagsOf(a);
                          if (_selectedMedicalCategory == 'Clinics') {
                            return cat.contains('clinic') || name.contains('clinic') || tags.contains('doctor') || tags.contains('medical_clinic');
                          } else if (_selectedMedicalCategory == 'Pharmacies') {
                            return cat.contains('pharmacy') || name.contains('pharmacy') || tags.contains('pharmacy') || tags.contains('drugstore');
                          } else if (_selectedMedicalCategory == 'Dental') {
                            return name.contains('dental') || name.contains('dentist') || tags.contains('dentist') || tags.contains('dental_clinic');
                          } else if (_selectedMedicalCategory == 'Labs') {
                            return name.contains('laborator') || name.contains('lab ') || name.contains('scan') || tags.contains('medical_lab') || tags.contains('physiotherapist');
                          }
                          return true;
                        }).toList();
                      }
                      _medicalList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
                      _medicalList = _deduplicateAttractions(_medicalList);
                    } else if (activeTab == 'Hospital') {
                      _hospitalList = sections['Hospital'] ?? [];
                      if (_selectedHospitalCategory != null) {
                        _hospitalList = _hospitalList.where((a) {
                          final name = a.name.toLowerCase();
                          if (_selectedHospitalCategory == 'Government') {
                            return name.contains('general') || name.contains('base ') || name.contains('district') ||
                                   name.contains('teaching') || name.contains('national') || name.contains('government');
                          } else if (_selectedHospitalCategory == 'Private') {
                            return !(name.contains('general') || name.contains('base ') || name.contains('district') ||
                                     name.contains('teaching') || name.contains('national') || name.contains('government'));
                          } else if (_selectedHospitalCategory == 'Maternity') {
                            return name.contains('maternity') || name.contains('children') || name.contains('women');
                          }
                          return true;
                        }).toList();
                      }
                      _hospitalList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
                      _hospitalList = _deduplicateAttractions(_hospitalList);
                    }

                    return Column(
                      children: [
                        
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _buildTabContent(isLoading),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section membership ──────────────────────────────────────────────────
  // Mirrors `place_bands.py` on the backend. POI/Nature and Hospital/Medical
  // each split a single pool, so a place lands in exactly one of each pair —
  // otherwise the same beach is listed under both POI and Nature.


  List<AttractionEntity> _deduplicateAttractions(List<AttractionEntity> list) {
    final seenKeys = <String>{};
    final result = <AttractionEntity>[];
    for (final a in list) {
      final nameKey = a.name.trim().toLowerCase();
      final idKey = a.id.trim();
      if ((nameKey.isNotEmpty && seenKeys.contains(nameKey)) ||
          (idKey.isNotEmpty && seenKeys.contains(idKey))) {
        continue;
      }
      if (nameKey.isNotEmpty) seenKeys.add(nameKey);
      if (idKey.isNotEmpty) seenKeys.add(idKey);
      result.add(a);
    }
    return result;
  }

  Widget _buildTabContent(bool isLoading) {
    switch (_tabs[_selectedTab]) {
      case 'POI': return _buildPoiTab(isLoading);
      case 'Nature': return _buildNatureTab(isLoading);
      case 'Food': return _buildFoodTab(isLoading);
      case 'Shopping': return _buildShoppingTab(isLoading);
      case 'Medical': return _buildMedicalTab(isLoading);
      case 'Hospital': return _buildHospitalTab(isLoading);
      case 'Emergency': return _buildEmergencyTab();
      default: return _buildPoiTab(isLoading);
    }
  }

  // ═══════════════════════════════════════
  // NATURE TAB
  // ═══════════════════════════════════════
  Widget _buildNatureTab(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Explore Nature & Outdoors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _buildExperienceCategoryItem(
                '🏖',
                'Beaches',
                _selectedNatureCategory == 'Beaches',
                () => setState(() {
                  _selectedNatureCategory = _selectedNatureCategory == 'Beaches' ? null : 'Beaches';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🌳',
                'Parks',
                _selectedNatureCategory == 'Parks',
                () => setState(() {
                  _selectedNatureCategory = _selectedNatureCategory == 'Parks' ? null : 'Parks';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🌊',
                'Waterfalls',
                _selectedNatureCategory == 'Waterfalls',
                () => setState(() {
                  _selectedNatureCategory = _selectedNatureCategory == 'Waterfalls' ? null : 'Waterfalls';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🛶',
                'Lakes',
                _selectedNatureCategory == 'Lakes',
                () => setState(() {
                  _selectedNatureCategory = _selectedNatureCategory == 'Lakes' ? null : 'Lakes';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🐘',
                'Wildlife',
                _selectedNatureCategory == 'Wildlife',
                () => setState(() {
                  _selectedNatureCategory = _selectedNatureCategory == 'Wildlife' ? null : 'Wildlife';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text('Nature Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: _natureList,
          isLoading: isLoading,
          emptyMessage: 'No natural spots found nearby.',
          defaultCategory: 'Nature',
          emoji: '🌳',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // HOSPITAL TAB
  // ═══════════════════════════════════════
  Widget _buildHospitalTab(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Find a Hospital', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _buildExperienceCategoryItem(
                '🏛',
                'Government',
                _selectedHospitalCategory == 'Government',
                () => setState(() {
                  _selectedHospitalCategory = _selectedHospitalCategory == 'Government' ? null : 'Government';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🏥',
                'Private',
                _selectedHospitalCategory == 'Private',
                () => setState(() {
                  _selectedHospitalCategory = _selectedHospitalCategory == 'Private' ? null : 'Private';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '👶',
                'Maternity',
                _selectedHospitalCategory == 'Maternity',
                () => setState(() {
                  _selectedHospitalCategory = _selectedHospitalCategory == 'Maternity' ? null : 'Maternity';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text('Hospitals Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: _hospitalList,
          isLoading: isLoading,
          emptyMessage: 'No hospitals found nearby.',
          defaultCategory: 'Hospital',
          emoji: '🏥',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // FOOD TAB
  // ═══════════════════════════════════════
  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_PLACEHOLDER_DELETE_ME() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL_BODY() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL_BODY_REAL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_DO_NOT_CALL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_BODY() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_BODY_REAL() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_UNUSED_DO_NOT_CALL() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_UNUSED_DO_NOT_CALL_BODY() {
    final Map<String, dynamic> result = {};
    final name = result['name'] ?? 'Unknown Place';
    final category = result['category'] ?? 'Place';
    final description = result['description'] ?? '';
    final funFact = result['fun_fact'] ?? '';
    final tips = result['tips'] ?? '';
    final confidence = (result['confidence'] ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Place name + category
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(confidence * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1, end: 0),

        const SizedBox(height: 16),

        // Description
        if (description.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_stories_rounded, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text('About', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textSecondary),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 12),

        // Fun Fact
        if (funFact.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amber.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fun Fact', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(funFact, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 12),

        // Tips
        if (tips.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎒', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Visitor Tip', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(tips, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 20),
      ],
    );
  }

  // ═══════════════════════════════════════
  // FOOD TAB
  // ═══════════════════════════════════════
  Widget _buildFoodTab(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Categories
        const Text('Explore Food & Dining', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _buildExperienceCategoryItem(
                '🍜',
                'Street Food',
                _selectedFoodCategory == 'Street Food',
                () => setState(() {
                  _selectedFoodCategory = _selectedFoodCategory == 'Street Food' ? null : 'Street Food';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🍽',
                'Fine Dining',
                _selectedFoodCategory == 'Fine Dining',
                () => setState(() {
                  _selectedFoodCategory = _selectedFoodCategory == 'Fine Dining' ? null : 'Fine Dining';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '☕',
                'Cafés',
                _selectedFoodCategory == 'Cafés',
                () => setState(() {
                  _selectedFoodCategory = _selectedFoodCategory == 'Cafés' ? null : 'Cafés';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🍕',
                'Fast Food',
                _selectedFoodCategory == 'Fast Food',
                () => setState(() {
                  _selectedFoodCategory = _selectedFoodCategory == 'Fast Food' ? null : 'Fast Food';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🥐',
                'Bakeries',
                _selectedFoodCategory == 'Bakeries',
                () => setState(() {
                  _selectedFoodCategory = _selectedFoodCategory == 'Bakeries' ? null : 'Bakeries';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Restaurant list
        const Text('Food & Dining Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: _foodList,
          isLoading: isLoading,
          emptyMessage: 'No food places found nearby.',
          defaultCategory: 'Food & Drink',
          emoji: '🍽',
        ),
      ],
    );
  }

  Widget _buildFoodRadar() {
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rings
            ...List.generate(3, (i) => Container(
              width: 80.0 + i * 70,
              height: 80.0 + i * 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.1 + i * 0.05)),
              ),
            )),

            // Sweep
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _radarController.value * 2 * pi,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25, 0.5],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Food dots (Real)
            ..._foodList.take(5).toList().asMap().entries.map((e) {
              final a = e.value;
              // Generate pseudo-random coordinates for the radar based on attraction ID
              final random = Random(a.id.hashCode);
              final dx = random.nextDouble() * 0.8 - 0.4;
              final dy = random.nextDouble() * 0.8 - 0.4;
              return _buildRadarDot(dx, dy, a, AppColors.primary);
            }),

            // Center dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 12)],
              ),
            ),

            // Pulse
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .scale(begin: const Offset(1, 1), end: const Offset(5, 5), duration: 2.seconds)
                .fade(begin: 0.6, end: 0),
          ],
        ),
      ),
    ).animate().fade().scale(begin: const Offset(0.8, 0.8));
  }

  Widget _buildRadarDot(double dx, double dy, AttractionEntity place, Color color) {
    return Positioned(
      left: 110 + dx * 200 - 16,
      top: 110 + dy * 200 - 16,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.2),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: AppColors.primary.withOpacity(0.1),
            child: Center(
              child: Icon(
                _getFoodIcon(place.categoryName ?? 'Food', place.name, place.id.hashCode),
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1500.ms),
    );
  }

  IconData _getFoodIcon(String category, String name, int index) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();
    if (cat.contains('cafe') || cat.contains('coffee') || nm.contains('cafe') || nm.contains('coffee')) {
      return Icons.coffee_rounded;
    }
    if (cat.contains('street') || cat.contains('fast') || nm.contains('burger') || nm.contains('pizza')) {
      return Icons.local_pizza_rounded;
    }
    return Icons.restaurant_rounded;
  }

  IconData _getExperienceIcon(String category, String name, int index) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();
    
    // Food & Dining
    if (cat.contains('food') || cat.contains('restaurant') || nm.contains('restaurant') || nm.contains('kitchen') || nm.contains('bistro')) {
      return Icons.restaurant_rounded;
    }
    if (cat.contains('cafe') || cat.contains('coffee') || nm.contains('cafe') || nm.contains('coffee')) {
      return Icons.local_cafe_rounded;
    }
    if (cat.contains('bar') || cat.contains('bakery') || nm.contains('bakery') || nm.contains('sweet')) {
      return Icons.bakery_dining_rounded;
    }

    // Shopping
    if (cat.contains('clothing') || cat.contains('fashion') || nm.contains('fashion') || nm.contains('boutique')) {
      return Icons.shopping_bag_rounded;
    }
    if (cat.contains('market') || cat.contains('local') || nm.contains('market') || nm.contains('bazaar') || nm.contains('mall')) {
      return Icons.storefront_rounded;
    }
    if (cat.contains('shopping') || cat.contains('store') || nm.contains('store') || nm.contains('shop')) {
      return Icons.shopping_cart_rounded;
    }

    // Medical
    if (cat.contains('hospital') || nm.contains('hospital')) {
      return Icons.local_hospital_rounded;
    }
    if (cat.contains('pharmacy') || nm.contains('pharmacy') || nm.contains('drug') || nm.contains('chemist')) {
      return Icons.medication_rounded;
    }
    if (cat.contains('clinic') || cat.contains('medical') || cat.contains('dental') || nm.contains('clinic') || nm.contains('dental') || nm.contains('doctor')) {
      return Icons.medical_services_rounded;
    }

    // POI / Attractions / Nature
    if (cat.contains('beach') || nm.contains('beach')) {
      return Icons.beach_access_rounded;
    }
    if (cat.contains('museum') || cat.contains('gallery') || nm.contains('museum') || nm.contains('gallery')) {
      return Icons.museum_rounded;
    }
    if (cat.contains('park') || cat.contains('garden') || nm.contains('park') || nm.contains('garden')) {
      return Icons.park_rounded;
    }
    if (cat.contains('temple') || cat.contains('church') || cat.contains('mosque') || nm.contains('temple') || nm.contains('kovil') || nm.contains('mosque')) {
      return Icons.account_balance_rounded;
    }
    return Icons.place_rounded;
  }

  IconData _getShoppingIcon(String category, String name, int index) {
    final cat = category.toLowerCase();
    final nm = name.toLowerCase();
    if (cat.contains('clothing') || cat.contains('fashion') || nm.contains('fashion') || nm.contains('boutique')) {
      return Icons.shopping_bag_rounded;
    }
    if (cat.contains('market') || cat.contains('local') || nm.contains('market') || nm.contains('bazaar')) {
      return Icons.storefront_rounded;
    }
    return Icons.shopping_cart_rounded;
  }

  Widget _buildExperienceCategoryItem(String emoji, String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 86,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandGreen : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? Colors.transparent : AppColors.border, width: 1.2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandGreen.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodCategory(String emoji, String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandGreen : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? Colors.transparent : AppColors.border, width: 1.5),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.brandGreen.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerItemCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 16, color: Colors.grey[200]),
          ),
          const SizedBox(width: 16),
          Container(width: 80, height: 14, color: Colors.grey[200]),
          const SizedBox(width: 16),
          Container(width: 20, height: 20, color: Colors.grey[200]),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 1200.ms, color: Colors.white54);
  }

  Widget _buildPlaceListWithSkeleton({
    required List<AttractionEntity> places,
    required bool isLoading,
    required String emptyMessage,
    required String defaultCategory,
    required String emoji,
  }) {
    final loadedCount = places.length;
    if (loadedCount == 0 && !isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(emptyMessage, style: const TextStyle(color: AppColors.textTertiary))),
      );
    }

    // The 9 is how many shimmer rows to stand up while a section is still
    // loading — not a limit on results. Clamping the loaded case to it as well
    // meant every Discovery section stopped at nine places however many came
    // back, which is how Discovery ended up showing *fewer* than Around You
    // despite being the deeper view of the same data: Around You caps at ten on
    // purpose (BAND_QUOTAS), Discovery is meant to show the whole section.
    final itemCount = isLoading ? max(loadedCount, 9) : loadedCount;

    return Column(
      children: List.generate(itemCount, (index) {
        if (index < loadedCount) {
          final place = places[index];
          return _buildExperienceCard(place, index, defaultCategory: defaultCategory, emoji: emoji);
        }
        return _buildShimmerItemCard();
      }),
    );
  }

  Widget _buildPoiTab(bool isLoading) {
    final pois = _poiList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Interests/Categories
        const Text('Explore Points of Interest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _buildExperienceCategoryItem(
                '🗼',
                'Landmarks',
                _selectedPoiCategory == 'Landmarks',
                () => setState(() {
                  _selectedPoiCategory = _selectedPoiCategory == 'Landmarks' ? null : 'Landmarks';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🗿',
                'Culture',
                _selectedPoiCategory == 'Culture',
                () => setState(() {
                  _selectedPoiCategory = _selectedPoiCategory == 'Culture' ? null : 'Culture';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🏛',
                'Museums',
                _selectedPoiCategory == 'Museums',
                () => setState(() {
                  _selectedPoiCategory = _selectedPoiCategory == 'Museums' ? null : 'Museums';
                }),
              ),
              const SizedBox(width: 10),
              // Beaches, Parks and Waterfalls moved to the Nature tab.
              _buildExperienceCategoryItem(
                '🎡',
                'Leisure',
                _selectedPoiCategory == 'Leisure',
                () => setState(() {
                  _selectedPoiCategory = _selectedPoiCategory == 'Leisure' ? null : 'Leisure';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Curated List
        const Text('Points of Interest Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: pois,
          isLoading: isLoading,
          emptyMessage: 'No points of interest found nearby.',
          defaultCategory: 'POI',
          emoji: '📍',
        ),
      ],
    );
  }

  Widget _buildFeaturedExperienceCard(AttractionEntity place, int index) {
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
        width: 260,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
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
                            AppColors.secondary.withOpacity(0.3),
                            AppColors.surfaceVariant,
                          ],
                        ),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Center(
                        child: Opacity(
                          opacity: 0.15,
                          child: Icon(
                            _getExperienceIcon(place.categoryName ?? 'Attraction', place.name, index),
                            size: 120,
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: Text(
                    place.categoryName?.toUpperCase() ?? 'EXPERIENCE',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
                  ),
                ),
                const Spacer(),
                Text(
                  place.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.ratingGold),
                    const SizedBox(width: 4),
                    Text('${place.rating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(width: 12),
                    Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text(
                      '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                    ),
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

  Widget _buildExperienceCard(
    AttractionEntity a,
    int index, {
    String defaultCategory = 'Attraction',
    String emoji = '📍',
  }) {
    final catName = (a.categoryName != null && a.categoryName!.isNotEmpty)
        ? a.categoryName!
        : defaultCategory;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AttractionDetailPage(
            id: a.id,
            name: a.name,
            category: catName,
            rating: a.rating,
            distance: '${((a.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
            emoji: emoji,
            imageUrl: a.photoUrls.isNotEmpty ? a.photoUrls.first : null,
            latitude: a.latitude,
            longitude: a.longitude,
          )),
        ),
        child: GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          glowColor: index % 2 == 0 ? AppColors.secondary : AppColors.primary,
          child: Row(
            children: [
              // Thumbnail (Network Image / Fallback Icon Container)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: a.photoUrls.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: a.photoUrls.first.startsWith('/')
                            ? '${ApiConstants.baseUrl}${a.photoUrls.first}'
                            : a.photoUrls.first,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 90,
                          height: 90,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.image_rounded, size: 24, color: AppColors.textMuted),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 90,
                          height: 90,
                          color: AppColors.secondary.withOpacity(0.1),
                          child: Center(
                            child: Icon(
                              _getExperienceIcon(catName, a.name, index),
                              color: AppColors.secondary,
                              size: 36,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
                        ),
                        child: Center(
                          child: Icon(
                            _getExperienceIcon(catName, a.name, index),
                            color: AppColors.secondary,
                            size: 36,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          catName.toUpperCase(),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1),
                        ),
                        GestureDetector(
                          onTap: () async {
                            if (a is AttractionModel) {
                              await CacheService.toggleFavoritePlace(a.toJson());
                            }
                            setState(() {});
                          },
                          child: Icon(
                            CacheService.isPlaceFavorite(a.id) ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                            color: CacheService.isPlaceFavorite(a.id) ? AppColors.primary : AppColors.textTertiary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                        Text(' ${a.rating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const SizedBox(width: 10),
                        const Icon(Icons.near_me_rounded, size: 12, color: AppColors.textTertiary),
                        Text(' ${((a.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.description ?? 'Discover this unique location near you.',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  // ═══════════════════════════════════════
  // SHOPPING TAB
  // ═══════════════════════════════════════
  Widget _buildShoppingTab(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick categories for shopping
        const Text('Explore Retail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _buildExperienceCategoryItem(
                '💻',
                'Tech',
                _selectedShoppingCategory == 'Tech',
                () => setState(() {
                  _selectedShoppingCategory = _selectedShoppingCategory == 'Tech' ? null : 'Tech';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🏺',
                'Local',
                _selectedShoppingCategory == 'Local',
                () => setState(() {
                  _selectedShoppingCategory = _selectedShoppingCategory == 'Local' ? null : 'Local';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🏬',
                'Malls',
                _selectedShoppingCategory == 'Malls',
                () => setState(() {
                  _selectedShoppingCategory = _selectedShoppingCategory == 'Malls' ? null : 'Malls';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🛒',
                'Supermarkets',
                _selectedShoppingCategory == 'Supermarkets',
                () => setState(() {
                  _selectedShoppingCategory = _selectedShoppingCategory == 'Supermarkets' ? null : 'Supermarkets';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text('Markets & Shops Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: _shoppingList,
          isLoading: isLoading,
          emptyMessage: 'No shops found nearby.',
          defaultCategory: 'Shopping',
          emoji: '🛍',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  // MEDICAL TAB
  // ═══════════════════════════════════════
  Widget _buildMedicalTab(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Explore Pharmacies & Clinics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              // Hospitals have their own tab now.
              _buildExperienceCategoryItem(
                '🩺',
                'Clinics',
                _selectedMedicalCategory == 'Clinics',
                () => setState(() {
                  _selectedMedicalCategory = _selectedMedicalCategory == 'Clinics' ? null : 'Clinics';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '💊',
                'Pharmacies',
                _selectedMedicalCategory == 'Pharmacies',
                () => setState(() {
                  _selectedMedicalCategory = _selectedMedicalCategory == 'Pharmacies' ? null : 'Pharmacies';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🦷',
                'Dental',
                _selectedMedicalCategory == 'Dental',
                () => setState(() {
                  _selectedMedicalCategory = _selectedMedicalCategory == 'Dental' ? null : 'Dental';
                }),
              ),
              const SizedBox(width: 10),
              _buildExperienceCategoryItem(
                '🔬',
                'Labs',
                _selectedMedicalCategory == 'Labs',
                () => setState(() {
                  _selectedMedicalCategory = _selectedMedicalCategory == 'Labs' ? null : 'Labs';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text('Pharmacies & Clinics Around You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPlaceListWithSkeleton(
          places: _medicalList,
          isLoading: isLoading,
          emptyMessage: 'No medical facilities found nearby.',
          defaultCategory: 'Medical',
          emoji: '💊',
        ),
      ],
    );
  }





  // ═══════════════════════════════════════
  // BUDGET TAB
  // ═══════════════════════════════════════
  Widget _buildBudgetTab() {
    return BlocListener<BudgetBloc, BudgetState>(
      listener: (context, state) {
        if (state is BudgetError) {
          if (state.message.contains('401') || state.message.contains('token')) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (state is BudgetClosed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget closed successfully! You can now start a new one.'),
              backgroundColor: AppColors.secondary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh to show NoBudgetFound state
          context.read<BudgetBloc>().add(FetchBudget());
        }
      },
      child: BlocBuilder<BudgetBloc, BudgetState>(
        buildWhen: (previous, current) => 
            current is! BudgetHistoryLoaded && 
            current is! BudgetDetailLoaded && 
            current is! BudgetHistoryLoading && 
            current is! BudgetDetailLoading,
        builder: (context, state) {
          if (state is BudgetLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is BudgetLoaded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.isFromCache)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        const Text('Refreshing...', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                      ],
                    ),
                  ),
                _buildBudgetUI(state.budget),
              ],
            );
          } else if (state is BudgetClosed || state is NoBudgetFound) {
            return _buildNoBudgetUI();
          } else if (state is BudgetError) {
            return _buildErrorUI(state.message);
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildNoBudgetUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(Icons.account_balance_wallet_rounded, size: 80, color: AppColors.primary.withOpacity(0.3)),
        const SizedBox(height: 24),
        const Text(
          'No Budget Set Yet',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        const Text(
          'Setup a budget to track your spending and get AI suggestions for your trip.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppColors.primaryGradient,
            ),
            child: ElevatedButton(
              onPressed: () => _showSetupBudgetModal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('SETUP BUDGET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            context.read<BudgetBloc>().add(FetchBudgetHistory());
            _showHistoryModal();
          },
          icon: const Icon(Icons.history_rounded, size: 20, color: AppColors.secondary),
          label: const Text('VIEW BUDGET HISTORY', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Budget History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<BudgetBloc, BudgetState>(
                buildWhen: (previous, current) => current is BudgetHistoryLoaded || current is BudgetHistoryLoading,
                builder: (context, state) {
                  if (state is BudgetHistoryLoaded) {
                    if (state.budgets.isEmpty) {
                      return const Center(child: Text('No past budgets', style: TextStyle(color: AppColors.textTertiary)));
                    }
                    return ListView.builder(
                      itemCount: state.budgets.length,
                      itemBuilder: (context, index) {
                        final b = state.budgets[index];
                        return InkWell(
                          onTap: () {
                            context.read<BudgetBloc>().add(FetchBudgetById(b.id));
                            _showBudgetDetailModal(b.name);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: GlassCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: b.isActive ? AppColors.primary.withOpacity(0.1) : AppColors.textTertiary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    b.isActive ? Icons.account_balance_wallet_rounded : Icons.history_rounded,
                                    color: b.isActive ? AppColors.primary : AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                      Text(
                                        '${DateFormat('MMM d').format(b.startDate)} - ${DateFormat('MMM d').format(b.endDate)}',
                                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${b.currency} ${formatAmount(b.totalSpent)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: b.totalSpent > b.totalAmount ? AppColors.error : AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '/ ${formatAmount(b.totalAmount)}',
                                      style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  } else if (state is BudgetHistoryLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBudgetDetailModal(String budgetName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
                ),
                Text(budgetName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<BudgetBloc, BudgetState>(
                buildWhen: (previous, current) => current is BudgetDetailLoaded || current is BudgetDetailLoading,
                builder: (context, state) {
                  if (state is BudgetDetailLoaded) {
                    final budget = state.budget;
                    if (budget.expenses.isEmpty) {
                      return const Center(child: Text('No expenses recorded for this budget', style: TextStyle(color: AppColors.textTertiary)));
                    }
                    return Column(
                      children: [
                        _buildCategoryBreakdown(budget),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: budget.expenses.length,
                            itemBuilder: (context, index) {
                              final e = budget.expenses[index];
                              return _buildTransaction(
                                e.description ?? e.category,
                                _getCategoryEmoji(e.category),
                                ConvertedCurrencyText(
                                  amount: e.amount,
                                  originalCurrency: budget.currency,
                                  prefix: '-',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 14),
                                ),
                                DateFormat('MMM d, hh:mm a').format(e.spentAt),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  } else if (state is BudgetDetailLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetUI(budget_entity.Budget budget) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Today's budget overview
        GlassCard(
          padding: const EdgeInsets.all(20),
          glowColor: budget.isOverBudget ? AppColors.error : AppColors.primary,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(budget.name.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text(
                          budget.isExpired ? 'EXPIRED' : '${budget.daysLeft} DAYS LEFT',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: budget.isExpired ? AppColors.error : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          title: const Text('Close Budget', style: TextStyle(color: Colors.white)),
                          content: const Text('Are you sure you want to close this budget? You can start a new one after closing.', style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                            ElevatedButton(
                              onPressed: () {
                                context.read<BudgetBloc>().add(CloseBudgetEvent());
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                              child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (b) => (budget.isOverBudget ? const LinearGradient(colors: [AppColors.error, AppColors.error]) : AppColors.primaryGradient).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                child: ConvertedCurrencyText(
                  amount: budget.spentAmount,
                  originalCurrency: budget.currency,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (budget.isOverBudget)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ConvertedCurrencyText(
                    amount: budget.overAmount,
                    originalCurrency: budget.currency,
                    prefix: '+',
                    suffix: ' OVER BUDGET',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('of ', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                  ConvertedCurrencyText(
                    amount: budget.totalAmount,
                    originalCurrency: budget.currency,
                    suffix: ' total budget',
                    style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Container(height: 8, color: AppColors.surfaceVariant),
                    FractionallySizedBox(
                      widthFactor: budget.spentPercentage.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: budget.isOverBudget 
                            ? const LinearGradient(colors: [AppColors.error, AppColors.error]) 
                            : AppColors.primaryGradient,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(budget.spentPercentage * 100).toStringAsFixed(0)}% used', style: TextStyle(fontSize: 11, color: budget.isOverBudget ? AppColors.error : AppColors.primary, fontWeight: FontWeight.w600)),
                  InkWell(
                    onTap: () {
                      context.read<BudgetBloc>().add(FetchBudgetHistory());
                      _showHistoryModal();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 14, color: AppColors.secondary),
                          const SizedBox(width: 4),
                          const Text('HISTORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.secondary, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fade(),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextButton.icon(
              onPressed: () => _showAddExpenseModal(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Expense', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCategoryBreakdown(budget),

        const SizedBox(height: 24),
        const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        if (budget.expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No transactions yet', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          ...budget.expenses.take(10).map((e) => _buildTransaction(
                e.description ?? e.category,
                _getCategoryEmoji(e.category),
                ConvertedCurrencyText(
                  amount: e.amount,
                  originalCurrency: budget.currency,
                  prefix: '-',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 14),
                ),
                DateFormat('hh:mm a').format(e.spentAt),
              )),
        
        const SizedBox(height: 30),
        // AI Suggestion Box (Future placeholder)
        _buildAISuggestionBox(budget),
      ],
    );
  }

  Widget _buildCategoryBreakdown(budget_entity.Budget budget) {
    final categories = ['Food', 'Transport', 'Shopping', 'Activities', 'Other'];
    final Map<String, double> totals = {};
    for (var cat in categories) {
      totals[cat] = budget.expenses
          .where((e) => e.category == cat)
          .fold(0.0, (sum, e) => sum + e.amount);
    }

    return Column(
      children: [
        _buildBudgetCategory(
          '🍽',
          'Food',
          ConvertedCurrencyText(
            amount: totals['Food']!,
            originalCurrency: budget.currency,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
          ),
          budget.totalAmount == 0 ? 0.0 : (totals['Food']! / budget.totalAmount).clamp(0.0, 1.0),
          AppColors.accent,
          0,
        ),
        _buildBudgetCategory(
          '🚕',
          'Transport',
          ConvertedCurrencyText(
            amount: totals['Transport']!,
            originalCurrency: budget.currency,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
          ),
          budget.totalAmount == 0 ? 0.0 : (totals['Transport']! / budget.totalAmount).clamp(0.0, 1.0),
          AppColors.secondary,
          1,
        ),
        _buildBudgetCategory(
          '🛍',
          'Shopping',
          ConvertedCurrencyText(
            amount: totals['Shopping']!,
            originalCurrency: budget.currency,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
          ),
          budget.totalAmount == 0 ? 0.0 : (totals['Shopping']! / budget.totalAmount).clamp(0.0, 1.0),
          AppColors.warning,
          2,
        ),
        _buildBudgetCategory(
          '🎫',
          'Activities',
          ConvertedCurrencyText(
            amount: totals['Activities']!,
            originalCurrency: budget.currency,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13),
          ),
          budget.totalAmount == 0 ? 0.0 : (totals['Activities']! / budget.totalAmount).clamp(0.0, 1.0),
          AppColors.neonGreen,
          3,
        ),
      ],
    );
  }

  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Food': return '🍽';
      case 'Transport': return '🚕';
      case 'Shopping': return '🛍';
      case 'Activities': return '🎫';
      default: return '💰';
    }
  }

  Widget _buildAISuggestionBox(budget_entity.Budget budget) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              const Text('AI BUDGET ADVISOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.secondary, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.5, fontFamily: 'Outfit'),
              children: [
                const TextSpan(text: 'Based on your spending, you are doing great! Try to limit food expenses to '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ConvertedCurrencyText(
                    amount: 2000,
                    originalCurrency: 'LKR',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const TextSpan(text: ' for the next 2 days to stay within budget.'),
              ],
            ),
          ),
        ],
      ),
    ).animate().shimmer(delay: 2.seconds);
  }

  void _showSetupBudgetModal() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final daysController = TextEditingController(text: '1');
    final budgetBloc = context.read<BudgetBloc>();

    final authState = context.read<AuthBloc>().state;
    String userCurrency = 'USD';
    if (authState is AuthAuthenticated) {
      userCurrency = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BlocProvider.value(
        value: budgetBloc,
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Setup Budget', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const Text('Plan your journey by setting a total budget.', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Budget Name',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.edit_note_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Total Amount ($userCurrency)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.payments_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Duration (Days)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.isNotEmpty ? nameController.text : 'My Budget';
                      final amount = double.tryParse(amountController.text) ?? 0;
                      final days = int.tryParse(daysController.text) ?? 1;
                      if (amount > 0) {
                        final authState = context.read<AuthBloc>().state;
                        String userCurrency = 'USD';
                        if (authState is AuthAuthenticated) {
                          userCurrency = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
                        }
                        budgetBloc.add(SetupBudgetEvent(
                          name: name,
                          totalAmount: amount,
                          startDate: DateTime.now(),
                          endDate: DateTime.now().add(Duration(days: days)),
                          currency: userCurrency,
                        ));
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('CONFIRM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddExpenseModal() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final budgetBloc = context.read<BudgetBloc>();
    String selectedCategory = 'Food';

    String budgetCurrency = 'USD';
    if (budgetBloc.state is BudgetLoaded) {
      budgetCurrency = (budgetBloc.state as BudgetLoaded).budget.currency;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BlocProvider.value(
        value: budgetBloc,
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Expense', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 24),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Amount ($budgetCurrency)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.remove_circle_outline, color: AppColors.error),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.description_outlined, color: AppColors.textTertiary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var cat in ['Food', 'Transport', 'Shopping', 'Activities', 'Other'])
                      GestureDetector(
                        onTap: () => setModalState(() => selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedCategory == cat ? AppColors.primary : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selectedCategory == cat ? Colors.transparent : AppColors.border),
                          ),
                          child: Text(cat, style: TextStyle(color: selectedCategory == cat ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final amount = double.tryParse(amountController.text) ?? 0;
                      if (amount > 0) {
                        budgetBloc.add(AddExpenseEvent(
                          amount: amount,
                          category: selectedCategory,
                          description: descController.text.isEmpty ? null : descController.text,
                        ));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Expense of $budgetCurrency ${formatAmount(amount)} added successfully!'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('ADD EXPENSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetCategory(String emoji, String title, Widget amountWidget, double progress, Color color, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    amountWidget,
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: (index * 100).milliseconds).fade().slideX(begin: 0.05, end: 0);
  }

  Widget _buildTransaction(String title, String emoji, Widget amountWidget, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(time, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          amountWidget,
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // EMERGENCY TAB
  // ═══════════════════════════════════════
  Widget _buildEmergencyTab() {
    final numbers = (_emergencyInfo?['emergency_numbers'] as List?)?.cast<Map>() ?? [];
    final phrases = (_emergencyInfo?['phrases'] as List?)?.cast<Map>() ?? [];
    final cachedName = CacheService.getLastFetchLocationName();
    final city = (_emergencyInfo?['city'] as String?) ?? cachedName;
    final country = _emergencyInfo?['country'] as String?;
    final locationLabel = (cachedName != null && cachedName.isNotEmpty && cachedName != 'Nearby' && cachedName != 'Locating...')
        ? cachedName
        : [city, country].where((s) => s != null && s.isNotEmpty).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SOS button
        Center(
          child: GestureDetector(
            onTap: () {
              final firstNumber = numbers.isNotEmpty ? numbers[0]['number'] as String? : null;
              if (firstNumber != null) {
                _makePhoneCall(firstNumber);
              }
            },
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withOpacity(0.15),
                border: Border.all(color: AppColors.error.withOpacity(0.4), width: 3),
                boxShadow: [BoxShadow(color: AppColors.error.withOpacity(0.2), blurRadius: 30)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emergency_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 6),
                  Text('SOS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error, letterSpacing: 3)),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1.seconds),
          ),
        ).animate().fade(),

        if (locationLabel.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_rounded, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(locationLabel, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        // Loading state — full spinner only when no cache, else subtle banner
        if (_isLoadingEmergency && _nearbyHospitals.isEmpty && _emergencyInfo == null)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Fetching emergency info for your location...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ))
        else ...[
          if (_isLoadingEmergency)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  const Text('Updating location data...', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ],
              ),
            ),
          // Nearby Hospitals
          const Text('Nearby Hospitals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (_nearbyHospitals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('No hospitals found nearby.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...List.generate(_nearbyHospitals.length, (i) {
              final h = _nearbyHospitals[i];
              return _buildHospitalCard(h['name'], h['dist'], h['address'], h['lat'], h['lng'], i);
            }),

          const SizedBox(height: 24),

          // Emergency Numbers
          const Text('Emergency Numbers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (numbers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Could not fetch emergency numbers.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...numbers.map((n) {
              final label = n['label'] as String? ?? '';
              final number = n['number'] as String? ?? '';
              final icon = _emergencyIcon(label);
              return _buildEmergencyNumber(label, number, icon);
            }),

          const SizedBox(height: 24),

          // Emergency Phrases
          const Text('Emergency Phrases', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (phrases.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Could not fetch local phrases.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...phrases.map((p) => _buildPhrase(
              p['english'] as String? ?? '',
              p['local'] as String? ?? '',
            )),
        ],
      ],
    );
  }

  IconData _emergencyIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('police')) return Icons.local_police_rounded;
    if (l.contains('ambulance') || l.contains('medical')) return Icons.medical_services_rounded;
    if (l.contains('fire')) return Icons.local_fire_department_rounded;
    if (l.contains('tourist') || l.contains('helpline')) return Icons.support_agent_rounded;
    return Icons.phone_rounded;
  }

  Widget _buildHospitalCard(String name, String dist, String address, double lat, double lng, int index) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.error.withOpacity(0.1),
              ),
              child: const Icon(Icons.local_hospital_rounded, color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.near_me_rounded, size: 12, color: AppColors.brandGreen),
                      const SizedBox(width: 4),
                      Text(dist, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brandGreen)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GoogleMapsPage(
                      initialLat: lat,
                      initialLng: lng,
                      destinationName: name,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.error.withOpacity(0.15),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.directions_rounded, color: AppColors.error, size: 14),
                    SizedBox(width: 4),
                    Text('Go', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanNumber.isEmpty) return;
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: cleanNumber,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Could not launch dialer for $phoneNumber: $e');
    }
  }

  Widget _buildEmergencyNumber(String label, String number, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _makePhoneCall(number),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.error),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  number,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.phone_rounded, size: 16, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhrase(String english, String local) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(english, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(local, style: TextStyle(fontSize: 13, color: AppColors.primary)),
        ],
      ),
    );
  }
  Widget _buildErrorUI(String message) {
    bool isAuthError = message.contains('401') || message.contains('token');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(
          isAuthError ? Icons.lock_person_rounded : Icons.error_outline_rounded,
          size: 80,
          color: AppColors.error.withOpacity(0.3),
        ),
        const SizedBox(height: 24),
        Text(
          isAuthError ? 'Authentication Required' : 'Something went wrong',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            isAuthError ? 'Please log in to your account to use the budget tracking feature.' : message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
        if (isAuthError)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                context.read<BudgetBloc>().add(FetchBudget());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            context.read<BudgetBloc>().add(FetchBudgetHistory());
            _showHistoryModal();
          },
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('VIEW PAST BUDGETS'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
        ),
      ],
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  ImageProvider _getImageProvider(String? url, String category, String name) {
    return PlaceImageHelper.getImageProvider(url, category, name);
  }

  Widget _buildImageWidget(String? url, String category, String name, {BoxFit fit = BoxFit.cover}) {
    return PlaceImageHelper.buildPlaceImage(
      imagePath: url, 
      category: category, 
      name: name,
      fit: fit,
    );
  }



  Widget _buildNatureItem(AttractionEntity item, int index) {
    final dist = ((item.distanceM ?? 0) / 1000).toStringAsFixed(1);
    
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: item.id,
          name: item.name,
          category: item.categoryName ?? 'Nature',
          rating: item.rating,
          distance: '$dist km',
          emoji: '🍃',
          imageUrl: item.photoUrls.isNotEmpty ? item.photoUrls.first : null,
          latitude: item.latitude,
          longitude: item.longitude,
        )),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                 const SizedBox(width: 3),
                 Text('${item.rating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                 const SizedBox(width: 12),
                 Icon(Icons.near_me_rounded, size: 12, color: AppColors.primary),
                 const SizedBox(width: 4),
                 Text('$dist km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
               ],
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () async {
                await CacheService.toggleFavoritePlace((item as AttractionModel).toJson());
                setState(() {});
              },
              child: Icon(
                CacheService.isPlaceFavorite(item.id) ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                color: CacheService.isPlaceFavorite(item.id) ? AppColors.primary : AppColors.textTertiary,
                size: 20,
               ),
             ),
           ],
         ),
       ),
     );
   }
}
