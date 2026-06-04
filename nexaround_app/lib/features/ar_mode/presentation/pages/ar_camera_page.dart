import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:nexaround_app/core/services/google_directions_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/ai_companion/presentation/pages/ai_chat_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/smart_tourism_map_page.dart';
import 'package:nexaround_app/core/services/permission_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

class ArCameraPage extends StatefulWidget {
  final Map<String, dynamic>? initialPlace;
  // Whether the AR tab is currently the visible one. The home tabs are kept
  // alive in an IndexedStack, so without this the camera + compass + GPS would
  // run (and redraw) in the background even when you're on another tab. When
  // false, AR pauses all of that and resumes when you return.
  final bool isActive;
  const ArCameraPage({super.key, this.initialPlace, this.isActive = true});

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

  void updateState(VoidCallback fn) => setState(fn);

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<AttractionEntity> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  
  // Permission state
  bool _isLocationGranted = false;
  bool _isCameraGranted = false;
  bool _isCheckingPermissions = true;
  
  // Navigation State
  bool _isNavigating = false;
  _ArLandmark? _navigationTarget;
  double _distanceToTarget = 0.0;
  bool _isListening = false;

  // ═══════════════════════════════════════
  // ROUTE NAVIGATION — Turn-by-turn with chevrons
  // ═══════════════════════════════════════
  WalkingRoute? _walkingRoute;
  int _currentStepIndex = 0;
  bool _isFetchingRoute = false;
  bool _hasArrivedAtDestination = false;
  static const double _stepAdvanceThresholdM = 20.0; // Advance to next step within 20m

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
  String _currentLocationName = '';
  bool _isSilentCapturing = false; // Silent capture in progress (no UI feedback)
  bool _hasCapturedForCurrentTarget = false; // Prevent multiple captures for same place
  
  // Disable old discovery system when Neva is active
  bool get _isOldDiscoveryDisabled => _isNevaSearching || _nevaSearchResult != null;

  // Session cache of Neva place results, keyed by rounded lat/lng. Avoids
  // re-hitting Gemini when the user re-points at the same landmark. Capped to
  // avoid unbounded memory growth; cleared on app restart.
  static final Map<String, Map<String, dynamic>> _nevaPlaceCache = {};
  static const int _nevaCacheMaxEntries = 50;

  String _nevaCacheKey(_ArLandmark landmark) {
    final lat = landmark.lat?.toStringAsFixed(5) ?? '?';
    final lng = landmark.lng?.toStringAsFixed(5) ?? '?';
    return '${landmark.name}|$lat,$lng';
  }

  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<geo.Position>? _positionSubscription;
  double _heading = 0.0;
  double? _rawHeading; // last raw reading from sensor (pre-smoothing)
  double? _compassAccuracy; // 0..360°, lower = more reliable
  List<_ArLandmark> _landmarks = [];
  bool _isFetchingPlaces = false;
  DateTime? _lastFetchTime;
  // Distinguishes "still loading" from "finished and found nothing" so the UI
  // can stop showing "SCANNING…" forever when a fetch comes back empty.
  bool _hasCompletedInitialFetch = false;
  // Set when a live fetch threw (network / backend error) rather than simply
  // returning zero results. Drives the retry prompt instead of "no places".
  bool _placesFetchError = false;

  /// User's manual choice for the "Your Location" pill, overriding auto-pick.
  /// Cleared on every fresh place fetch so it doesn't stick after you walk
  /// somewhere new.
  String? _userPickedLocationName;

  // === AR camera geometry ===
  // Typical mobile back-camera horizontal FOV. Phones vary 60–75°; 65° is a
  // safe default that keeps the cone honest without missing nearby items.
  static const double _cameraFovDegrees = 65.0;
  // Hard cone used to decide whether a landmark is "in front of the camera".
  // Includes a small buffer so cards don't pop in/out at the FOV edge.
  static const double _viewConeHalfDegrees = (_cameraFovDegrees / 2) + 5;
  // Half-angle of the cone in which place cards are actually drawn. Matches the
  // camera field of view plus the same 8° edge buffer the projection uses, so
  // "a place has a visible card" and "a place is in front of the lens" mean the
  // same thing. Used to gate the turn/direction guide so it only appears when
  // nothing is visible in the camera frame.
  static const double _cardConeHalfDegrees = _viewConeHalfDegrees + 8;
  // The raw sensor reading is jittery; we low-pass filter it so cards don't
  // dance when the phone is "still". Higher = more responsive, lower = more
  // stable. 0.05 was far too low — it made the heading lag reality by several
  // seconds (places pointed the wrong way until it slowly caught up). 0.2 keeps
  // jitter down while tracking turns in a fraction of a second. The very first
  // reading is snapped directly (see compass listener) so AR opens aligned.
  static const double _headingSmoothing = 0.2;
  // The compass fires 20-50x/sec and jitters even when the phone is still.
  // Rebuilding the whole AR tree on every tick is wasteful, so we only rebuild
  // when the smoothed heading actually moved at least this many degrees (plus
  // the first reading / accuracy changes). Below this, the move is invisible.
  static const double _headingRebuildThresholdDegrees = 0.4;
  // If the OS reports compass accuracy worse than this, ignore the update.
  static const double _maxAcceptableAccuracyDegrees = 35.0;
  bool _minimalHud = false;
  bool _isCapturing = false;

  // ═══════════════════════════════════════
  // AR FILTER (category-based)
  // ═══════════════════════════════════════
  String _selectedFilter = 'All';
  // User-selectable search range (km). The slider snaps to [_rangeSteps]; both
  // the live fetch and the on-screen cull honor it so the user controls how far
  // out attractions / medical (and all categories) are shown.
  int _rangeKm = 10;
  static const List<int> _rangeSteps = [2, 5, 10];
  static const List<Map<String, dynamic>> _arFilters = [
    {'id': 'All', 'label': 'All', 'icon': Icons.public_rounded},
    {'id': 'Food', 'label': 'Food', 'icon': Icons.restaurant_rounded},
    {'id': 'Shopping', 'label': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {'id': 'Historical', 'label': 'Historical', 'icon': Icons.account_balance_rounded},
    {'id': 'Nature', 'label': 'Nature', 'icon': Icons.park_rounded},
    {'id': 'Hotels', 'label': 'Hotels', 'icon': Icons.hotel_rounded},
    {'id': 'Medical', 'label': 'Medical', 'icon': Icons.medical_services_rounded},
    {'id': 'Others', 'label': 'Others', 'icon': Icons.more_horiz_rounded},
  ];

  int _maxRangeForCategory(String filter) {
    if (filter == 'Medical' || filter == 'Nature' || filter == 'Historical') {
      return 50;
    }
    return 10;
  }

  List<int> _rangeStepsForCategory(String filter) {
    if (filter == 'Medical' || filter == 'Nature' || filter == 'Historical') {
      return const [2, 5, 10, 20, 50];
    }
    return const [2, 5, 10];
  }

  bool _matchesFilter(_ArLandmark lm, String filter) {
    if (filter == 'All') return true;
    final c = lm.category.toLowerCase();
    final nameLower = lm.name.toLowerCase();
    final tagsLower = lm.tags.map((t) => t.toLowerCase()).toList();

    bool isNature() {
      final natureKeywords = [
        'park', 'garden', 'beach', 'forest', 'lake', 'mountain', 'nature', 'zoo', 
        'reserve', 'river', 'waterfall', 'sea', 'ocean', 'natural_feature', 
        'campground', 'beach_resort', 'outdoor'
      ];
      
      // Check in category name
      if (natureKeywords.any((keyword) => c.contains(keyword))) return true;
      
      // Check in place name (beaches, parks etc)
      if (natureKeywords.any((keyword) => nameLower.contains(keyword))) return true;
      
      // Check in Google Place tags/types
      if (tagsLower.any((tag) => natureKeywords.any((keyword) => tag.contains(keyword)))) return true;
      
      return false;
    }

    switch (filter) {
      case 'Food':
        return c.contains('restaurant') || c.contains('food') || c.contains('cafe') ||
            c.contains('bar') || c.contains('bakery') || c.contains('meal') || c.contains('dining') ||
            tagsLower.any((tag) => tag.contains('restaurant') || tag.contains('food') || tag.contains('cafe') || tag.contains('bar') || tag.contains('bakery') || tag.contains('meal') || tag.contains('dining'));
      case 'Shopping':
        return c.contains('shop') || c.contains('store') || c.contains('mall') ||
            c.contains('market') || c.contains('retail') || c.contains('clothing') ||
            tagsLower.any((tag) => tag.contains('shopping') || tag.contains('store') || tag.contains('mall') || tag.contains('clothing') || tag.contains('supermarket'));
      case 'Historical':
        // `attraction` is deliberate: the curated DB and the backend both file
        // every heritage landmark (temples, forts, museums) under the broad
        // category_name "Attractions" — there is no dedicated "Historical"
        // category. Matching it on the category (not the raw `tourist_attraction`
        // tag) keeps shopping malls Google sometimes tags as attractions out of
        // this bucket. This is what makes the Historical filter actually
        // populate instead of dropping every landmark into Others.
        return c.contains('museum') || c.contains('temple') || c.contains('church') ||
            c.contains('monument') || c.contains('historic') || c.contains('heritage') ||
            c.contains('mosque') || c.contains('shrine') || c.contains('castle') ||
            c.contains('landmark') || c.contains('tourist') || c.contains('attraction') ||
            tagsLower.any((tag) => tag.contains('museum') || tag.contains('place_of_worship') || tag.contains('church') || tag.contains('hindu_temple') || tag.contains('mosque') || tag.contains('synagogue') || tag.contains('monument'));
      case 'Nature':
        return isNature();
      case 'Hotels':
        return c.contains('hotel') || c.contains('lodging') || c.contains('motel') ||
            c.contains('resort') || c.contains('guest') || c.contains('hostel') ||
            tagsLower.any((tag) => tag.contains('lodging') || tag.contains('hotel') || tag.contains('resort') || tag.contains('motel') || tag.contains('hostel') || tag.contains('campground'));
      case 'Medical':
        return c.contains('medical') || c.contains('hospital') || c.contains('pharmacy') ||
            c.contains('doctor') || c.contains('clinic') || c.contains('dentist') ||
            c.contains('care') || c.contains('health') ||
            tagsLower.any((tag) => tag.contains('medical') || tag.contains('hospital') || tag.contains('pharmacy') || tag.contains('doctor') || tag.contains('clinic') || tag.contains('dentist') || tag.contains('health'));
      case 'Others':
        return !_matchesFilter(lm, 'Food') &&
            !_matchesFilter(lm, 'Shopping') &&
            !_matchesFilter(lm, 'Historical') &&
            !_matchesFilter(lm, 'Nature') &&
            !_matchesFilter(lm, 'Hotels') &&
            !_matchesFilter(lm, 'Medical');
    }
    return false;
  }

  // ── Category display policy (client rules) ──────────────────────────
  //  • No fixed "max per category" — proximity alone decides how many show.
  //  • Normal categories (food, hotels, others) show ONLY when extremely
  //    close (within [_extremelyCloseM]). This keeps the list short without
  //    an arbitrary count cap.
  //  • LONG-RANGE categories — attractions, hospitals, beaches, shopping —
  //    may show at any distance (their numbers are already limited when
  //    fetched).
  static const double _extremelyCloseM = 300;

  // Buckets allowed to appear at long range. In this app the backend maps
  // "Medical" → Google `hospital` and "Beach" → `beach`. Shopping is included
  // because malls/markets/supermarkets are destinations people travel to, and
  // they're almost always farther than [_extremelyCloseM]: capping them to 300m
  // left the Shopping filter showing only the rotate/nav hint with no place
  // labels (client report), since matched shops got stripped by proximity.
  static const Set<String> _longRangeKeys = {'hospital', 'beach', 'historical', 'shopping'};

  // ── Real Google Place-type sets (New Places API) ────────────────────
  // Classification keys off the place's ACTUAL types (lm.tags), NOT its
  // category name. The category name is only the *query bucket* the place was
  // fetched under, so it describes the search, not the place — a university
  // with a campus cafe was being stamped "Food & Drink" and leaking into the
  // Food filter (tester report: "Food shows a college"). Matching real types
  // and routing institutional/service places to Others fixes that.
  static const Set<String> _medicalTypes = {
    'hospital', 'pharmacy', 'drugstore', 'doctor', 'dentist',
    'physiotherapist', 'medical_lab', 'dental_clinic', 'wellness_center',
  };
  static const Set<String> _natureTypes = {
    'beach', 'park', 'national_park', 'state_park', 'garden',
    'botanical_garden', 'campground', 'hiking_area', 'natural_feature',
    'wildlife_park', 'wildlife_refuge', 'zoo', 'dog_park', 'picnic_ground',
  };
  static const Set<String> _historicalTypes = {
    'tourist_attraction', 'museum', 'art_gallery', 'historical_landmark',
    'historical_place', 'monument', 'cultural_landmark', 'hindu_temple',
    'church', 'mosque', 'synagogue', 'temple', 'shrine', 'castle', 'fort',
    'place_of_worship', 'amusement_park', 'aquarium', 'cultural_center',
  };
  static const Set<String> _foodTypes = {
    'restaurant', 'cafe', 'coffee_shop', 'bar', 'bakery', 'meal_takeaway',
    'meal_delivery', 'fast_food_restaurant', 'ice_cream_shop', 'food_court',
    'food', 'pub', 'wine_bar', 'bar_and_grill', 'breakfast_restaurant',
    'brunch_restaurant',
  };
  static const Set<String> _shoppingTypes = {
    'shopping_mall', 'department_store', 'clothing_store', 'supermarket',
    'grocery_store', 'convenience_store', 'market', 'shoe_store',
    'jewelry_store', 'electronics_store', 'book_store', 'furniture_store',
    'hardware_store', 'gift_shop', 'shopping_center', 'store',
  };
  static const Set<String> _hotelTypes = {
    'lodging', 'hotel', 'motel', 'resort_hotel', 'guest_house', 'hostel',
    'bed_and_breakfast', 'inn', 'extended_stay_hotel',
  };
  // Institutional / service / transport — never a sightseeing category. These
  // are routed to Others BEFORE food/shopping/hotel so a place that is really
  // a school / bank / office / fuel station can't leak into a tourist filter
  // just because Google also tagged an ancillary cafe or shop on it.
  static const Set<String> _excludedTypes = {
    'school', 'primary_school', 'secondary_school', 'university', 'college',
    'preschool', 'child_care_agency', 'tutoring_service',
    'government_office', 'local_government_office', 'city_hall', 'courthouse',
    'embassy', 'fire_station', 'police', 'post_office',
    'bank', 'atm', 'finance', 'accounting', 'insurance_agency',
    'real_estate_agency', 'lawyer', 'corporate_office', 'office',
    'gas_station', 'car_repair', 'car_dealer', 'car_rental', 'car_wash',
    'parking', 'electrician', 'plumber', 'moving_company', 'storage',
    'funeral_home', 'cemetery', 'telecommunications_service_provider',
    'transit_station', 'bus_station', 'train_station', 'subway_station',
    'light_rail_station', 'airport', 'taxi_stand',
  };

  bool _isFoodType(String t) => _foodTypes.contains(t) || t.endsWith('_restaurant');
  bool _isShoppingType(String t) => _shoppingTypes.contains(t) || t.endsWith('_store');

  /// Bucket a landmark into a single display category using its REAL Google
  /// types first. A place only lands in a tourist bucket when its actual type
  /// fits; otherwise it falls through to Others — so categories stay clean
  /// (no colleges under Food, no banks under Historical, etc.).
  String _displayCategoryKey(_ArLandmark lm) {
    final types = lm.tags.map((t) => t.toLowerCase().trim()).toSet()
      ..removeWhere((t) => t.isEmpty);

    // No real types (curated DB / older cache entries) → fall back to the
    // legacy category-name keyword match so those still bucket sensibly.
    if (types.isEmpty) return _legacyCategoryKey(lm);

    bool hasAny(Set<String> s) => types.any((t) => s.contains(t));

    // Medical wins outright (safety category, unambiguous types).
    if (hasAny(_medicalTypes)) return 'hospital';
    // Strong sightseeing / nature signals beat everything non-medical.
    if (hasAny(_natureTypes)) return 'beach';
    if (hasAny(_historicalTypes)) return 'historical';
    // Institutional / service / transport → Others, BEFORE food/shopping/hotel
    // so a college-with-a-cafe or a fuel-station-with-a-shop can't slip in.
    if (hasAny(_excludedTypes)) return 'others';
    if (types.any(_isFoodType)) return 'food';
    if (types.any(_isShoppingType)) return 'shopping';
    if (hasAny(_hotelTypes)) return 'hotel';
    return 'others';
  }

  /// Fallback bucketing for places with no Google types (curated DB / cache),
  /// using the category-name keyword match. Mirrors the type-based priority.
  String _legacyCategoryKey(_ArLandmark lm) {
    if (_matchesFilter(lm, 'Medical')) return 'hospital';
    if (_matchesFilter(lm, 'Nature')) return 'beach';
    if (_matchesFilter(lm, 'Historical')) return 'historical';
    if (_matchesFilter(lm, 'Food')) return 'food';
    if (_matchesFilter(lm, 'Shopping')) return 'shopping';
    if (_matchesFilter(lm, 'Hotels')) return 'hotel';
    return 'others';
  }

  /// Keep a landmark only if it is extremely close, OR it belongs to a
  /// long-range category (attraction / hospital / beach) that is allowed at
  /// any distance. No count cap — proximity does the limiting.
  List<_ArLandmark> _filterByProximity(List<_ArLandmark> sortedByDistance) {
    final result = <_ArLandmark>[];
    for (final lm in sortedByDistance) {
      final key = _displayCategoryKey(lm);
      if (_longRangeKeys.contains(key) || lm.distanceM <= _extremelyCloseM) {
        result.add(lm);
      }
    }
    return result;
  }

  // Memoize the filtered lists per filter. The result only depends on
  // [_landmarks] and the proximity rule, NOT on heading — yet build() runs on
  // every compass tick. Caching against the current landmark snapshot keeps
  // those frequent rebuilds (and the 8 filter chips that each call this) cheap.
  List<_ArLandmark>? _capCacheSource;
  int _capCacheLen = -1;
  final Map<String, List<_ArLandmark>> _capCache = {};

  // Maps an AR filter id to the single display bucket a place must resolve to
  // before it shows under that filter. Filtering on the *primary* bucket (from
  // [_displayCategoryKey]) instead of a loose keyword match makes the categories
  // mutually exclusive: Google tags supermarkets, grocery stores and food courts
  // with a generic `store`/`supermarket` type, which used to leak them into
  // Shopping even though they're really Food. Now each place lands in exactly one
  // bucket (priority order: Medical → Nature → Historical → Food → Shopping →
  // Hotels → others), so a food place can never appear under Shopping. 'All' is
  // intentionally absent — it bypasses this and shows every bucket.
  static const Map<String, String> _filterBucketKey = {
    'Food': 'food',
    'Shopping': 'shopping',
    'Historical': 'historical',
    'Nature': 'beach',
    'Hotels': 'hotel',
    'Medical': 'hospital',
    'Others': 'others',
  };

  /// Places to display for [filter] — exclusive bucket match, closest-first, then
  /// the proximity rule (extremely-close normals + any-distance long-range ones).
  List<_ArLandmark> _placesForFilter(String filter) {
    if (!identical(_capCacheSource, _landmarks) || _capCacheLen != _landmarks.length) {
      _capCache.clear();
      _capCacheSource = _landmarks;
      _capCacheLen = _landmarks.length;
    }
    final cached = _capCache[filter];
    if (cached != null) return cached;

    final bucket = _filterBucketKey[filter];
    final double maxRangeM = (_rangeKm * 1000).toDouble();
    final matches = _landmarks
        .where((lm) =>
            lm.distanceM <= maxRangeM &&
            (filter == 'All' || _displayCategoryKey(lm) == bucket))
        .toList()
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final result = _filterByProximity(matches);
    _capCache[filter] = result;
    return result;
  }

  List<_ArLandmark> get _filteredLandmarks => _placesForFilter(_selectedFilter);

  /// Landmarks the camera is currently pointed at, ordered by how centred
  /// they are in the view (most-centred first). Used to pick the focused
  /// place and to decide whether to show the "rotate to discover" prompt.
  List<_ArLandmark> get _landmarksInView {
    final inView = <MapEntry<_ArLandmark, double>>[];
    for (final lm in _filteredLandmarks) {
      final angle = _signedAngleDelta(_heading, lm.bearing);
      if (angle.abs() <= _viewConeHalfDegrees) {
        inView.add(MapEntry(lm, angle.abs()));
      }
    }
    inView.sort((a, b) => a.value.compareTo(b.value));
    return inView.map((e) => e.key).toList();
  }

  /// True when at least one place sits inside the on-screen card cone
  /// (~±[_cardConeHalfDegrees]° of the camera heading) — i.e. the user can
  /// already see place cards laid out in front of them. Bearing is computed
  /// exactly like [_buildOtherPlaceDots] so the two never disagree.
  bool get _hasLandmarkInForwardView {
    for (final lm in _filteredLandmarks) {
      final double liveBearing =
          (_currentPosition != null && lm.lat != null && lm.lng != null)
              ? _calculateBearing(_currentPosition!.latitude,
                  _currentPosition!.longitude, lm.lat!, lm.lng!)
              : lm.bearing;
      if (_signedAngleDelta(_heading, liveBearing).abs() <= _cardConeHalfDegrees) {
        return true;
      }
    }
    return false;
  }

  /// The nearest landmark by angle that is NOT in view — used to hint the
  /// user which way to rotate when nothing is visible.
  _ArLandmark? get _nearestOffScreenLandmark {
    _ArLandmark? closest;
    double? bestAngle;
    for (final lm in _filteredLandmarks) {
      final angle = _signedAngleDelta(_heading, lm.bearing).abs();
      if (angle <= _viewConeHalfDegrees) continue; // already in view
      if (bestAngle == null || angle < bestAngle) {
        bestAngle = angle;
        closest = lm;
      }
    }
    return closest;
  }

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
    _checkAndInit();
  }

  Future<void> _checkAndInit() async {
    // Actually check and request permissions (critical for iOS)
    final cameraOk = await PermissionService.isCameraGranted();
    final locationOk = await PermissionService.isLocationGranted();

    if (mounted) {
      setState(() {
        _isCameraGranted = cameraOk;
        _isLocationGranted = locationOk;
        _isCheckingPermissions = false;
      });
    }

    // Request permissions if not granted yet
    if (!cameraOk) {
      final granted = await PermissionService.requestCameraPermission();
      if (mounted) setState(() => _isCameraGranted = granted);
    }
    if (!locationOk) {
      final granted = await PermissionService.requestLocationPermission();
      if (mounted) setState(() => _isLocationGranted = granted);
    }

    _loadCachedPlaces();
    if (widget.isActive) _startArCapture();

    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted || !widget.isActive) return;
      final raw = event.heading;
      if (raw == null || raw.isNaN) return;

      final bool firstReading = _rawHeading == null;
      // First valid reading: snap straight to it so the AR view opens aligned
      // with reality instead of slewing all the way from north (0°) over
      // several seconds, which made every place point the wrong way at first.
      final double newHeading = firstReading
          ? raw
          : _smoothHeading(_heading, raw, _headingSmoothing);

      _rawHeading = raw;
      final double? prevAccuracy = _compassAccuracy;
      _compassAccuracy = event.accuracy;

      // Throttle: skip the (expensive) full rebuild when the heading barely
      // moved. The compass jitters constantly while stationary, so without this
      // the whole AR tree redraws 20-50x/sec for no visible change.
      double delta = (newHeading - _heading).abs();
      if (delta > 180) delta = 360 - delta; // shortest angle across 0°/360°
      final bool accuracyChanged = (prevAccuracy ?? -1) != (_compassAccuracy ?? -1);
      if (!firstReading && delta < _headingRebuildThresholdDegrees && !accuracyChanged) {
        return; // value already stored above; no rebuild needed
      }
      setState(() => _heading = newHeading);
    });

    _positionSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted || !widget.isActive) return;
      debugPrint('📍 AR Location Update: ${pos.latitude}, ${pos.longitude}');
      setState(() {
        _currentPosition = pos;
        
        // Update distances for all landmarks dynamically as the user moves
        _landmarks = _landmarks.map((lm) {
          if (lm.lat == null || lm.lng == null) return lm;
          
          final double rawDistM = geo.Geolocator.distanceBetween(
            pos.latitude, pos.longitude, lm.lat!, lm.lng!
          );
          final bearing = _calculateBearing(pos.latitude, pos.longitude, lm.lat!, lm.lng!);
          
          final distKm = rawDistM / 1000;
          final distStr = distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';
          
          return lm.copyWith(
            distance: distStr,
            distanceM: rawDistM,
            bearing: bearing,
          );
        }).toList();

        // If navigating, also update the navigation target explicitly
        if (_isNavigating && _navigationTarget != null) {
          final target = _navigationTarget!;
          if (target.lat != null && target.lng != null) {
            final double distM = geo.Geolocator.distanceBetween(
              pos.latitude, pos.longitude, target.lat!, target.lng!
            );
            final bearing = _calculateBearing(pos.latitude, pos.longitude, target.lat!, target.lng!);
            
            final distKm = distM / 1000;
            final distStr = distKm < 1 ? '${distM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';
            
            _navigationTarget = target.copyWith(
              distance: distStr,
              distanceM: distM,
              bearing: bearing,
            );
            _distanceToTarget = distM;

            // Straight-line arrival fallback: if within 2m, trigger arrival
            if (distM <= 2.0 && !_hasArrivedAtDestination) {
              setState(() => _hasArrivedAtDestination = true);
              HapticFeedback.vibrate();
              debugPrint('🏁 ARRIVED at ${_navigationTarget?.name} (straight-line within 2m)!');
            }
          }

          // Advance route steps based on GPS proximity
          _checkRouteStepAdvancement(pos);
        }
      });
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

  // Live places are fetched once, lazily, the first time AR becomes visible.
  bool _placesFetched = false;

  /// Called when the AR tab becomes visible: (re)start the camera and load
  /// places. The compass/GPS callbacks gate on [widget.isActive] themselves, so
  /// they resume doing work automatically.
  void _startArCapture() {
    if (_controller == null) {
      _initializeCamera();
    } else {
      try { _controller!.resumePreview(); } catch (_) {}
    }
    if (!_placesFetched) {
      _placesFetched = true;
      _fetchLivePlaces();
    }
  }

  /// Called when the AR tab is hidden: freeze the camera preview and clear the
  /// heading so it re-snaps on return. The compass/GPS callbacks early-return
  /// while hidden, so the heavy AR tree stops rebuilding in the background.
  void _stopArCapture() {
    _rawHeading = null;
    try { _controller?.pausePreview(); } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ArCameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _startArCapture();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopArCapture();
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    _controller?.dispose();
    _newPlaceController.dispose();
    _newPlaceDescriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // ROUTE NAVIGATION — Fetch directions + start turn-by-turn
  // ═══════════════════════════════════════════════════════════
  Future<void> _performArSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });
    try {
      final results = await GooglePlacesService.searchPlaces(
        query: query,
        latitude: _currentPosition?.latitude ?? 6.9271,
        longitude: _currentPosition?.longitude ?? 79.8612,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('AR Search error: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _startRouteNavigation(_ArLandmark landmark) {
    setState(() {
      _navigationTarget = landmark;
      _isNavigating = true;
      _showInfoCard = false;
      _arMode = 'navigate';
      _isFetchingRoute = true;
      _walkingRoute = null;
      _currentStepIndex = 0;
      _hasArrivedAtDestination = false;
    });

    // Fetch walking route in background
    _fetchWalkingRoute(landmark);
  }

  Future<void> _fetchWalkingRoute(_ArLandmark landmark) async {
    if (_currentPosition == null || landmark.lat == null || landmark.lng == null) {
      if (mounted) setState(() => _isFetchingRoute = false);
      return;
    }

    final route = await GoogleDirectionsService.getWalkingRoute(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: landmark.lat!,
      destLng: landmark.lng!,
    );

    if (mounted) {
      setState(() {
        _walkingRoute = route;
        _currentStepIndex = 0;
        _isFetchingRoute = false;
      });
      if (route != null) {
        debugPrint('✅ Route loaded: ${route.steps.length} steps, ${route.totalDistance}');
        HapticFeedback.mediumImpact();
      } else {
        debugPrint('⚠️ No route found — falling back to compass-only navigation');
      }
    }
  }

  /// Advance to the next route step if the user is close enough to the
  /// current step’s endpoint. Called from the GPS position listener.
  void _checkRouteStepAdvancement(geo.Position pos) {
    if (_walkingRoute == null || _hasArrivedAtDestination) return;

    final steps = _walkingRoute!.steps;
    if (_currentStepIndex >= steps.length) return;

    final currentStep = steps[_currentStepIndex];
    final distToStepEnd = geo.Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      currentStep.endLat, currentStep.endLng,
    );

    final isLastStep = _currentStepIndex == steps.length - 1;
    // Standard steps advance at 15m, final step (arrival) triggers strictly at 2m
    final threshold = isLastStep ? 2.0 : 15.0;

    if (distToStepEnd <= threshold) {
      if (!isLastStep) {
        // Advance to next step
        setState(() => _currentStepIndex++);
        HapticFeedback.heavyImpact();
        debugPrint('➡️ Step ${_currentStepIndex}/${steps.length}: ${steps[_currentStepIndex].instruction}');
      } else {
        // Arrived at destination!
        setState(() => _hasArrivedAtDestination = true);
        HapticFeedback.vibrate();
        debugPrint('🏁 ARRIVED at ${_navigationTarget?.name}!');
      }
    }
  }

  /// The bearing the user should currently face. When we have a walking
  /// route, this is the bearing of the active step. Otherwise it falls back
  /// to the straight-line bearing to the target.
  double get _activeNavBearing {
    if (_walkingRoute != null && _currentStepIndex < _walkingRoute!.steps.length) {
      return _walkingRoute!.steps[_currentStepIndex].bearing;
    }
    return _navigationTarget?.bearing ?? _heading;
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

  /// Signed angular distance from [heading] to [bearing] in degrees,
  /// normalised to (-180, 180]. Positive = target is clockwise (right) of
  /// where the camera is pointing.
  static double _signedAngleDelta(double heading, double bearing) {
    double d = (bearing - heading) % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }

  /// Low-pass filter for the compass heading. Handles the wrap-around between
  /// 359° and 0° so a tiny rotation across north doesn't snap the smoothed
  /// value all the way back around the circle.
  static double _smoothHeading(double previous, double next, double alpha) {
    double delta = _signedAngleDelta(previous, next);
    double updated = previous + delta * alpha;
    if (updated < 0) updated += 360;
    if (updated >= 360) updated -= 360;
    return updated;
  }

  /// Returns the on-screen horizontal position (0..1) for a landmark whose
  /// bearing is [angle] degrees off camera centre, using a perspective
  /// projection so items track real-world position instead of stretching
  /// linearly. Returns null when the landmark is outside the view cone.
  static double? _projectAngleToScreenX(double angle, {double bufferDegrees = 8}) {
    final half = _viewConeHalfDegrees + bufferDegrees;
    if (angle.abs() > half) return null;
    final halfFovRad = (_cameraFovDegrees / 2) * pi / 180;
    final angleRad = angle * pi / 180;
    // tan(angle)/tan(halfFov) maps angle linearly across the screen *in
    // perspective space*, which matches what the camera lens actually shows.
    final t = tan(angleRad) / tan(halfFovRad);
    return (0.5 + t * 0.5).clamp(-0.15, 1.15);
  }

  Future<void> _initializeCamera() async {
    // On iOS, camera permission MUST be granted before accessing the camera.
    // Unlike Android, iOS won't show a permission dialog when the camera opens.
    if (!_isCameraGranted) {
      final granted = await PermissionService.requestCameraPermission();
      if (!granted) {
        debugPrint('📷 Camera permission not granted — cannot initialize camera');
        if (mounted) setState(() => _isCameraGranted = false);
        return;
      }
      if (mounted) setState(() => _isCameraGranted = true);
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _isCameraGranted = true;
        });
      }
    } catch (e) {
      debugPrint('Camera Error: $e');
      if (mounted) setState(() => _isCameraGranted = false);
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
              // Do NOT auto-open info card — user taps to open it
              
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

  static const int _maxVisibleMarkers = 60;
  // How many place cards are drawn on screen at once. Kept low so the vertically
  // stacked cards (see [_buildLandmarkMarker]) never overlap each other — the
  // most-centred places win the visible slots.
  static const int _maxVisibleOnScreen = 5;
  // Search radii, widest-first fallback. Start at 1 km — that single tier already
  // covers the close places too, so we skip the old 100/200/500 m micro-tiers and
  // their extra API calls. We only expand to 2/5/10 km when 1 km comes back too
  // sparse (see the early-break on [_minPlacesBeforeStop] in the fetch loop).
  static const List<int> _searchRadii = [1000, 2000, 5000, 10000];
  // Once a radius tier has collected at least this many places, stop widening.
  static const int _minPlacesBeforeStop = 12;

  void _loadCachedPlaces({geo.Position? position}) {
    try {
      final cachedJson = CacheService.getCachedAttractions();
      if (cachedJson.isNotEmpty) {
        final pos = position ?? _currentPosition;
        if (pos == null) {
          // Without location, we can't filter cached places by distance.
          // Do not load to avoid showing unrelated places from other countries.
          return;
        }
        final double currentLat = pos.latitude;
        final double currentLng = pos.longitude;

        final List<_ArLandmark> cachedLandmarks = [];
        for (final jsonMap in cachedJson) {
          final lat = (jsonMap['latitude'] as num?)?.toDouble();
          final lng = (jsonMap['longitude'] as num?)?.toDouble();
          
          if (lat != null && lng != null) {
            final distanceM = geo.Geolocator.distanceBetween(currentLat, currentLng, lat, lng);
            // Only keep cached places within the user-selected range.
            if (distanceM > _rangeKm * 1000) continue;

            final name = jsonMap['name'] as String? ?? 'Discovery';
            final categoryName = jsonMap['category_name'] as String? ?? 'Attraction';
            final rating = (jsonMap['rating'] as num?)?.toDouble() ?? 0.0;
            final description = jsonMap['description'] as String? ?? '';
            final photoUrls = jsonMap['photo_urls'] as List? ?? [];
            final tags = (jsonMap['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

            final photoUrl = photoUrls.isNotEmpty 
                ? photoUrls.first 
                : (categoryName == 'Nature' 
                    ? 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop' 
                    : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop');

            final bearing = _calculateBearing(currentLat, currentLng, lat, lng);
            final distKm = distanceM / 1000;
            final distStr = distKm < 1 ? '${distanceM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';

            cachedLandmarks.add(_ArLandmark(
              name,
              photoUrl,
              rating,
              distStr,
              bearing,
              description,
              categoryName.toUpperCase(),
              distanceM,
              lat,
              lng,
              tags,
            ));
          }
        }

        // Sort by distance
        cachedLandmarks.sort((a, b) => a.distanceM.compareTo(b.distanceM));

        setState(() {
          _landmarks = cachedLandmarks;
          if (_currentPosition == null) {
            _currentPosition = pos;
          }
        });
        debugPrint('📦 AR: Loaded ${_landmarks.length} places from cache within 10km.');
      }
    } catch (e) {
      debugPrint('Error loading cached places in AR: $e');
    }
  }

  Future<void> _fetchLivePlaces() async {
    if (!_isLocationGranted) {
      // No location → we can't search. Stop the "scanning" spinner so the UI
      // can prompt for permission instead of hanging forever.
      if (mounted) {
        setState(() {
          _hasCompletedInitialFetch = true;
          _placesFetchError = false;
        });
      }
      return;
    }
    if (_isFetchingPlaces) {
      debugPrint('🔍 AR: Fetch already in progress, ignoring duplicate call.');
      return;
    }
    final now = DateTime.now();
    if (_lastFetchTime != null && now.difference(_lastFetchTime!) < const Duration(seconds: 15)) {
      debugPrint('🔍 AR: Fetch throttled (cooldown active), ignoring call.');
      return;
    }
    _isFetchingPlaces = true;
    _lastFetchTime = now;

    try {
      final pos = await PermissionService.getSafePosition();
      if (pos == null) return;
      
      // Load relevant cached places immediately to show them first
      if (_landmarks.isEmpty) {
        _loadCachedPlaces(position: pos);
      }
      
      List<_ArLandmark> collected = [];
      List<AttractionEntity> allPlaces = []; // to save to cache later
      // True if any category call failed with a real error (vs. empty result).
      // Lets the empty-state UI say "couldn't load / retry" instead of "none".
      bool fetchHadError = false;

      final categoriesToFetch = [
        null,
        'Food & Drink',
        'Shopping',
        'Attractions',
        'Hotels',
        'Medical',
      ];

      // Honor the user-selected range: build the radius tiers up to _rangeKm.
      final int maxRangeM = _rangeKm * 1000;
      final List<int> activeRadii = [
        ..._searchRadii.where((r) => r < maxRangeM),
        maxRangeM,
      ];

      for (final radius in activeRadii) {
        // Capping categories: only Attractions (Historical) and Medical can go beyond 10km (10000m).
        // Food, Shopping, Hotels, and 'null' (All) are capped at 10km.
        final currentCategories = categoriesToFetch.where((cat) {
          if (radius > 10000) {
            return cat == 'Attractions' || cat == 'Medical';
          }
          return true;
        }).toList();

        if (currentCategories.isEmpty) continue;

        debugPrint('🔍 AR: Searching radius $radius m across categories: $currentCategories...');
        
        final List<List<dynamic>> results = await Future.wait(
          currentCategories.map((cat) => GooglePlacesService.fetchNearbyPlaces(
            latitude: pos.latitude,
            longitude: pos.longitude,
            radius: radius,
            categoryName: cat,
          ).catchError((err) {
            debugPrint('Error fetching category $cat: $err');
            if (err is PlacesFetchException) fetchHadError = true;
            return <dynamic>[];
          }))
        );

        final places = results.expand((x) => x).toList();

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
            p.photoUrls.isNotEmpty 
                ? p.photoUrls.first 
                : (p.categoryName == 'Nature' 
                    ? 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop' 
                    : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop'),
            p.rating,
            distStr,
            bearing,
            p.description ?? 'A remarkable location nearby!',
            p.categoryName?.toUpperCase() ?? 'ATTRACTION',
            rawDistM,
            p.latitude,
            p.longitude,
            p.tags,
          ));
          allPlaces.add(p);
        }

        debugPrint('📍 AR: ${collected.length} places so far at $radius m tier.');
        // 1 km first; only widen to the next tier when this one came back sparse.
        if (collected.length >= _minPlacesBeforeStop) {
          debugPrint('📍 AR: Found ${collected.length} places (>= $_minPlacesBeforeStop) at $radius m. Stopping radius expansion to save API cost.');
          break;
        }
      }

      // Dedicated Beach Query up to the selected range specifically
      try {
        debugPrint('🏖 AR: Querying Beaches up to ${_rangeKm}km specifically...');
        final beachPlaces = await GooglePlacesService.fetchNearbyPlaces(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radius: maxRangeM,
          categoryName: 'Beach',
        );

        for (final p in beachPlaces) {
          if (collected.any((l) => l.name == p.name)) continue;

          final rawDistM = (p.distanceM ?? 0).toDouble();
          if (rawDistM > maxRangeM) continue; // within the selected range
          final bearing = _calculateBearing(pos.latitude, pos.longitude, p.latitude, p.longitude);
          final distKm = rawDistM / 1000;
          final distStr = distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';

          // Nature default stunning beach photo
          final defaultPhoto = 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop';
          final photoUrl = p.photoUrls.isNotEmpty ? p.photoUrls.first : defaultPhoto;

          collected.add(_ArLandmark(
            p.name,
            photoUrl,
            p.rating,
            distStr,
            bearing,
            p.description ?? 'A beautiful sandy beach.',
            'NATURE',
            rawDistM,
            p.latitude,
            p.longitude,
            p.tags,
          ));
          allPlaces.add(p);
        }
      } catch (e) {
        debugPrint('AR dedicated Beach fetch failed: $e');
      }

      // Dedicated LONG-RANGE query (up to the selected range): per the client
      // rule, attractions and hospitals are worth surfacing from far away. The
      // tier loop above can stop early in dense areas, so this guarantees a
      // far-but-notable attraction/hospital still shows. Display caps trim rest.
      const longRangeQueries = [
        {'category': 'Attractions', 'label': 'ATTRACTION', 'max': 5},
        {'category': 'Medical', 'label': 'MEDICAL', 'max': 3},
      ];
      for (final q in longRangeQueries) {
        try {
          final cat = q['category'] as String;
          final maxAdd = q['max'] as int;
          debugPrint('🛰 AR: Long-range query for $cat up to ${_rangeKm}km...');
          final farPlaces = await GooglePlacesService.fetchNearbyPlaces(
            latitude: pos.latitude,
            longitude: pos.longitude,
            radius: maxRangeM,
            categoryName: cat,
          );

          final candidates = farPlaces
              .where((p) => (p.distanceM ?? 0) <= maxRangeM)
              .where((p) => !collected.any((l) => l.name == p.name))
              .toList()
            ..sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

          for (final p in candidates.take(maxAdd)) {
            final rawDistM = (p.distanceM ?? 0).toDouble();
            final bearing = _calculateBearing(pos.latitude, pos.longitude, p.latitude, p.longitude);
            final distKm = rawDistM / 1000;
            final distStr = distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';

            collected.add(_ArLandmark(
              p.name,
              p.photoUrls.isNotEmpty
                  ? p.photoUrls.first
                  : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop',
              p.rating,
              distStr,
              bearing,
              p.description ?? 'A notable place worth the trip.',
              p.categoryName?.toUpperCase() ?? (q['label'] as String),
              rawDistM,
              p.latitude,
              p.longitude,
              p.tags,
            ));
            allPlaces.add(p);
          }
        } catch (e) {
          debugPrint('AR long-range fetch failed for ${q['category']}: $e');
        }
      }

      if (collected.isNotEmpty) {
        // Separate beaches and non-beaches to ensure beaches are never truncated
        final beaches = collected.where((l) => 
          l.category == 'NATURE' || 
          l.name.toLowerCase().contains('beach') || 
          l.tags.contains('beach')
        ).toList();
        
        // Sort beaches by distance first (closest first)
        beaches.sort((a, b) => a.distanceM.compareTo(b.distanceM));

        // Filter beaches so we only keep one beach per direction (e.g. 30 degrees bearing difference)
        final List<_ArLandmark> uniqueDirectionBeaches = [];
        for (final beach in beaches) {
          bool hasBeachInDirection = false;
          for (final addedBeach in uniqueDirectionBeaches) {
            final diff = _signedAngleDelta(beach.bearing, addedBeach.bearing).abs();
            if (diff < 30.0) {
              hasBeachInDirection = true;
              break;
            }
          }
          if (!hasBeachInDirection) {
            uniqueDirectionBeaches.add(beach);
          }
        }
        
        final nonBeaches = collected.where((l) => !beaches.any((b) => b.name == l.name)).toList();
        
        // Sort non-beaches by distance and truncate
        nonBeaches.sort((a, b) => a.distanceM.compareTo(b.distanceM));
        
        final maxNonBeaches = _maxVisibleMarkers - uniqueDirectionBeaches.length;
        final truncatedNonBeaches = nonBeaches.take(maxNonBeaches > 40 ? maxNonBeaches : 40).toList();
        
        // Combine them and sort the final list by distance
        final finalCollected = [...truncatedNonBeaches, ...uniqueDirectionBeaches];
        finalCollected.sort((a, b) => a.distanceM.compareTo(b.distanceM));
        
        collected = finalCollected;

        if (mounted) {
          setState(() {
            _landmarks = collected;
            _currentPosition = pos;
            _placesFetchError = false;
            // Fresh fetch means user likely moved; drop any manual override so
            // the smart picker is in charge again.
            _userPickedLocationName = null;
          });
        }

        // Cache the newly fetched places to the persistent cache so other screens can use them
        try {
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
            'rating': p.rating,
            'review_count': p.reviewCount,
            'photo_urls': p.photoUrls,
            'tags': p.tags,
            'distance_m': p.distanceM,
            'created_at': p.createdAt.toIso8601String(),
          }).toList();
          CacheService.cacheAttractions(attractionJsons);
        } catch (e) {
          debugPrint('AR: Failed to cache fetched places: $e');
        }
      } else {
        // If collected is empty (e.g. timeout or no result), keep the old landmarks (cached or from last load)
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            // No results: distinguish a real failure (all calls errored) from a
            // genuinely empty area, so the UI shows the right message.
            _placesFetchError = fetchHadError;
          });
        }
      }

      // Resolve a friendly name for the "Your Location" pill.
      _resolveCurrentLocationName(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('AR places error: $e');
      // Surface the failure to the UI so the user gets a retry prompt instead
      // of an endless "SCANNING…" spinner.
      if (mounted) setState(() => _placesFetchError = true);
    } finally {
      _isFetchingPlaces = false;
      // First fetch has now finished (success, empty, or error) — let the UI
      // switch away from the initial scanning state.
      if (mounted) setState(() => _hasCompletedInitialFetch = true);
    }
  }

  /// User-initiated retry from the AR overlay. Re-checks location permission,
  /// clears the throttle so the fetch isn't skipped, and tries again.
  Future<void> _retryFetchPlaces() async {
    if (_isFetchingPlaces) return;
    // Re-check permission in case the user just granted it from settings.
    if (!_isLocationGranted) {
      final granted = await PermissionService.requestLocationPermission();
      if (mounted) setState(() => _isLocationGranted = granted);
    }
    if (mounted) {
      setState(() {
        _placesFetchError = false;
        _hasCompletedInitialFetch = false; // show "scanning" again while retrying
      });
    }
    _lastFetchTime = null; // bypass the 15s cooldown for an explicit retry
    await _fetchLivePlaces();
  }

  Future<void> _resolveCurrentLocationName(double lat, double lng) async {
    try {
      final name = await GooglePlacesService.reverseGeocode(lat, lng);
      if (mounted && name.isNotEmpty) {
        setState(() => _currentLocationName = name);
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }
  }

  /// GPS at ground level often has 10–20 m of horizontal error, and many
  /// shops sit shoulder-to-shoulder within that radius. So instead of always
  /// picking the absolute closest landmark, we treat everything inside the
  /// GPS error circle as "could be where I am" and rank them with a smarter
  /// heuristic.
  double get _locationAmbiguityRadius {
    final accuracy = _currentPosition?.accuracy ?? 15.0;
    // Minimum 20m guards against unrealistically tight GPS reports indoors.
    return max(20.0, accuracy + 5);
  }

  /// Landmarks that could plausibly be "where the user is", ranked smartly:
  ///   1. Places NOT in the camera view come first — in AR mode you point at
  ///      things you're looking AT, not where you're standing. So if the
  ///      camera is pointed at "Riky Mobiles", that's probably not where
  ///      you are; the shop behind you is.
  ///   2. Within each group (in-view vs. behind), closer wins.
  List<_ArLandmark> get _locationCandidates {
    final r = _locationAmbiguityRadius;
    final candidates =
        _landmarks.where((lm) => lm.distanceM <= r).toList();
    if (candidates.isEmpty) {
      return _landmarks.isEmpty ? const [] : [_landmarks.first];
    }
    candidates.sort((a, b) {
      final aInView =
          _signedAngleDelta(_heading, a.bearing).abs() <= _viewConeHalfDegrees;
      final bInView =
          _signedAngleDelta(_heading, b.bearing).abs() <= _viewConeHalfDegrees;
      if (aInView != bInView) return aInView ? 1 : -1; // behind-camera first
      return a.distanceM.compareTo(b.distanceM);
    });
    return candidates;
  }

  /// Pick the most specific name we can show in the "Your Location" pill.
  /// Honours a manual user pick first; otherwise uses the smart candidate
  /// ranking; falls back to the reverse-geocoded locality.
  String _resolveDisplayLocation() {
    if (_userPickedLocationName != null && _userPickedLocationName!.isNotEmpty) {
      return _userPickedLocationName!;
    }
    final candidates = _locationCandidates;
    if (candidates.isNotEmpty) {
      final pick = candidates.first;
      final d = pick.distanceM;
      if (d <= 10) return pick.name;
      if (d <= 40) return 'At ${pick.name}';
      if (d <= 150) return 'Near ${pick.name}';
    }
    if (_currentLocationName.isNotEmpty) return _currentLocationName;
    return 'Locating…';
  }

  /// Bottom sheet that lets the user confirm which nearby place they're
  /// actually at. GPS can't tell ground-floor neighbours apart, so this is
  /// the honest UX answer: show the candidates, let the human pick.
  void _showLocationPicker() {
    final candidates = _locationCandidates.take(8).toList();
    if (candidates.isEmpty) return;
    final currentDisplay = _resolveDisplayLocation();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 0.6,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Which place are you at?",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GPS can\'t tell ground-floor neighbours apart — pick the one you\'re actually inside.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...candidates.map((lm) {
                        final isCurrent =
                            currentDisplay.contains(lm.name) ||
                                _userPickedLocationName == lm.name;
                        final angle =
                            _signedAngleDelta(_heading, lm.bearing);
                        final inView =
                            angle.abs() <= _viewConeHalfDegrees;
                        return _buildLocationCandidateTile(
                          lm,
                          isCurrent: isCurrent,
                          inView: inView,
                        );
                      }),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            setState(() => _userPickedLocationName = null);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.65),
                          ),
                          child: const Text(
                            'Use automatic detection',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationCandidateTile(
    _ArLandmark lm, {
    required bool isCurrent,
    required bool inView,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        setState(() => _userPickedLocationName = lm.name);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrent
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.08),
            width: isCurrent ? 1.2 : 0.6,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.8,
                ),
              ),
              child: Icon(
                inView ? Icons.center_focus_strong_rounded : Icons.place_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lm.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${lm.distanceM.toInt()} m',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (inView) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• in view (you\'re looking at it)',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isCurrent)
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20)
            else
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.55), size: 22),
          ],
        ),
      ),
    );
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
      final currentPosition = await geo.Geolocator.getCurrentPosition();
      
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
  
  Widget _buildHomeButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('🏠 [Home Button] Tap registered!');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        HomePage.homeKey.currentState?.switchToExplore();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.2),
        ),
        child: const Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildMapsButton([_ArLandmark? landmark]) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('🗺️ [Maps Button] Tap registered!');
        if (landmark != null && landmark.lat != null && landmark.lng != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SmartTourismMapPage(
                initialLat: landmark.lat!,
                initialLng: landmark.lng!,
                destinationName: landmark.name,
                initialCategory: landmark.category.toUpperCase(),
              ),
            ),
          );
        } else if (_currentPosition != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SmartTourismMapPage(
                initialLat: _currentPosition!.latitude,
                initialLng: _currentPosition!.longitude,
                destinationName: _currentLocationName,
                initialCategory: _selectedFilter == 'All' ? 'HIDDEN' : _selectedFilter.toUpperCase(),
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SmartTourismMapPage(
                initialLat: 7.8731,
                initialLng: 80.7718,
                destinationName: 'Sri Lanka',
                initialCategory: 'HIDDEN',
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.2),
        ),
        child: const Text(
          'Maps',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildSmallLocationBadge() {
    final name = _resolveDisplayLocation();
    final canPick = _locationCandidates.length > 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canPick ? _showLocationPicker : null,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 26, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Your Location',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Positioned(
            right: -8,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E88E5),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// "Your Location" pill shown above the bottom card / sticky to lower screen.
  /// Tells the user which area the AR view is anchored to.
  Widget _buildLocationPill() {
    final name = _resolveDisplayLocation();
    final canPick = _locationCandidates.length > 1;
    // Discover mode renders a place-info card pinned at bottom: 40 (~110 px
    // tall, top edge ~bottom: 150). We tuck the pill just above that card
    // edge so they read as one bottom panel. The marker stack is compacted
    // (see rowHeight in _buildLandmarkMarker) so the last card clears this
    // zone. In explore mode there's no bottom card so we sit low.
    final reserveDiscoverySpace =
        _isIdentifying && !_isNevaAnalyzing && _nevaSearchResult == null;
    final pillBottom = reserveDiscoverySpace ? 158.0 : 36.0;
    return Positioned(
      bottom: pillBottom,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canPick ? _showLocationPicker : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E88E5).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Your Location',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (canPick) ...[
                          const SizedBox(width: 4),
                          Text(
                            '• tap to change',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (canPick) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Color(0xFF1E88E5), size: 22),
                ),
              ],
            ),
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
            begin: 1, end: 1.02, duration: 1800.ms),
      ),
    );
  }

  /// Convert a heading in degrees to a compass cardinal (N, NE, E, …, NW).
  String _cardinalFromHeading(double heading) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalized = (heading % 360 + 360) % 360;
    return dirs[((normalized + 22.5) ~/ 45) % 8];
  }

  Widget _buildTopHUD() {
    final cardinal = _cardinalFromHeading(_heading);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                  const SizedBox(width: 18),
                  // ── KM RANGE CYCLE CIRCLE (beside AR LIVE) ──
                  _buildKmRangePicker(),
                  const Spacer(),
                  // Combined XP + Compass pill
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // XP segment
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$_nexusPoints XP',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Compass segment
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Transform.rotate(
                                      angle: -_heading * pi / 180,
                                      child: CustomPaint(painter: _CompassNeedlePainter()),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cardinal,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 1,
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
                  const SizedBox(width: 12),
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
                            color: Colors.white.withOpacity(0.9),
                            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.black, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Single circular tap-to-cycle KM range button beside "AR LIVE".
  /// Each tap advances to the next step: 2→5→10→20→50→2→…
  Widget _buildKmRangePicker() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final steps = _rangeStepsForCategory(_selectedFilter);
        final idx = steps.indexOf(_rangeKm);
        final next = steps[idx == -1 ? 0 : (idx + 1) % steps.length];
        setState(() {
          _rangeKm = next;
          _capCache.clear();
        });
        _lastFetchTime = null;
        _fetchLivePlaces();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brandGreen,
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandGreen.withOpacity(0.55),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_rangeKm',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            Text(
              'km',
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 7,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.05, duration: 1200.ms, curve: Curves.easeInOut),
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
    if (_isCheckingPermissions) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }

    // Only location permission is required - camera is handled by Android system
    if (!_isLocationGranted) {
      return _buildLocationPermissionBarrier();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Live camera feed
          _buildCameraBackground(),

          // Removed subtle scan line wave effect as requested
          
          // EXPLORE MODE: Floating AR markers (compass-driven).
          // During navigation, show them dimmed so nearby POIs (like UC College)
          // remain visible as contextual landmarks.
          if (!_isIdentifying)
            if (_isNavigating)
              ...(_landmarksInView
                  .where((lm) => lm.name != _navigationTarget?.name)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => Opacity(
                        opacity: 0.4,
                        child: _buildLandmarkMarker(e.key, e.value),
                      )))
            else
              ..._landmarksInView
                  .asMap()
                  .entries
                  .map((e) => _buildLandmarkMarker(e.key, e.value)),

          // EXPLORE MODE: If we have places nearby but none in the view cone,
          // guide the user to rotate toward the closest one.
          if (!_isNavigating &&
              !_isIdentifying &&
              !_isMapping &&
              _nevaSearchResult == null &&
              !_showInfoCard &&
              _filteredLandmarks.isNotEmpty &&
              _landmarksInView.isEmpty)
            _buildRotateToDiscoverOverlay(),

          // DISCOVER MODE: Show single closest place with lock-on animation
          if (_isIdentifying && !_showInfoCard && !_isNevaAnalyzing && !_isNavigating)
            _buildDiscoveryTarget(),

          // Top HUD (XP and Map Place) - HIDE IF NAVIGATING OR SHOWING NEVA RESULTS
          if (!_minimalHud && !_isNavigating && _nevaSearchResult == null) _buildTopHUD(),



          // Filter chip bar - hide when mapping or showing detail (can be shown while navigating)
          if (!_minimalHud && !_isMapping && _nevaSearchResult == null && !_showInfoCard)
            _buildArFilterBar(),

          // Range slider - sits just below the filter chips; lets the user pick
          // how far out (km) to surface attractions / medical and all places.
          if (!_minimalHud && !_isMapping && _nevaSearchResult == null && !_showInfoCard)
            _buildRangeSlider(),

          // Place count/Status badge at bottom - HIDE IF NAVIGATING OR SHOWING NEVA RESULTS
          if (!_minimalHud && !_isNavigating && !_isIdentifying && _nevaSearchResult == null)
            Positioned(
              // Anchored below the range slider relative to the notch so it
              // never overlaps the slider or the floating place labels.
              top: MediaQuery.of(context).padding.top + 154,
              left: 0,
              right: 0,
              child: Center(child: _buildXPBadge()),
            ),

          // Tap-triggered place detail card (compact bottom card) - Consolidated Explore & Navigation Page!
          if (_isNavigating && _navigationTarget != null)
            _buildInfoCard(_navigationTarget!)
          else if (_showInfoCard && _selectedLandmark >= 0 && _selectedLandmark < _landmarks.length)
            _buildInfoCard(_landmarks[_selectedLandmark]),

          // Redesigned persistent Bottom Navigation Row (which includes Home, Location Pill, and Maps)
          if (!_minimalHud && !_isMapping && _nevaSearchResult == null)
            _buildBottomNavigationRow(),

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

  // ═══════════════════════════════════════
  // AR RANGE SLIDER - now replaced by the inline KM picker in _buildTopHUD
  // Kept as a no-op so existing call-sites in build() don't break.
  // ═══════════════════════════════════════
  Widget _buildRangeSlider() => const SizedBox.shrink();

  // ═══════════════════════════════════════
  // AR FILTER BAR - Horizontal chip selector
  // ═══════════════════════════════════════
  Widget _buildArFilterBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 68,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 40,
        child: Material(
          color: Colors.transparent,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _arFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = _arFilters[i];
              final id = f['id'] as String;
              final label = f['label'] as String;
              final icon = f['icon'] as IconData;
              final selected = _selectedFilter == id;
              // Show the count actually rendered (after per-category caps), not
              // the raw match count, so the chip never promises more than it shows.
              final count = _placesForFilter(id).length;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = id;
                    final maxKm = _maxRangeForCategory(id);
                    if (_rangeKm > maxKm) {
                      _rangeKm = maxKm;
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brandGreen : Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.5), blurRadius: 12)]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ).animate().fade(duration: 300.ms).slideY(begin: -0.1, end: 0),
        ),
      ),
    );
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

  /// Shown when there ARE nearby landmarks but none fall inside the camera's
  /// view cone — instead of leaving the screen empty (which looked broken),
  /// we tell the user which way to turn.
  Widget _buildRotateToDiscoverOverlay() {
    final hint = _nearestOffScreenLandmark;
    final angle = hint == null
        ? 0.0
        : _signedAngleDelta(_heading, hint.bearing); // -180..180
    final turnRight = angle > 0;
    final turnDegrees = angle.abs().round();

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rotating radar ring with arrow
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1,
                        ),
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
                          begin: 0.92,
                          end: 1.08,
                          duration: 1600.ms,
                          curve: Curves.easeInOut,
                        ),
                    Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.10),
                            Colors.transparent,
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: Transform.rotate(
                        // Point the arrow toward the nearest off-screen place.
                        angle: hint == null ? 0 : angle * pi / 180,
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                hint == null ? 'Look around' : 'Rotate to discover',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(blurRadius: 12, color: Colors.black54),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Subtle hint
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.32),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          turnRight
                              ? Icons.turn_right_rounded
                              : Icons.turn_left_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hint == null
                              ? 'No places in view — pan the camera'
                              : 'Turn ${turnRight ? 'right' : 'left'} ~$turnDegrees° toward ${hint.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Compass accuracy warning — magnetic interference makes the
              // bearing unreliable until the user does a figure-8 calibration.
              if (_compassAccuracy != null &&
                  _compassAccuracy! > _maxAcceptableAccuracyDegrees) ...[
                const SizedBox(height: 10),
                Text(
                  'Compass needs calibration — wave the phone in a figure 8',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          )
              .animate()
              .fade(duration: 250.ms)
              .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _buildLandmarkMarker(int index, _ArLandmark landmark) {
    // Reset visible counter at the start of each build cycle
    if (index == 0) _visibleCount = 0;

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    final angle = _signedAngleDelta(_heading, landmark.bearing);
    final dx = _projectAngleToScreenX(angle);
    if (dx == null) return const SizedBox.shrink();

    if (_visibleCount >= _maxVisibleOnScreen) return const SizedBox.shrink();

    int currentSlot = _visibleCount;
    _visibleCount++;

    // === COMPACT LAYOUT ===
    // Cards are stacked one per row. rowHeight MUST stay >= the rendered card
    // height (name pill + thumbnail card + tether ≈ 97 px) or consecutive cards
    // overlap. 104 leaves a small gap. Combined with [_maxVisibleOnScreen] this
    // keeps every visible label clear of its neighbours.
    // Notch-relative: clears the top HUD row (~48px) + filter chip bar (40px)
    // + a comfortable gap so cards never overlap the chips.
    // The range slider row was removed (now in HUD), so we reclaim that 34px
    // and push the first card slightly higher for a cleaner look.
    final double topStart = MediaQuery.of(context).padding.top + 160;
    const double rowHeight = 104.0;
    const double cardW = 170.0;

    double topPos = topStart + (currentSlot * rowHeight);
    double leftPos = (screenW * dx) - (cardW / 2);
    leftPos = leftPos.clamp(8.0, screenW - cardW - 8.0);

    // Stagger alternating markers horizontally
    if (currentSlot % 2 == 1) {
      leftPos = (leftPos + 30).clamp(8.0, screenW - cardW - 8.0);
    }

    // Direction badge
    final cardinal = _cardinalFromHeading(landmark.bearing);
    final arrowIcon = _arrowIconForCardinal(cardinal);

    return Positioned(
      left: leftPos,
      top: topPos,
      child: GestureDetector(
        onTap: () {
          final i = _landmarks.indexWhere((l) => l.name == landmark.name);
          if (i >= 0) {
            setState(() {
              _selectedLandmark = i;
              _showInfoCard = true;
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── COMPACT NAME PILL (uniform style for all markers) ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
              ),
              child: Text(
                landmark.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),

            // ── COMPACT DARK CARD ──
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: cardW,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 40, height: 40,
                          child: _buildMarkerImage(landmark),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Rating + Distance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                                const SizedBox(width: 3),
                                Text('${landmark.rating}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              landmark.distance,
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── DOTTED LINE TO GROUND ──
            SizedBox(
              height: 12,
              child: CustomPaint(
                size: const Size(2, double.infinity),
                painter: _DottedLinePainter(
                  color: Colors.white.withOpacity(0.4),
                  dashHeight: 3,
                  dashSpace: 3,
                  dashWidth: 1.2,
                ),
              ),
            ),
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.7),
                boxShadow: [
                  BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fade(duration: 350.ms).moveX(begin: -20, end: 0, curve: Curves.easeOutBack);
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
        // ── PLACE DOTS (highlighted when locked/pointed) ─
        ..._buildOtherPlaceDots(pointedLandmark, screenW, screenH),

        // ── PLACE INFO PANEL (when pointing at a place) ─
        if (pointedLandmark != null) ...[
          // Place info panel — static, no blink, live content
          Positioned(
            left: 16,
            right: 16,
            bottom: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHomeButton(),
                      const SizedBox(width: 8),
                      Flexible(child: _buildSmallLocationBadge()),
                      const SizedBox(width: 8),
                      _buildMapsButton(pointedLandmark),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // Banner body tap → open the place info / navigation card
                    final i = _landmarks.indexWhere((l) => l.name == pointedLandmark.name);
                    setState(() {
                      _selectedLandmark = i >= 0 ? i : _selectedLandmark;
                      _showInfoCard = true;
                    });
                  },
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
                                      const Icon(Icons.straighten, color: Colors.white38, size: 13),
                                      const SizedBox(width: 3),
                                      Text(pointedLandmark.distance, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // ── NEVA AVATAR — only this area opens Neva ──
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _startNevaSearch(pointedLandmark),
                              child: Column(
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── DIRECTION GUIDE (no landmark in view) ──────────────────
        if (pointedLandmark == null && !_isNevaSearching)
          _buildDirectionGuide(),
      ],
    );
  }

  /// Build a label card per visible landmark, spread by bearing, with a
  /// direction badge (NE/N/etc) + dotted line dropping toward its ground
  /// position. Highlights the one the camera is currently pointed at.
  /// Cards are placed with greedy collision avoidance so they don't stack.
  List<Widget> _buildOtherPlaceDots(_ArLandmark? pointedLandmark, double screenW, double screenH) {
    final List<Widget> markers = [];
    final visible = _filteredLandmarks;

    if (visible.isEmpty) return markers;

    final double maxDist = visible.map((l) => l.distanceM).reduce((a, b) => a > b ? a : b);
    if (maxDist <= 1.0) return markers;

    const double topY = 185.0; // Adjusted from 140.0 to prevent overlapping with the top category selection bar
    final double bottomY = screenH * 0.55;
    const double cardW = 165;
    const double cardH = 60;
    const double gap = 8;

    // Pre-compute candidate placements, sorted by distance ascending so
    // closer places get their preferred slot first.
    final placements = <_ArLabelPlacement>[];
    for (final lm in visible) {
      final double liveBearing = (_currentPosition != null && lm.lat != null && lm.lng != null)
          ? _calculateBearing(_currentPosition!.latitude, _currentPosition!.longitude, lm.lat!, lm.lng!)
          : lm.bearing;

      double diff = liveBearing - _heading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      // Position the card with the SAME perspective projection the camera lens
      // uses (tan(angle)/tan(halfFov)), so a card sits exactly where its place
      // appears in the live image — instead of being spread linearly across a
      // cone far wider than the real field of view. Returns null when the place
      // is outside the lens's view, so cards only show for things actually in
      // front of the camera (this is what fixes the "wrong direction" mismatch).
      final double? dx = _projectAngleToScreenX(diff);
      if (dx == null) continue;
      final double centerX = (screenW * dx).clamp(cardW / 2 + 8, screenW - cardW / 2 - 8);

      final double logNorm = (log(lm.distanceM + 1) / log(maxDist + 1)).clamp(0.05, 1.0);
      final double preferredY = bottomY - logNorm * (bottomY - topY);

      placements.add(_ArLabelPlacement(
        landmark: lm,
        bearing: liveBearing,
        preferredX: centerX,
        preferredY: preferredY,
      ));
    }

    placements.sort((a, b) => a.landmark.distanceM.compareTo(b.landmark.distanceM));

    // Greedy collision avoidance: bump down if a placed card overlaps.
    final placedRects = <Rect>[];
    for (final p in placements) {
      double x = p.preferredX - cardW / 2;
      double y = p.preferredY;
      Rect candidate = Rect.fromLTWH(x, y, cardW, cardH);

      int attempts = 0;
      while (attempts < 12) {
        final overlap = placedRects.any((r) => r.inflate(gap / 2).overlaps(candidate.inflate(gap / 2)));
        if (!overlap) break;
        y += cardH + gap;
        candidate = Rect.fromLTWH(x, y, cardW, cardH);
        attempts++;
      }

      // Don't render beyond the visible AR band — skip if pushed too far down.
      if (candidate.top > screenH * 0.72) continue;

      placedRects.add(candidate);
      p.finalX = candidate.left;
      p.finalY = candidate.top;
    }

    for (final p in placements) {
      if (p.finalY == null) continue;
      final lm = p.landmark;

      final cardinal = _cardinalFromHeading(p.bearing);
      final arrowIcon = _arrowIconForCardinal(cardinal);

      // All cards use the same neutral dark style — no blue lock highlight
      const Color cardBg = Colors.black;
      final Color borderColor = Colors.white.withOpacity(0.08);

      // Realistic short pointers (fixed 40px length) instead of floor cables
      const double lineHeight = 40.0;

      markers.add(
        Positioned(
          left: p.finalX!,
          top: p.finalY!,
          child: GestureDetector(
            onTap: () {
              final i = _landmarks.indexWhere((l) => l.name == lm.name);
              if (i >= 0) {
                setState(() {
                  _selectedLandmark = i;
                  _showInfoCard = true;
                });
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Label card 
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                  width: cardW,
                  height: cardH,
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      PlaceImageHelper.buildPlaceImage(
                        imagePath: lm.imagePath,
                        category: lm.category,
                        name: lm.name,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(width: 6),
                      // Name / rating / distance
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lm.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                const SizedBox(width: 2),
                                Text(
                                  '${lm.rating}',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              lm.distance,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // ── SMALL WHITE DIRECTION BADGE (no arrow) ──
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            cardinal,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                  ],
                ),
                // Dotted vertical drop line to ground anchor
                if (lineHeight > 4) ...[
                  SizedBox(
                    width: 2,
                    height: lineHeight,
                    child: CustomPaint(
                      painter: _DottedDropLinePainter(
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 6, spreadRadius: 1),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  /// Map a cardinal direction string to a matching arrow icon.
  IconData _arrowIconForCardinal(String cardinal) {
    switch (cardinal) {
      case 'N':  return Icons.arrow_upward_rounded;
      case 'NE': return Icons.north_east_rounded;
      case 'E':  return Icons.arrow_forward_rounded;
      case 'SE': return Icons.south_east_rounded;
      case 'S':  return Icons.arrow_downward_rounded;
      case 'SW': return Icons.south_west_rounded;
      case 'W':  return Icons.arrow_back_rounded;
      case 'NW': return Icons.north_west_rounded;
      default:   return Icons.arrow_upward_rounded;
    }
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
  
  /// Empty / error / no-permission state for the AR overlay, shown when there
  /// are no landmarks to display after a fetch has finished. Always offers a
  /// retry so the user is never stuck on an endless "SCANNING…" spinner.
  Widget _buildArEmptyState(double bottom, IconData icon, String title, String subtitle) {
    return Positioned(
      left: 24, right: 24, bottom: bottom,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white70, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11.5, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _isFetchingPlaces ? null : _retryFetchPlaces,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 7),
                          Text('RETRY', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
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
    );
  }

  /// Direction guide — tells user to turn left/right with degrees to nearest place
  Widget _buildDirectionGuide() {
    // Sit above the "Your Location" pill (at bottom: 158, ~50px tall) so they
    // don't crowd each other at the bottom of the screen.
    const double guideBottom = 240;

    if (_landmarks.isEmpty) {
      final bool stillLoading = !_hasCompletedInitialFetch || _isFetchingPlaces;
      if (stillLoading) {
        // Genuine loading — show the scanning pulse.
        return Positioned(
          left: 0, right: 0, bottom: guideBottom,
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
                      Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white38))
                        .animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.2, end: 1, duration: 700.ms),
                      const SizedBox(width: 10),
                      const Text('SCANNING FOR PLACES...', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.4, end: 1, duration: 900.ms),
          ),
        );
      }

      // Fetch finished with nothing to display — explain why and offer a retry,
      // instead of leaving the scanning spinner up forever.
      final bool needsLocation = !_isLocationGranted;
      final IconData icon = needsLocation
          ? Icons.location_off_rounded
          : (_placesFetchError ? Icons.cloud_off_rounded : Icons.explore_off_rounded);
      final String title = needsLocation
          ? 'LOCATION NEEDED'
          : (_placesFetchError ? "COULDN'T LOAD PLACES" : 'NO PLACES NEARBY');
      final String subtitle = needsLocation
          ? 'Enable location to discover places around you'
          : (_placesFetchError
              ? 'Check your connection and try again'
              : 'Nothing found in this area right now');
      return _buildArEmptyState(guideBottom, icon, title, subtitle);
    }

    // Places are already visible in front of the user — don't nag them with
    // a "turn" instruction toward a place they can already see. The guide is
    // only meant to point the way when the camera is aimed at empty space.
    // This is what fixed the "navigation shows randomly" report: the guide
    // now strictly appears only when no places sit in the forward view.
    if (_hasLandmarkInForwardView) return const SizedBox.shrink();

    // Find the nearest place by angle difference
    final pool = _filteredLandmarks;
    _ArLandmark? nearest;
    double bestDiff = double.infinity;
    double bestRawDiff = 0; // signed: negative = left, positive = right

    for (final lm in pool) {
      final double liveBearing = (_currentPosition != null && lm.lat != null && lm.lng != null)
          ? _calculateBearing(_currentPosition!.latitude, _currentPosition!.longitude, lm.lat!, lm.lng!)
          : lm.bearing;
      double diff = liveBearing - _heading;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      if (diff.abs() < bestDiff) {
        bestDiff = diff.abs();
        bestRawDiff = diff;
        nearest = lm;
      }
    }

    if (nearest == null) return const SizedBox.shrink();

    final bool turnRight = bestRawDiff > 0;
    final int degrees = bestDiff.round();
    final String dirLabel = turnRight ? 'RIGHT' : 'LEFT';
    final IconData arrow = turnRight ? Icons.turn_right_rounded : Icons.turn_left_rounded;
    const Color guideColor = Color(0xFF00E5FF);

    // Truncate name
    final name = nearest.name.length > 15 ? '${nearest.name.substring(0, 14)}…' : nearest.name;

    return Positioned(
      left: 0, right: 0, bottom: guideBottom,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: guideColor.withOpacity(0.4), width: 1),
                boxShadow: [BoxShadow(color: guideColor.withOpacity(0.15), blurRadius: 16)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(arrow, color: guideColor, size: 20)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveX(begin: turnRight ? 0 : -4, end: turnRight ? 4 : 0, duration: 800.ms),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TURN $dirLabel ${degrees}°',
                        style: const TextStyle(color: guideColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    nearest.distance,
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Get the landmark that the camera is currently pointing at
  _ArLandmark? _getPointedLandmark() {
    final pool = _filteredLandmarks;
    if (_currentPosition == null || pool.isEmpty) return null;
    
    // Camera is pointing in the direction of current heading
    final cameraHeading = _heading;
    
    // Find landmark closest to camera heading
    _ArLandmark? closestLandmark;
    double smallestAngleDiff = double.infinity;
    
    for (final landmark in pool) {
      // Reuse the bearing already maintained on position updates instead of
      // recomputing it every compass tick — it only changes when the user moves,
      // not when they rotate, and this matches how the markers are placed.
      final bearing = landmark.bearing;

      // Calculate angle difference between camera heading and landmark bearing
      double angleDiff = (bearing - cameraHeading).abs();
      if (angleDiff > 180) angleDiff = 360 - angleDiff;
      
      // Consider landmarks within 30 degrees of camera center
      if (angleDiff < 30 && angleDiff < smallestAngleDiff) {
        smallestAngleDiff = angleDiff;
        closestLandmark = landmark;
      }
    }

    return closestLandmark;
  }
  
  /// Start Neva search for place information
  void _startNevaSearch(_ArLandmark landmark) async {
    setState(() {
      _isNevaSearching = true;
      _frozenLandmark = landmark; // Freeze this landmark
    });

    final cacheKey = _nevaCacheKey(landmark);

    // Cache hit — skip Gemini entirely
    final cached = _nevaPlaceCache[cacheKey];
    if (cached != null) {
      debugPrint('🔍 NEVA: Cache hit for ${landmark.name}');
      if (!mounted) return;
      setState(() {
        _nevaSearchResult = Map<String, dynamic>.from(cached);
        _isNevaSearching = false;
      });
      return;
    }

    try {
      final locStr = (landmark.lat != null && landmark.lng != null)
          ? ' at ${landmark.lat!.toStringAsFixed(4)}, ${landmark.lng!.toStringAsFixed(4)}'
          : '';
      final placePrompt =
          'You are a deeply knowledgeable local historian and insider guide. '
          'The user is standing near "${landmark.name}" (a ${landmark.category} rated ${landmark.rating}/5$locStr). '
          'Provide RARE, UNIQUE, NON-GENERIC facts that most people and tourists would NEVER know. '
          'Do NOT give generic descriptions like "popular restaurant" or "well-known temple". '
          'Instead dig deep: hidden history, surprising origin stories, local legends, architectural secrets, '
          'famous incidents, cultural significance, what locals call it, secret menu items, '
          'best-kept secrets, or little-known connections to famous people/events.\n\n'
          'Return ONLY this JSON (no prose, no code fences):\n'
          '{"tagline":"<=12 words, a surprising hook that grabs attention",'
          '"hidden_history":"2-3 sentences about the origin story or historical significance most people miss",'
          '"surprising_fact":"1 jaw-dropping fact that would make someone say wow",'
          '"local_secret":"something only locals know — a hidden feature, secret spot, or insider knowledge",'
          '"best_time":"when is the absolute best time to visit and why (be specific)",'
          '"top_positive":"a specific glowing praise point as if from a real review",'
          '"top_negative":"a specific honest criticism as if from a real review",'
          '"insider_tip":"<=20 words — a practical local tip that guidebooks never mention"}\n'
          'Be hyper-specific to THIS exact place. Never be vague or generic.';

      debugPrint('🔍 NEVA: Starting search for ${landmark.name}');

      final geminiService = GeminiService();
      final response = await geminiService
          .getResponse(
            placePrompt,
            temperature: 0.5,
            maxOutputTokens: 512,
            responseMimeType: 'application/json',
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('🔍 NEVA: Got response: ${response.substring(0, response.length.clamp(0, 100))}...');

      Map<String, dynamic> parsed = {};
      if (response.isNotEmpty) {
        // Strip markdown fences Gemini sometimes adds even in JSON mode
        var cleaned = response.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
          final fenceEnd = cleaned.lastIndexOf('```');
          if (fenceEnd >= 0) cleaned = cleaned.substring(0, fenceEnd);
          cleaned = cleaned.trim();
        }
        final jsonStart = cleaned.indexOf('{');
        final jsonEnd = cleaned.lastIndexOf('}') + 1;
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          try {
            final decoded = jsonDecode(cleaned.substring(jsonStart, jsonEnd));
            if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
          } catch (e) {
            debugPrint('🔍 NEVA: JSON parse failed: $e');
          }
        }
      }

      final nevaResult = <String, dynamic>{
        'name': landmark.name,
        'category': landmark.category,
        'distance': landmark.distance,
        'rating': landmark.rating,
        'tagline': parsed['tagline'] ?? '',
        'hidden_history': parsed['hidden_history'] ?? '',
        'surprising_fact': parsed['surprising_fact'] ?? '',
        'local_secret': parsed['local_secret'] ?? '',
        'best_time': parsed['best_time'] ?? '',
        'top_positive': parsed['top_positive'] ?? '',
        'top_negative': parsed['top_negative'] ?? '',
        'insider_tip': parsed['insider_tip'] ?? '',
        'description': response,
        'confidence': parsed.isEmpty ? 0.7 : 0.9,
      };

      // Cache only if Gemini gave us useful structured content
      if (parsed.isNotEmpty) {
        if (_nevaPlaceCache.length >= _nevaCacheMaxEntries) {
          _nevaPlaceCache.remove(_nevaPlaceCache.keys.first);
        }
        _nevaPlaceCache[cacheKey] = nevaResult;
      }

      if (!mounted) return;
      setState(() {
        _nevaSearchResult = nevaResult;
      });

      debugPrint('🔍 NEVA: Search completed for ${landmark.name}');
    } catch (e) {
      debugPrint('🔍 NEVA: Error during search: $e');
      final basicResult = <String, dynamic>{
        'name': landmark.name,
        'category': landmark.category,
        'distance': landmark.distance,
        'rating': landmark.rating,
        'description': landmark.description,
        'fun_fact': '',
        'tips': '',
        'confidence': 0.7,
      };

      if (!mounted) return;
      setState(() {
        _nevaSearchResult = basicResult;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isNevaSearching = false;
        });
      }
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
    final hiddenHistory = result['hidden_history'] ?? '';
    final surprisingFact = result['surprising_fact'] ?? '';
    final localSecret = result['local_secret'] ?? '';
    final bestTime = result['best_time'] ?? '';
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

        // ── Bubble 3: tagline hook ────────────────────────────
        if (tagline.isNotEmpty)
          _nevaBubble(
            child: Text('\"$tagline\"',
              style: const TextStyle(color: Colors.black87, fontSize: 14, fontStyle: FontStyle.italic, height: 1.5)),
            delay: 600.ms,
          ),

        // ── Bubble 4: Hidden History ──────────────────────────
        if (hiddenHistory.isNotEmpty)
          _nevaBubble(
            child: _bubbleHighlight(Icons.menu_book_rounded, 'Hidden History', hiddenHistory, const Color(0xFF8B5CF6)),
            delay: 900.ms,
          ),

        // ── Bubble 5: Surprising Fact ─────────────────────────
        if (surprisingFact.isNotEmpty)
          _nevaBubble(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🤯', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Flexible(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.5),
                      children: [
                        const TextSpan(text: 'Did you know?  ', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE11D48))),
                        TextSpan(text: surprisingFact),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            delay: 1200.ms,
          ),

        // ── Bubble 6: Local Secret ────────────────────────────
        if (localSecret.isNotEmpty)
          _nevaBubble(
            child: _bubbleHighlight(Icons.lock_open_rounded, 'Local Secret', localSecret, const Color(0xFF059669)),
            delay: 1500.ms,
          ),

        // ── Bubble 7: Best Time to Visit ──────────────────────
        if (bestTime.isNotEmpty)
          _nevaBubble(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🕐', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Flexible(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.5),
                      children: [
                        const TextSpan(text: 'Best time  ', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0284C7))),
                        TextSpan(text: bestTime),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            delay: 1800.ms,
          ),

        // ── Bubble 8: positive review ─────────────────────────
        if (topPositive.isNotEmpty)
          _nevaBubble(
            child: _bubbleReview(true, topPositive),
            delay: 2100.ms,
          ),

        // ── Bubble 9: negative review ─────────────────────────
        if (topNegative.isNotEmpty)
          _nevaBubble(
            child: _bubbleReview(false, topNegative),
            delay: 2400.ms,
          ),

        // ── Bubble 10: insider tip ────────────────────────────
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
            delay: 2700.ms,
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
      final currentPosition = await geo.Geolocator.getCurrentPosition();
      
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

  /// Compact tap-triggered place card (client-requested redesign).
  ///
  /// Left half = the place the user tapped. Right half = quick "NEARBY"
  /// category shortcuts that pull food / shopping / services / medical spots
  /// around that place via Ask Neva.
  Widget _buildInfoCard(_ArLandmark landmark) {
    final reviewCount = (landmark.rating * 26).round();

    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildHomeButton(),
                const SizedBox(width: 8),
                Flexible(child: _buildSmallLocationBadge()),
                const SizedBox(width: 8),
                _buildMapsButton(landmark),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14).withOpacity(0.92), // Futuristic deep space blue-black
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.25), width: 1.2), // Glowing neon blue border
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Section headers row: YOU SELECTED | X ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'YOU SELECTED',
                          style: TextStyle(
                            color: Color(0xFF00E5FF), // Brighter neon blue
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (!_isNavigating)
                          GestureDetector(
                            onTap: () => setState(() {
                              _showInfoCard = false;
                              _isListening = false;
                            }),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF5252).withValues(alpha: 0.18),
                                border: Border.all(
                                  color: const Color(0xFFFF5252).withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF5252).withValues(alpha: 0.2),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFFF5252),
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Body (Details / Nearby Categories Side-by-Side) ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left half: Selected Place Details
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PlaceImageHelper.buildPlaceImage(
                                    imagePath: landmark.imagePath,
                                    category: landmark.category,
                                    name: landmark.name,
                                    width: 56,
                                    height: 56,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      landmark.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        height: 1.15,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${landmark.rating}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '($reviewCount)',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.straighten_rounded, color: Colors.white.withOpacity(0.6), size: 13),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      landmark.distance,
                                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // MORE INFO — opens Ask Neva
                              GestureDetector(
                                onTap: () => _openAskNevaFor(landmark),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
                                  ),
                                  child: const Text(
                                    'MORE INFO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Right half: NEARBY category shortcuts
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.white.withOpacity(0.12), width: 0.8),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'NEARBY',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.restaurant_rounded,
                                      label: 'FOOD',
                                      color: Colors.redAccent,
                                      categoryId: 'food',
                                      prettyLabel: 'Food',
                                    ),
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.shopping_bag_rounded,
                                      label: 'SHOP',
                                      color: Colors.greenAccent.shade700,
                                      categoryId: 'shopping',
                                      prettyLabel: 'Shopping',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.account_balance_rounded,
                                      label: 'HISTORY',
                                      color: Colors.blueAccent,
                                      categoryId: 'historical',
                                      prettyLabel: 'Historical Sites',
                                    ),
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.hotel_rounded,
                                      label: 'HOTELS',
                                      color: Colors.purpleAccent,
                                      categoryId: 'hotel',
                                      prettyLabel: 'Hotels',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (_isNavigating) ...[
                      // Step progress bar (when route available)
                      if (_walkingRoute != null && _walkingRoute!.steps.isNotEmpty) ...[
                        _buildStepProgressBar(),
                        const SizedBox(height: 12),
                      ],

                      // Dynamic navigation guidance row + EXIT button
                      () {
                        final hasRoute = _walkingRoute != null && _walkingRoute!.steps.isNotEmpty;
                        final RouteStep? currentStep = hasRoute && _currentStepIndex < _walkingRoute!.steps.length
                            ? _walkingRoute!.steps[_currentStepIndex]
                            : null;

                        // Determine maneuver icon based on turn direction
                        IconData maneuverIcon = Icons.arrow_upward_rounded;
                        double diff = 0.0;
                        if (_navigationTarget != null) {
                          final navBearing = _activeNavBearing;
                          diff = _signedAngleDelta(_heading, navBearing);
                        }
                        if (currentStep?.maneuver != null) {
                          final m = currentStep!.maneuver!;
                          if (m.contains('left')) maneuverIcon = Icons.turn_left_rounded;
                          else if (m.contains('right')) maneuverIcon = Icons.turn_right_rounded;
                          else if (m.contains('uturn')) maneuverIcon = Icons.u_turn_left_rounded;
                          else if (m.contains('roundabout')) maneuverIcon = Icons.roundabout_left_rounded;
                        }

                        return Row(
                          children: [
                            // Turn-by-Turn Instruction Card (flex: 8)
                            Expanded(
                              flex: 8,
                              child: Container(
                                height: 52,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E5FF).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.05), blurRadius: 10),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // Maneuver Icon box
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1),
                                      ),
                                      child: Icon(
                                        hasRoute ? maneuverIcon : (diff.abs() < 30 ? Icons.arrow_upward_rounded : (diff > 0 ? Icons.turn_right_rounded : Icons.turn_left_rounded)),
                                        color: const Color(0xFF00E5FF),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Instruction details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            hasRoute
                                                ? 'STEP ${_currentStepIndex + 1}/${_walkingRoute!.steps.length}'
                                                : 'HEADING TARGET',
                                            style: const TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hasRoute
                                                ? (currentStep?.instruction ?? 'Follow route')
                                                : (diff.abs() < 30 ? 'Keep heading forward' : 'Rotate to your ${diff > 0 ? "right" : "left"}'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
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
                            const SizedBox(width: 10),
                            // Crimson-Red glowing EXIT button (flex: 3)
                            Expanded(
                              flex: 3,
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isNavigating = false;
                                  _navigationTarget = null;
                                  _walkingRoute = null;
                                  _currentStepIndex = 0;
                                  _hasArrivedAtDestination = false;
                                  _arMode = 'explore';
                                }),
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFFFF5252).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 3)),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text(
                                        'EXIT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }(),
                    ] else ...[
                      // ── START NAVIGATION button ──
                      GestureDetector(
                        onTap: () {
                          _startRouteNavigation(landmark);
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.navigation_rounded, color: Colors.black, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'START NAVIGATION',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ).animate().slideY(begin: 0.4, end: 0, duration: 400.ms, curve: Curves.easeOutQuart).fade(duration: 300.ms),
    );
  }

  /// One tile in the NEARBY strip — colored icon square + caption underneath.
  Widget _buildNearbyTile({
    required _ArLandmark landmark,
    required IconData icon,
    required String label,
    required Color color,
    required String categoryId,
    required String prettyLabel,
  }) {
    return GestureDetector(
      onTap: () => _openNearbyCategoryFor(landmark, categoryId, prettyLabel),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, // More compact sizing to prevent overlaps and overflows
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20), // Balanced icon size
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 7.5, // Reduced font size for tight space alignment
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5, // Reduced letter spacing to save horizontal pixels
            ),
          ),
        ],
      ),
    );
  }

  /// Open Ask Neva for a specific landmark with no auto-fetch — used by
  /// MORE INFO and the place name itself.
  void _openAskNevaFor(_ArLandmark landmark) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(
          initialPrompt: 'Tell me more about ${landmark.name}.',
          placeContext: {
            'name': landmark.name,
            'category': landmark.category,
            'latitude': landmark.lat,
            'longitude': landmark.lng,
          },
        ),
      ),
    );
  }

  /// Open Ask Neva and auto-trigger a nearby-places fetch for the chosen
  /// category around this landmark — used by the NEARBY tiles.
  void _openNearbyCategoryFor(_ArLandmark landmark, String categoryId, String prettyLabel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(
          placeContext: {
            'name': landmark.name,
            'category': landmark.category,
            'latitude': landmark.lat,
            'longitude': landmark.lng,
          },
          autoFetchCategoryId: categoryId,
          autoFetchCategoryLabel: prettyLabel,
        ),
      ),
    );
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

    // Use route step bearing when available, otherwise straight-line to target
    final navBearing = _activeNavBearing;
    double diff = _signedAngleDelta(_heading, navBearing);
    final isTargetInView = diff.abs() < 30;

    // Current step info
    final hasRoute = _walkingRoute != null && _walkingRoute!.steps.isNotEmpty;
    final RouteStep? currentStep = hasRoute && _currentStepIndex < _walkingRoute!.steps.length
        ? _walkingRoute!.steps[_currentStepIndex]
        : null;
    final RouteStep? nextStep = hasRoute && _currentStepIndex + 1 < _walkingRoute!.steps.length
        ? _walkingRoute!.steps[_currentStepIndex + 1]
        : null;

    // Determine maneuver icon
    IconData maneuverIcon = Icons.arrow_upward_rounded;
    if (currentStep?.maneuver != null) {
      final m = currentStep!.maneuver!;
      if (m.contains('left')) maneuverIcon = Icons.turn_left_rounded;
      else if (m.contains('right')) maneuverIcon = Icons.turn_right_rounded;
      else if (m.contains('uturn')) maneuverIcon = Icons.u_turn_left_rounded;
      else if (m.contains('roundabout')) maneuverIcon = Icons.roundabout_left_rounded;
    }

    const cyan = Color(0xFF00E5FF);

    return Positioned.fill(
      child: Stack(
        children: [
          // Subtle edge vignette
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.15)],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),

          // ══════════════════════════════════════
          // ANIMATED AR CHEVRONS (Google Maps style)
          // ══════════════════════════════════════
          if (!_isFetchingRoute && !_hasArrivedAtDestination)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildArChevrons(diff, isTargetInView),
              ),
            ),

          // ROUTE LOADING indicator
          if (_isFetchingRoute)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: 0, right: 0,
              child: Column(
                children: [
                  const SizedBox(
                    width: 48, height: 48,
                    child: CircularProgressIndicator(color: cyan, strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text('Calculating route...', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ).animate().fade(),
            ),

          // ARRIVAL CELEBRATION
          if (_hasArrivedAtDestination)
            Positioned.fill(
              child: _buildArrivalCelebration(),
            ),

          // FLOATING AR MARKER ON TARGET (when in view)
          if (isTargetInView && !_hasArrivedAtDestination) () {
            final angle = _signedAngleDelta(_heading, _navigationTarget!.bearing);
            final dx = _projectAngleToScreenX(angle);
            if (dx != null) {
              final screenW = MediaQuery.of(context).size.width;
              final screenH = MediaQuery.of(context).size.height;
              return Positioned(
                left: (screenW * dx) - 80,
                top: screenH * 0.35,
                child: _buildNavigationBubble(_navigationTarget!),
              );
            }
            return const SizedBox.shrink();
          }(),

          // DISTANCE HUD (Elevated to fit perfectly above the bottom merged card)
          if (!_hasArrivedAtDestination)
            Positioned(
              bottom: _isNavigating ? 360 : 310,
              left: 0, right: 0,
              child: Column(
                children: [
                  Text(
                    _navigationTarget!.distance.toUpperCase(),
                    style: const TextStyle(
                      color: cyan, fontSize: 72, fontWeight: FontWeight.w900, letterSpacing: -2,
                      shadows: [Shadow(color: cyan, blurRadius: 30)],
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1.seconds),
                  Text(
                    'TO ${_navigationTarget!.name.toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2,
                      shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
                  ),
                  // Route overview (total distance + ETA)
                  if (hasRoute) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${_walkingRoute!.remainingDistanceText(_currentStepIndex)} · ${_walkingRoute!.totalDuration}',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // AR CHEVRONS — Animated directional arrows (Google Maps style)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildArChevrons(double bearingDiff, bool isAhead) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    const cyan = Color(0xFF00E5FF);

    // Rotation angle: 0 when straight ahead, rotates with bearing diff
    final rotationAngle = isAhead ? 0.0 : (bearingDiff.clamp(-90, 90) * pi / 180);

    // Horizontal offset: chevrons shift toward the direction
    final hOffset = isAhead ? 0.0 : (bearingDiff.clamp(-60, 60) / 60) * (screenW * 0.25);

    // Opacity: brighter when target is ahead
    final baseOpacity = isAhead ? 0.9 : (0.5 + (1 - bearingDiff.abs() / 90).clamp(0, 1) * 0.4);

    return Stack(
      children: List.generate(3, (i) {
        // Stagger each chevron vertically
        final yPos = screenH * 0.55 - (i * 65);
        final chevronOpacity = (baseOpacity - i * 0.2).clamp(0.15, 0.9);
        final chevronScale = 1.0 - (i * 0.1);

        return Positioned(
          left: (screenW / 2 - 50) + hOffset,
          top: yPos,
          child: Transform.rotate(
            angle: rotationAngle,
            child: Opacity(
              opacity: chevronOpacity,
              child: Transform.scale(
                scale: chevronScale,
                child: SizedBox(
                  width: 100, height: 60,
                  child: CustomPaint(
                    painter: _ChevronPainter(
                      color: cyan,
                      glowIntensity: i == 0 ? 1.0 : 0.4,
                    ),
                  ),
                ),
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .moveY(
                begin: 20, end: -20,
                duration: Duration(milliseconds: 1200 + i * 200),
                curve: Curves.easeInOut,
              )
              .then()
              .moveY(
                begin: -20, end: 20,
                duration: Duration(milliseconds: 1200 + i * 200),
                curve: Curves.easeInOut,
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(
                begin: chevronOpacity * 0.6,
                end: chevronOpacity,
                duration: Duration(milliseconds: 800 + i * 300),
              ),
        );
      }),
    );
  }

  /// Step progress bar showing which step the user is on
  Widget _buildStepProgressBar() {
    if (_walkingRoute == null) return const SizedBox.shrink();
    final total = _walkingRoute!.steps.length;
    const cyan = Color(0xFF00E5FF);

    return Row(
      children: List.generate(total, (i) {
        final isCompleted = i < _currentStepIndex;
        final isCurrent = i == _currentStepIndex;
        return Expanded(
          child: Container(
            height: 3,
            margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: isCompleted
                  ? cyan
                  : (isCurrent ? cyan.withOpacity(0.6) : Colors.white.withOpacity(0.15)),
              boxShadow: isCompleted || isCurrent
                  ? [BoxShadow(color: cyan.withOpacity(0.4), blurRadius: 4)]
                  : null,
            ),
          ),
        );
      }),
    );
  }

  /// Arrival celebration overlay
  Widget _buildArrivalCelebration() {
    const cyan = Color(0xFF00E5FF);
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cyan.withOpacity(0.15),
                border: Border.all(color: cyan, width: 3),
                boxShadow: [BoxShadow(color: cyan.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
              ),
              child: const Icon(Icons.flag_rounded, color: cyan, size: 48),
            ).animate().scale(begin: const Offset(0, 0), end: const Offset(1, 1), duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            const Text('YOU\'VE ARRIVED!', style: TextStyle(color: cyan, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
            const SizedBox(height: 8),
            Text(
              _navigationTarget?.name ?? 'Destination',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => setState(() {
                _isNavigating = false;
                _navigationTarget = null;
                _walkingRoute = null;
                _hasArrivedAtDestination = false;
                _arMode = 'explore';
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  color: cyan, borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: cyan.withOpacity(0.4), blurRadius: 20)],
                ),
                child: const Text('CONTINUE EXPLORING', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    ).animate().fade(duration: 400.ms);
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

  Widget _buildLocationPermissionBarrier() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background grid
          _buildScanLines(),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Icon
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.1),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 48),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 2.seconds),
                  
                  const SizedBox(height: 40),
                  
                  const Text(
                    'LOCATION REQUIRED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fade().slideY(begin: 0.2),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    'To explore nearby places in AR, NexAround needs access to your location. Camera access will be requested by your device when needed.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fade(delay: 200.ms),
                  
                  const SizedBox(height: 48),
                  
                  // Permission indicator
                  _buildPermissionIndicator('Location', _isLocationGranted),
                  
                  const SizedBox(height: 64),
                  
                  // Grant Button
                  GestureDetector(
                    onTap: () => openAppSettings(),
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'ENABLE LOCATION',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ).animate().fade(delay: 600.ms).slideY(begin: 0.3),
                  
                  const SizedBox(height: 24),
                  
                  TextButton(
                    onPressed: () => HomePage.homeKey.currentState?.switchToExplore(),
                    child: Text(
                      'BACK TO MAP',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionIndicator(String label, bool granted) {
    return Column(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: granted ? const Color(0xFF4ADE80) : Colors.orange,
            boxShadow: [
              BoxShadow(
                color: (granted ? const Color(0xFF4ADE80) : Colors.orange).withOpacity(0.4),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    );
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

/// Mutable placement record used by the AR label layout pass to resolve
/// collisions between overlapping cards. preferredX/Y come from bearing +
/// distance; final values are set once the greedy bumper finds an unoccupied
/// slot. A null finalY means the placement was dropped (pushed off-screen).
class _ArLabelPlacement {
  final _ArLandmark landmark;
  final double bearing;
  final double preferredX;
  final double preferredY;
  double? finalX;
  double? finalY;

  _ArLabelPlacement({
    required this.landmark,
    required this.bearing,
    required this.preferredX,
    required this.preferredY,
  });
}

/// Vertical dotted "drop" line under each AR label, anchoring it to a ground
/// point so the user reads the label as belonging to a specific spot below.
class _DottedDropLinePainter extends CustomPainter {
  final Color color;
  _DottedDropLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const double dotR = 1.4;
    const double step = 6;
    final cx = size.width / 2;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawCircle(Offset(cx, y), dotR, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedDropLinePainter old) => old.color != color;
}

/// Minimal compass needle (red north / white south) used in the top HUD.
class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      r - 1,
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // North half (red, points up)
    final northPath = Path()
      ..moveTo(cx, cy - r + 3)
      ..lineTo(cx - 3, cy)
      ..lineTo(cx + 3, cy)
      ..close();
    canvas.drawPath(northPath, Paint()..color = const Color(0xFFE53935));

    // South half (white)
    final southPath = Path()
      ..moveTo(cx, cy + r - 3)
      ..lineTo(cx - 3, cy)
      ..lineTo(cx + 3, cy)
      ..close();
    canvas.drawPath(southPath, Paint()..color = Colors.white);

    // Center pin
    canvas.drawCircle(Offset(cx, cy), 1.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom painter for dotted vertical line (used in AR place markers)
class _DottedLinePainter extends CustomPainter {
  final Color color;
  final double dashHeight;
  final double dashSpace;
  final double dashWidth;

  _DottedLinePainter({
    required this.color,
    required this.dashHeight,
    required this.dashSpace,
    required this.dashWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashWidth
      ..strokeCap = StrokeCap.round;

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  final List<String> tags;

  const _ArLandmark(this.name, this.imagePath, this.rating, this.distance, this.bearing, this.description, this.category, [this.distanceM = 0, this.lat, this.lng, this.tags = const []]);

  _ArLandmark copyWith({
    String? distance,
    double? bearing,
    double? distanceM,
  }) {
    return _ArLandmark(
      name,
      imagePath,
      rating,
      distance ?? this.distance,
      bearing ?? this.bearing,
      description,
      category,
      distanceM ?? this.distanceM,
      lat,
      lng,
      tags,
    );
  }
}

/// Draws a single chevron/arrow shape pointing upward.
/// Used in the AR navigation overlay to show walking direction.
class _ChevronPainter extends CustomPainter {
  final Color color;
  final double glowIntensity;

  _ChevronPainter({required this.color, this.glowIntensity = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Chevron path — a wide "V" shape pointing upward
    final path = Path()
      ..moveTo(w * 0.1, h * 0.85)   // bottom-left
      ..lineTo(w * 0.5, h * 0.15)   // top-center (tip)
      ..lineTo(w * 0.9, h * 0.85)   // bottom-right
      ..lineTo(w * 0.75, h * 0.85)  // inner-right
      ..lineTo(w * 0.5, h * 0.40)   // inner-top
      ..lineTo(w * 0.25, h * 0.85)  // inner-left
      ..close();

    // Glow shadow
    if (glowIntensity > 0.5) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.3 * glowIntensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawPath(path, glowPaint);
    }

    // Main fill with gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.95),
        color.withOpacity(0.4),
      ],
    );
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // White edge highlight
    final edgePaint = Paint()
      ..color = Colors.white.withOpacity(0.5 * glowIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, edgePaint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) =>
      old.color != color || old.glowIntensity != glowIntensity;
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

extension _ArCameraNavigation on _ArCameraPageState {
  Widget _buildNavigationBubble(_ArLandmark landmark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.5), blurRadius: 20),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 24),
              const SizedBox(height: 8),
              Text(
                landmark.name.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                landmark.distance,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -10, end: 10, duration: 2.seconds, curve: Curves.easeInOut),
        
        // Animated line to ground
        Container(
          width: 2,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF00E5FF), const Color(0xFF00E5FF).withOpacity(0)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationRow() {
    final name = _resolveDisplayLocation();
    final canPick = _locationCandidates.length > 1;

    // Hide row if there is an active selected place info card so it doesn't float above it
    final hasActivePlaceCard = _isNavigating || _showInfoCard || (_isIdentifying && (_frozenLandmark ?? _getPointedLandmark()) != null);
    if (hasActivePlaceCard) {
      return const SizedBox.shrink();
    }
    const rowBottom = 36.0;

    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + rowBottom,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Home Button
          _buildHomeButton(),

          // Location Pill (Center)
          GestureDetector(
            onTap: () {
              debugPrint('📍 [Location Pill] Tap registered! canPick: $canPick');
              if (canPick) _showLocationPicker();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E88E5).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Your Location',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Color(0xFF1E88E5), size: 16),
                  ),
                ],
              ),
            ),
          ),

          // Maps Button
          _buildMapsButton(),
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
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/neva_avatar.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback icon if asset doesn't load or exist yet
            return const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF));
          },
        ),
      ),
    );
  }

  Widget _buildArSearchBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 74,
      left: 16,
      right: 16,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Search any place to navigate...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w500),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          updateState(() {
                            _searchResults = [];
                            _showSearchResults = false;
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (val) {
                _performArSearch(val);
              },
              onSubmitted: (val) {
                _performArSearch(val);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArSearchResultsOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 124,
      left: 16,
      right: 16,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Color(0xFF00E5FF),
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _searchResults.length,
                    separatorBuilder: (context, index) => Divider(
                      color: Colors.white.withOpacity(0.08),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final place = _searchResults[index];
                      final distanceM = place.distanceM ?? 0.0;
                      final distanceText = distanceM < 1000
                          ? '${distanceM.toInt()} m'
                          : '${(distanceM / 1000).toStringAsFixed(1)} km';
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.place_rounded,
                          color: Color(0xFF00E5FF),
                          size: 18,
                        ),
                        title: Text(
                          place.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: place.address != null
                            ? Text(
                                place.address!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Text(
                          distanceText,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10,
                          ),
                        ),
                        onTap: () {
                          final pos = _currentPosition;
                          final bearing = pos != null
                              ? _calculateBearing(pos.latitude, pos.longitude, place.latitude, place.longitude)
                              : 0.0;
                          final landmark = _ArLandmark(
                            place.name,
                            place.photoUrls.isNotEmpty
                                ? place.photoUrls.first
                                : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop',
                            place.rating,
                            distanceText,
                            bearing,
                            place.description ?? 'A remarkable location nearby!',
                            place.categoryName?.toUpperCase() ?? 'ATTRACTION',
                            distanceM,
                            place.latitude,
                            place.longitude,
                          );

                          updateState(() {
                            if (!_landmarks.any((l) => l.name == landmark.name)) {
                              _landmarks.add(landmark);
                            }
                            _selectedLandmark = _landmarks.indexWhere((l) => l.name == landmark.name);
                            _showInfoCard = true;
                            _showSearchResults = false;
                            _searchController.text = place.name;
                          });
                          FocusScope.of(context).unfocus();
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
