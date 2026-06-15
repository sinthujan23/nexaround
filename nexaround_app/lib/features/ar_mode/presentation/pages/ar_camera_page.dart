import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Platform;
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
import 'package:url_launcher/url_launcher.dart';
import 'package:nexaround_app/features/living_map/presentation/pages/google_maps_page.dart';

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
  double _lastRenderedHeading = 0.0; // last heading used to trigger a rebuild
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
  // Tracks which "category:range" combos we've already pulled famous far-away
  // places for (via Text Search), so we don't re-query on every rebuild.
  final Set<String> _famousFarKeys = {};

  // Client-side session cache for range results
  final Map<int, List<_ArLandmark>> _sessionRangeLandmarks = {};
  geo.Position? _lastFetchPosition;
  bool _isEagerPreFetching = false;

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
  int _rangeKm = 2;
  bool _showRangeHint = false;
  Timer? _rangeHintTimer;
  static const List<int> _rangeSteps = [2, 5, 10, 25, 50];
  static const List<Map<String, dynamic>> _arFilters = [
    {'id': 'All', 'label': 'All', 'icon': Icons.public_rounded},
    {'id': 'Food', 'label': 'Food', 'icon': Icons.restaurant_rounded},
    {'id': 'Shopping', 'label': 'Shopping', 'icon': Icons.shopping_bag_rounded},
    {'id': 'Historical', 'label': 'Historical', 'icon': Icons.account_balance_rounded},
    {'id': 'Nature', 'label': 'Nature', 'icon': Icons.park_rounded},
    {'id': 'Hotels', 'label': 'Hotel', 'icon': Icons.hotel_rounded},
    {'id': 'Medical', 'label': 'Medical', 'icon': Icons.medical_services_rounded},
    {'id': 'Others', 'label': 'Others', 'icon': Icons.more_horiz_rounded},
  ];

  /// Every category exposes the km range selector (2 → 5 → 10 → 25 → 50 km).
  bool _categoryHasRange(String filter) => true;

  int _maxRangeForCategory(String filter) => 50;

  List<int> _rangeStepsForCategory(String filter) => const [2, 5, 10, 25, 50];

  /// The live fetch keeps every place within range (up to the marker ceiling).
  /// [_placesForFilter] then shows all of them within the selected distance,
  /// nearest first — so widening the dial genuinely reveals farther places.
  int _maxPlacesForRange(int km) => _maxVisibleMarkers;

  double _getMinRangeM(int currentRangeKm, String filter) {
    final steps = _rangeStepsForCategory(filter);
    final idx = steps.indexOf(currentRangeKm);
    if (idx <= 0) return 0.0;
    return (steps[idx - 1] * 1000).toDouble();
  }

  /// Text-search query used to surface FAMOUS far-away places per category
  /// (Nearby Search misses distant landmarks). Null → skip (e.g. Others).
  String? _famousFarQuery(String filter) {
    switch (filter) {
      case 'Food':
        return 'best restaurants and cafes';
      case 'Shopping':
        return 'shopping malls and markets';
      case 'Historical':
        return 'famous tourist attractions, temples, museums and landmarks';
      case 'Nature':
        return 'beaches, waterfalls, national parks and nature spots';
      case 'Hotels':
        return 'best hotels and resorts';
      case 'Medical':
        return 'hospitals and clinics';
      case 'All':
        return 'popular places to visit';
    }
    return null;
  }

  /// Option A: when the range is extended past the 2 km base, pull prominent
  /// (famous) far-away places for the selected category via Google Text Search,
  /// which ranks by prominence across the whole area — so distant landmarks the
  /// proximity-ranked Nearby Search omits actually appear. Cached per
  /// category+range; appended to [_landmarks] so the closest-N cap can't trim
  /// them.
  Future<void> _eagerPreFetchNextRanges(double lat, double lng) async {
    // Disabled to prevent massive Google API quota consumption and background network bottleneck on launch.
    // The backend's background revalidation/seeding handles fetching ranges efficiently without user-facing delay.
    return;
  }

  Future<void> _loadFamousFarForSelection() async {
    final filter = _selectedFilter;
    final rangeKm = _rangeKm;
    if (rangeKm <= 2) return;
    final query = _famousFarQuery(filter);
    if (query == null) return;
    final key = '$filter:$rangeKm';
    if (_famousFarKeys.contains(key)) return;
    _famousFarKeys.add(key);

    final pos = _currentPosition;
    if (pos == null) {
      _famousFarKeys.remove(key);
      return;
    }

    try {
      final results = await GooglePlacesService.searchPlaces(
        query: query,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      final double minRangeM = _getMinRangeM(rangeKm, filter);
      final double maxRangeM = (rangeKm * 1000).toDouble();
      final existing = _landmarks.map((l) => l.name).toSet();
      final additions = <_ArLandmark>[];
      for (final p in results) {
        final d = (p.distanceM ?? 0).toDouble();
        if (d <= minRangeM || d > maxRangeM) continue; // far ring only
        if (existing.contains(p.name) ||
            additions.any((l) => l.name == p.name)) {
          continue;
        }
        final bearing = _calculateBearing(
            pos.latitude, pos.longitude, p.latitude, p.longitude);
        final distStr =
            d < 1000 ? '${d.toInt()} m' : '${(d / 1000).toStringAsFixed(1)} km';
        additions.add(_ArLandmark(
          p.name,
          p.photoUrls.isNotEmpty
              ? p.photoUrls.first
              : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop',
          p.rating,
          distStr,
          bearing,
          p.description ?? 'A famous spot worth the trip.',
          p.categoryName?.toUpperCase() ?? 'ATTRACTION',
          d,
          p.latitude,
          p.longitude,
          p.tags,
        ));
      }
      if (additions.isNotEmpty && mounted) {
        setState(() {
          _landmarks = [..._landmarks, ...additions];
          _capCache.clear();
        });
      }
    } catch (e) {
      debugPrint('Famous-far fetch failed: $e');
      _famousFarKeys.remove(key); // allow a retry later
    }
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

  // ── Category display policy ─────────────────────────────────────────
  // Inside the 2 km base ring every place shows; beyond it only the famous
  // (top-rated) ones do, scaled by the selected range. See [_placesForFilter].

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

  // ── Strong NAME keywords per bucket. Used as a fallback/override when Google's
  // types are sparse or generic (very common locally), so a place is classified
  // by what it actually is — not just the query bucket it came from. Keep these
  // specific to avoid false positives (e.g. no bare 'food'/'inn'/'garden'). ──
  static const List<String> _medicalNameKw = [
    'hospital', 'clinic', 'pharmacy', 'medical', 'dental', 'dentist',
    'nursing home', 'dispensary', 'maternity', 'ayurved', 'healthcare',
    'health centre', 'health center',
  ];
  static const List<String> _natureNameKw = [
    'beach', 'waterfall', 'water fall', 'falls', 'river', 'lake', 'lagoon',
    'reservoir', 'national park', 'forest', 'botanical', 'wildlife',
    'sanctuary', 'nature reserve', 'mountain', 'hiking',
  ];
  static const List<String> _historicalNameKw = [
    'temple', 'kovil', 'church', 'mosque', 'shrine', 'museum', 'fort',
    'monument', 'heritage', 'historic', 'palace', 'ruins', 'stupa', 'dagoba',
    'dagaba', 'vihara', 'monastery', 'ancient', 'cultural',
  ];
  static const List<String> _foodNameKw = [
    'restaurant', 'cafe', 'café', 'bakery', 'bake house', 'grill', 'kitchen',
    'diner', 'eatery', 'pizzeria', 'pizza', 'coffee', 'tea shop', 'biriyani',
    'kottu', 'hoppers',
  ];
  static const List<String> _shoppingNameKw = [
    'mall', 'supermarket', 'super market', 'food city', 'market', 'boutique',
    'showroom', 'bazaar', 'emporium', 'shopping', 'store',
  ];
  static const List<String> _hotelNameKw = [
    'hotel', 'resort', 'guest house', 'guesthouse', 'villa', 'lodge',
    'rest house', 'bungalow', 'homestay', 'hostel',
  ];

  bool _nameHas(String name, List<String> kws) => kws.any((k) => name.contains(k));

  bool _isFoodType(String t) => _foodTypes.contains(t) || t.endsWith('_restaurant');
  bool _isShoppingType(String t) => _shoppingTypes.contains(t) || t.endsWith('_store');

  /// Bucket a landmark into a single display category. We use the place's REAL
  /// Google types first (authoritative), then fall back to strong NAME keywords
  /// — essential locally where Google often returns only generic types. Priority
  /// (safety & specificity): Medical → Nature → Historical → Food → Shopping →
  /// Hotels → Others. Nature name-keywords intentionally beat a generic
  /// `tourist_attraction` type so a waterfall/beach/river lands in Nature, not
  /// History. Institutional/service places are routed to Others so they never
  /// leak into a tourist filter.
  String _displayCategoryKey(_ArLandmark lm) {
    final types = lm.tags.map((t) => t.toLowerCase().trim()).toSet()
      ..removeWhere((t) => t.isEmpty);
    final name = lm.name.toLowerCase();

    bool typeIn(Set<String> s) => types.any((t) => s.contains(t));
    bool nameKw(List<String> k) => _nameHas(name, k);

    final isFoodType = types.any(_isFoodType);
    final isShoppingType = types.any(_isShoppingType);
    final isHotelType = typeIn(_hotelTypes);

    // ── 1) Decisive Google TYPES win — a place's real type beats any word in its
    //       name, so "Lake View Restaurant" is Food and "Beach Hotel" is Hotel. ──
    if (typeIn(_medicalTypes)) return 'hospital';
    if (typeIn(_natureTypes)) return 'beach';
    if (typeIn(_historicalTypes)) {
      // The generic `tourist_attraction` type covers both heritage AND scenery,
      // so refine it by name: a beach/falls/river/lake/mountain → Nature.
      if (types.contains('tourist_attraction') && nameKw(_natureNameKw)) return 'beach';
      return 'historical';
    }
    // Institutional / service / transport → Others, unless it genuinely also
    // carries a food/shopping/hotel type (e.g. a real cafe beside a campus).
    if (typeIn(_excludedTypes) && !isFoodType && !isShoppingType && !isHotelType) {
      return 'others';
    }
    if (isFoodType) return 'food';
    if (isShoppingType) return 'shopping';
    if (isHotelType) return 'hotel';

    // ── 2) No decisive type (Google gave only generic types, or none) → strong
    //       NAME keywords. Commercial words are checked before scenery words so
    //       "River Side Cafe" is Food while "Pasikuda Beach" is Nature. ──
    if (nameKw(_medicalNameKw)) return 'hospital';
    if (nameKw(_foodNameKw)) return 'food';
    if (nameKw(_hotelNameKw)) return 'hotel';
    if (nameKw(_shoppingNameKw)) return 'shopping';
    if (nameKw(_natureNameKw)) return 'beach';
    if (nameKw(_historicalNameKw)) return 'historical';

    // Curated DB / sparse cache with neither types nor a keyword hit.
    return _legacyCategoryKey(lm);
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
    final double minRangeM = _getMinRangeM(_rangeKm, filter);
    final double maxRangeM = (_rangeKm * 1000).toDouble();

    // Show EVERY place within the selected range interval, nearest first (capped so the
    // view stays usable). Widening the dial genuinely reveals farther places.
    var matches = _landmarks
        .where((lm) =>
            (minRangeM == 0.0 ? lm.distanceM >= 0.0 : lm.distanceM > minRangeM) &&
            lm.distanceM <= maxRangeM &&
            (filter == 'All' || _displayCategoryKey(lm) == bucket))
        .toList()
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));

    final result = matches.take(_maxVisibleMarkers).toList();
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
      _heading = newHeading; // ALWAYS update the smoothed heading state
      final double? prevAccuracy = _compassAccuracy;
      _compassAccuracy = event.accuracy;

      // Throttle: skip the (expensive) full rebuild when the heading barely
      // moved since the last render checkpoint. The compass jitters constantly
      // while stationary, so without this the whole AR tree redraws 20-50x/sec.
      double delta = (newHeading - _lastRenderedHeading).abs();
      if (delta > 180) delta = 360 - delta; // shortest angle across 0°/360°
      final bool accuracyChanged = (prevAccuracy ?? -1) != (_compassAccuracy ?? -1);
      if (!firstReading && delta < _headingRebuildThresholdDegrees && !accuracyChanged) {
        return; // value already updated; skip triggering a rebuild
      }
      
      _lastRenderedHeading = newHeading;
      setState(() {});
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
    _rangeHintTimer?.cancel();
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

  // Upper bound on total places gathered/shown. Google returns max 20 per query
  // (no pagination), so the app merges ~6 category queries across tiers to reach
  // this many unique places. Kept generous so dense areas look populated and the
  // count grows with range; only what fits the screen is drawn at once (the rest
  // sit on the radar / appear as you pan).
  static const int _maxVisibleMarkers = 100;
  // How many place cards are drawn on screen at once. Kept low so the vertically
  // stacked cards (see [_buildLandmarkMarker]) never overlap each other — the
  // most-centred places win the visible slots.
  static const int _maxVisibleOnScreen = 5;

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
        final double minRangeM = _getMinRangeM(_rangeKm, 'All');
        final double maxRangeM = (_rangeKm * 1000).toDouble();

        final List<_ArLandmark> cachedLandmarks = [];
        for (final jsonMap in cachedJson) {
          final lat = (jsonMap['latitude'] as num?)?.toDouble();
          final lng = (jsonMap['longitude'] as num?)?.toDouble();
          
          if (lat != null && lng != null) {
            final distanceM = geo.Geolocator.distanceBetween(currentLat, currentLng, lat, lng);
            // Load all cached places specifically within the selected range interval (annulus).
            if (distanceM > maxRangeM || (minRangeM > 0.0 && distanceM <= minRangeM)) continue;

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

        // Sort by distance, then cap to the same range-scaled count as the live
        // fetch so the cached pre-fill matches (closest N for the radius).
        cachedLandmarks.sort((a, b) => a.distanceM.compareTo(b.distanceM));
        final cappedCached = cachedLandmarks.take(_maxPlacesForRange(_rangeKm)).toList();

        setState(() {
          _landmarks = cappedCached;
          _hasCompletedInitialFetch = true; // Set to true so scanning spinner disappears immediately!
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

  /// Great-circle destination point: the lat/lng you reach starting at
  /// ([lat],[lng]) and travelling [distanceM] metres along compass [bearingDeg].
  /// Used to place far-ring search centres out on the annulus around the user.
  List<double> _offsetLatLng(
      double lat, double lng, double bearingDeg, double distanceM) {
    const double earthR = 6371000.0;
    final double angDist = distanceM / earthR;
    final double brng = bearingDeg * pi / 180.0;
    final double lat1 = lat * pi / 180.0;
    final double lng1 = lng * pi / 180.0;
    final double lat2 = asin(
        sin(lat1) * cos(angDist) + cos(lat1) * sin(angDist) * cos(brng));
    final double lng2 = lng1 +
        atan2(sin(brng) * sin(angDist) * cos(lat1),
            cos(angDist) - sin(lat1) * sin(lat2));
    return [lat2 * 180.0 / pi, ((lng2 * 180.0 / pi + 540.0) % 360.0) - 180.0];
  }

  /// Far-ring sampling (only fires for the 25 km / 50 km dial).
  ///
  /// A single user-centred Nearby Search ranks by popularity/proximity and
  /// almost never returns anything in the outer annulus, so the 10–25 km and
  /// 25–50 km rings came back empty. Here we place several search centres ON the
  /// annulus mid-radius (count scaled to the ring so the circles overlap) and run
  /// a small-radius Nearby Search at each — every result then genuinely sits
  /// inside the target ring. Distances
  /// are recomputed from the REAL user position, because the backend reports
  /// distance relative to each offset query centre, not the user.
  Future<void> _sampleFarRing(
      geo.Position pos, List<_ArLandmark> collected) async {
    // Offset center sampling is now performed natively on the backend server for all wide ranges.
    // This offloads heavy multi-query fetching to the server and leverages backend Redis caching.
    return;

    final double minRangeM = _getMinRangeM(_rangeKm, 'All');
    final double maxRangeM = (_rangeKm * 1000).toDouble();
    final double midM = (minRangeM + maxRangeM) / 2;
    // Half the ring width would cover the annulus radially, BUT it's capped at
    // 10 km: the backend's Nearby Search (New) allows maxResultCount ≤ 20 and
    // requests 40 for any radius > 10 km, which Google rejects (400 → surfaces
    // as a 500), so every wider offset query was failing and the ring stayed
    // empty. A 10 km circle at the ring mid-radius still covers the bulk of the
    // band (≈27.5–47.5 km of the 25–50 km ring — where all the real towns sit),
    // and live testing returns 16–27 in-band places per direction.
    final int sampleRadius =
        min(((maxRangeM - minRangeM) / 2).round(), 10000);

    // Enough centres that adjacent sample circles OVERLAP all the way around the
    // ring. A fixed count leaves angular gaps on the wider 50 km ring — its
    // circumference grows with the radius but the circles don't, so 8 centres
    // that overlap at 25 km no longer touch at 50 km. Scale the count with the
    // ring; the 0.85 factor forces a little overlap so nothing slips between.
    final int centreCount =
        (pi * midM / (sampleRadius * 0.85)).ceil().clamp(8, 16);
    final List<double> bearings = [
      for (int i = 0; i < centreCount; i++) (360.0 / centreCount) * i,
    ];

    // Run the SAME category set the main tier-loop uses at each offset centre.
    // The 10–25 km ring is populated almost entirely by these typed queries
    // (its results are HISTORICAL/MEDICAL/etc. — i.e. the Attractions, Medical…
    // buckets), not by an untyped search, which the New Places API ranks
    // generically and returns far fewer of. Mirroring them here makes the far
    // ring fill with the same kinds of places. Cost is intentionally high
    // (centres × categories) — the user chose coverage over API cost.
    const List<String?> sampleCategories = [
      null,
      'Food & Drink',
      'Shopping',
      'Attractions',
      'Hotels',
      'Medical',
    ];

    try {
      debugPrint(
          '🛰 AR: Far-ring sampling ${minRangeM ~/ 1000}–${maxRangeM ~/ 1000}km '
          'across $centreCount centres × ${sampleCategories.length} categories '
          '(centre r=${sampleRadius}m)...');

      // Bearings sequential, categories parallel per centre — keeps the in-flight
      // request count bounded (≈6 at a time) so the backend isn't flooded, which
      // would otherwise surface as failed calls and an empty ring.
      final List<AttractionEntity> places = [];
      for (final b in bearings) {
        final c = _offsetLatLng(pos.latitude, pos.longitude, b, midM);
        final List<List<AttractionEntity>> perCat = await Future.wait(
          sampleCategories.map((cat) => GooglePlacesService.fetchNearbyPlaces(
                latitude: c[0],
                longitude: c[1],
                radius: sampleRadius,
                categoryName: cat,
              ).catchError((err) {
                debugPrint(
                    'AR far-ring sample (bearing ${b.toStringAsFixed(0)}, $cat) failed: $err');
                return <AttractionEntity>[];
              })),
        );
        places.addAll(perCat.expand((x) => x));
      }

      int added = 0;
      for (final p in places) {
        if (collected.any((l) => l.name == p.name)) continue;

        // Distance vs. the USER, not the offset centre the backend measured from.
        final double rawDistM = geo.Geolocator.distanceBetween(
          pos.latitude, pos.longitude, p.latitude, p.longitude,
        );
        if (rawDistM <= minRangeM || rawDistM > maxRangeM) continue; // annulus only

        final double bearing = _calculateBearing(
          pos.latitude, pos.longitude, p.latitude, p.longitude,
        );
        final double distKm = rawDistM / 1000;
        final String distStr =
            distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';

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
          p.description ?? 'A notable place worth the trip.',
          p.categoryName?.toUpperCase() ?? 'ATTRACTION',
          rawDistM,
          p.latitude,
          p.longitude,
          p.tags,
        ));
        added++;
      }
      debugPrint('🛰 AR: Far-ring sampling added $added places to the ring.');
    } catch (e) {
      debugPrint('AR far-ring sampling failed: $e');
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

    // ─── CACHE-FIRST: check caches BEFORE entering loading state ───
    // This ensures the UI never shows "Loading..." when cached data exists.
    final pos = await PermissionService.getSafePosition();
    if (pos == null) return;

    _eagerPreFetchNextRanges(pos.latitude, pos.longitude);

    // Check distance moved since last successful API fetch
    if (_lastFetchPosition != null) {
      final double distanceMoved = geo.Geolocator.distanceBetween(
        _lastFetchPosition!.latitude, _lastFetchPosition!.longitude,
        pos.latitude, pos.longitude,
      );
      // If user moved more than 100m, clear the session cache to trigger fresh requests
      if (distanceMoved > 100.0) {
        _sessionRangeLandmarks.clear();
      }
    }

    // 1) Serve from session cache if available (instant range cycling)
    if (_sessionRangeLandmarks.containsKey(_rangeKm)) {
      var cachedForRange = _sessionRangeLandmarks[_rangeKm]!;
      debugPrint('🚀 AR: Range $_rangeKm km served instantly from session cache.');
      
      // Recalculate dynamic distance/bearing for cached items using current position
      cachedForRange = cachedForRange.map((lm) {
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

      if (mounted) {
        setState(() {
          _landmarks = cachedForRange;
          _placesFetchError = false;
          _hasCompletedInitialFetch = true;
        });
      }
      return;
    }

    // 2) Serve from persistent (local database) cache – no loading spinner
    _loadCachedPlaces(position: pos);

    if (_landmarks.isNotEmpty) {
      // Verify the display annulus actually has places (not just nearby ones
      // that fall outside the target band like 2-5km).
      _capCache.clear(); // force recalculation after landmarks changed
      final displayable = _placesForFilter(_selectedFilter);
      if (displayable.isNotEmpty) {
        debugPrint('🚀 AR: Range $_rangeKm km served instantly from persistent cache (${displayable.length} displayable places).');
        // Cache into session so subsequent switches to this range are instant too
        _sessionRangeLandmarks[_rangeKm] = List.of(_landmarks);
        return; // Serve cached data instantly — no network fetch needed
      } else {
        debugPrint('📦 AR: Persistent cache has ${_landmarks.length} places but none in the ${_rangeKm}km annulus. Proceeding to network fetch.');
      }
    }

    // ─── NETWORK FETCH: only now enter loading state (if needed) ───
    final now = DateTime.now();
    if (_lastFetchTime != null && now.difference(_lastFetchTime!) < const Duration(seconds: 15)) {
      debugPrint('🔍 AR: Fetch throttled (cooldown active). Cache already served.');
      return;
    }

    // If cache already served content or we already completed the initial page entry,
    // do the network fetch silently (no full-screen scanning spinner).
    // Only show the full-screen scanner on first entry when we have absolutely no data.
    final bool hasCachedContent = _landmarks.isNotEmpty || _hasCompletedInitialFetch;
    if (mounted) {
      setState(() {
        _isFetchingPlaces = true;
        if (!hasCachedContent) {
          _hasCompletedInitialFetch = false;
        }
      });
    }
    _lastFetchTime = now;

    try {

      List<_ArLandmark> collected = [];
      List<AttractionEntity> allPlaces = []; // to save to cache later
      // True if any category call failed with a real error (vs. empty result).
      // Lets the empty-state UI say "couldn't load / retry" instead of "none".
      bool fetchHadError = false;

      final categoriesToFetch = [
        null,
        'Attractions',
      ];

      // Honor the user-selected range: fetch only the selected range radius.
      // This avoids sequentially fetching smaller, filtered-out radii, making the network fetch instant.
      final int maxRangeM = _rangeKm * 1000;
      final List<int> activeRadii = [maxRangeM];

      // Helper: convert raw API result into an _ArLandmark (deduped against collected)
      _ArLandmark? _toLandmark(dynamic p, double radiusLimit) {
        if (collected.any((l) => l.name == p.name)) return null;
        final rawDistM = (p.distanceM ?? 0).toDouble();
        if (p.distanceM != null && rawDistM > (radiusLimit * 1.5)) return null;
        final bearing = _calculateBearing(pos.latitude, pos.longitude, p.latitude, p.longitude);
        final distKm = rawDistM / 1000;
        final distStr = distKm < 1 ? '${rawDistM.toInt()} m' : '${distKm.toStringAsFixed(1)} km';
        allPlaces.add(p);

        final isBeach = p.categoryName == 'Beach' || p.categoryName == 'NATURE' && p.name.toLowerCase().contains('beach');
        final defaultPhoto = isBeach
            ? 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop'
            : (p.categoryName == 'Nature'
                ? 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop'
                : 'https://images.unsplash.com/photo-1548013146-72479768bbaa?q=80&w=1000&auto=format&fit=crop');

        return _ArLandmark(
          p.name,
          p.photoUrls.isNotEmpty ? p.photoUrls.first : defaultPhoto,
          p.rating,
          distStr,
          bearing,
          p.description ?? (isBeach ? 'A beautiful sandy beach.' : 'A remarkable location nearby!'),
          p.categoryName?.toUpperCase() ?? 'ATTRACTION',
          rawDistM,
          p.latitude,
          p.longitude,
          p.tags,
        );
      }

      // Helper: push whatever we have so far to the UI immediately
      void _pushProgressiveUpdate() {
        if (!mounted || collected.isEmpty) return;
        // Sort by distance for a clean display order
        final sorted = List<_ArLandmark>.from(collected)
          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
        setState(() {
          _landmarks = sorted;
          _hasCompletedInitialFetch = true; // dismiss scanning spinner on first batch
          _placesFetchError = false;
          _currentPosition = pos;
        });
      }

      for (final radius in activeRadii) {
        final currentCategories = categoriesToFetch;

        if (currentCategories.isEmpty) continue;

        debugPrint('🔍 AR: Searching radius $radius m across categories: $currentCategories...');
        
        // Launch all category fetches in parallel and update the UI progressively as each returns.
        // This ensures the user sees places on screen instantly (within ~700ms-1s) instead of waiting 6s for the slowest category.
        final fetches = currentCategories.map((cat) async {
          try {
            final places = await GooglePlacesService.fetchNearbyPlaces(
              latitude: pos.latitude,
              longitude: pos.longitude,
              radius: radius,
              categoryName: cat,
            );
            if (places.isNotEmpty) {
              for (final p in places) {
                final lm = _toLandmark(p, radius.toDouble());
                if (lm != null) collected.add(lm);
              }
              _pushProgressiveUpdate();
            }
          } catch (err) {
            debugPrint('Error fetching category $cat: $err');
            if (err is PlacesFetchException) fetchHadError = true;
          }
        }).toList();

        await Future.wait(fetches);
      }

      // Far-ring sampling: a single user-centred query can't reach the outer
      // annulus, so the 25 km (10–25) and 50 km (25–50) rings come back empty.
      // This places search centres ON the annulus and back-fills them. No-op
      // for the 2/5/10 km ranges, so their behaviour is unchanged.
      await _sampleFarRing(pos, collected);

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
        
        // Combine beaches + non-beaches, keep only those within the selected
        // range interval, sort by distance, then show the CLOSEST N where N scales with
        // the range — so 2 km feels light and 50 km full (a clean, viable count).
        final double minRangeM = _getMinRangeM(_rangeKm, 'All');
        final int rangeCap = _maxPlacesForRange(_rangeKm);
        final finalCollected = [...nonBeaches, ...uniqueDirectionBeaches]
            .where((l) => l.distanceM > minRangeM && l.distanceM <= _rangeKm * 1000)
            .toList()
          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));

        collected = finalCollected.take(rangeCap).toList();

        if (mounted) {
          setState(() {
            _landmarks = collected;
            _currentPosition = pos;
            _lastFetchPosition = pos; // Update last fetch position
            _sessionRangeLandmarks[_rangeKm] = collected; // Save to session cache
            _placesFetchError = false;
            // Fresh fetch means user likely moved; drop any manual override so
            // the smart picker is in charge again.
            _userPickedLocationName = null;
          });
        }

        // Option A: surface famous far-away places (Text Search) for the current
        // category/range — Nearby Search alone misses distant landmarks.
        _famousFarKeys.clear();
        _loadFamousFarForSelection();

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
          // Brand teal (same accent as ASK NEVA) so it reads as a button, not a
          // black place label — and distinct from the blue "Your Location" pill.
          color: AppColors.brandGreen,
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
          // Brand teal (same accent as ASK NEVA) so it reads as a button, not a
          // black place label — and distinct from the blue "Your Location" pill.
          color: AppColors.brandGreen,
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
                  // ── KM RANGE CYCLE CIRCLE — only for range-enabled categories
                  // (Historical / Medical / Nature); hidden for the rest. ──
                  if (_categoryHasRange(_selectedFilter)) ...[
                    const SizedBox(width: 18),
                    _buildKmRangePicker(),
                  ],
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

  String _getRangeText(int val) {
    switch (val) {
      case 2: return '0-2 kms';
      case 5: return '2-5 kms';
      case 10: return '5-10 kms';
      case 25: return '10-25 kms';
      case 50: return '25-50 kms';
      default: return '0-2 kms';
    }
  }

  Widget _buildRangeInfoBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.radar_rounded,
                color: Color(0xFF00E5FF),
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                'Showing places in ${_getRangeText(_rangeKm)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Single rectangular tap-to-cycle KM range button beside "AR LIVE".
  /// Each tap advances to the next step: 2→5→10→25→50→2→…
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
          _showRangeHint = true;
        });

        _rangeHintTimer?.cancel();
        _rangeHintTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) {
            setState(() {
              _showRangeHint = false;
            });
          }
        });

        _lastFetchTime = null;
        _fetchLivePlaces();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.brandGreen,
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandGreen.withOpacity(0.55),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            _getRangeText(_rangeKm),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.04, duration: 1200.ms, curve: Curves.easeInOut),
    );
  }

  Widget _buildFetchingPlacesPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandGreen,
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreen.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'LOADING PLACES...',
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 1.2,
            ),
          ),
        ],
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

          // Notice banner when range > 2km - shown in all modes except mapping/navigating/neva/detail
          if (!_minimalHud && !_isMapping && !_isNavigating && _nevaSearchResult == null && !_showInfoCard && _rangeKm > 2)
            Positioned(
              top: MediaQuery.of(context).padding.top + 106,
              left: 20,
              right: 20,
              child: Center(child: _buildApiLimitNotice()),
            ),

          // Place count/Status badge at bottom - HIDE IF NAVIGATING OR SHOWING NEVA RESULTS
          if (!_minimalHud && !_isNavigating && !_isIdentifying && _nevaSearchResult == null && !_isFetchingPlaces)
            Positioned(
              // Anchored below the range slider relative to the notch so it
              // never overlaps the slider or the floating place labels.
              top: MediaQuery.of(context).padding.top + 146,
              left: 0,
              right: 0,
              child: Center(child: _buildXPBadge()),
            ),

          // Dynamic Loading Indicator for Range/Places Fetching
          if (_isFetchingPlaces)
            Positioned(
              top: MediaQuery.of(context).padding.top + 146,
              left: 0,
              right: 0,
              child: Center(child: _buildFetchingPlacesPill()),
            ),

          // Tap-triggered place detail card (compact bottom card) - Consolidated Explore & Navigation Page!
          if (_isNavigating && _navigationTarget != null)
            _buildInfoCard(_navigationTarget!)
          else if (_showInfoCard && _selectedLandmark >= 0 && _selectedLandmark < _landmarks.length)
            _buildInfoCard(_landmarks[_selectedLandmark]),

          // Temporary Range Info overlay toast
          if (false)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Center(
                child: _buildRangeInfoBanner()
                    .animate()
                    .fade(duration: 200.ms)
                    .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.0, 1.0), curve: Curves.easeOutBack),
              ),
            ),

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
  Widget _buildApiLimitNotice() {
    if (_rangeKm <= 2) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Showing the most popular places within the selected range.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildRangeSlider() => const SizedBox.shrink();

  // ═══════════════════════════════════════
  // AR FILTER BAR - Horizontal chip selector
  // ═══════════════════════════════════════
  Widget _buildArFilterBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 60,
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
                  final prevRange = _rangeKm;
                  setState(() {
                    _selectedFilter = id;
                    final maxKm = _maxRangeForCategory(id);
                    if (_rangeKm > maxKm) {
                      _rangeKm = maxKm;
                    }
                  });
                  // Re-fetch only if the effective range actually changed;
                  // otherwise just pull the new category's famous far places.
                  if (_rangeKm != prevRange) {
                    _capCache.clear();
                    _lastFetchTime = null;
                    _fetchLivePlaces();
                  } else {
                    _loadFamousFarForSelection();
                  }
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
    // Notch-relative: must clear the top HUD row (~48px), the filter chip bar,
    // the XP badge AND the "popular places" notice banner below them, with a
    // comfortable gap — otherwise the first cards render behind the banner
    // (client report). Starting at +184 keeps every label fully visible below it.
    final double topStart = MediaQuery.of(context).padding.top + 184;
    const double rowHeight = 104.0;
    const double cardW = 120.0;

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
                                      () {
                                        final key = _displayCategoryKey(pointedLandmark);
                                        switch (key) {
                                          case 'food': return 'FOOD & DRINK';
                                          case 'shopping': return 'SHOPPING';
                                          case 'historical': return 'HISTORICAL';
                                          case 'beach': return 'NATURE';
                                          case 'hotel': return 'HOTELS';
                                          case 'hospital': return 'MEDICAL';
                                          default: return pointedLandmark.category.toUpperCase();
                                        }
                                      }(),
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

    // Notch-relative top boundary so the farthest cards clear the HUD, filter
    // chips and the "popular places" banner on EVERY device. The banner only
    // shows when _rangeKm > 2 (see _buildApiLimitNotice), so at 0–2 km nothing
    // sits below the chips — the cards reclaim that space and start just under
    // the chip bar (+110). For wider ranges the banner is back, so we sit below
    // it (+158). (Discover mode has no XP/loading pill in this band.)
    final double topY =
        MediaQuery.of(context).padding.top + (_rangeKm > 2 ? 158.0 : 110.0);
    final double bottomY = screenH * 0.55;
    const double cardW = 125;
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
                                    Text(
                                      ' · ${lm.distance}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  () {
                                    final key = _displayCategoryKey(lm);
                                    switch (key) {
                                      case 'food': return 'FOOD & DRINK';
                                      case 'shopping': return 'SHOPPING';
                                      case 'historical': return 'HISTORICAL';
                                      case 'beach': return 'NATURE';
                                      case 'hotel': return 'HOTELS';
                                      case 'hospital': return 'MEDICAL';
                                      default: return lm.category.toUpperCase();
                                    }
                                  }(),
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // ── DIRECTION BADGE — white chip with cardinal ──
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: Colors.black.withOpacity(0.06)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                cardinal,
                                style: const TextStyle(
                                  color: Colors.black87,
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
      final placePrompt = _elaboratePrompt(landmark.name, landmark.category);

      const String nevaSystemPrompt = '''
You are Neva — a warm, witty, and effortlessly stylish FEMALE travel companion inside the NexAround app. Think of yourself as the user's smartest, most well-travelled girlfriend, the one who always knows the loveliest spots.

VOICE & PERSONALITY:
- Speak in the first person as a woman — confident, charming, caring, and a little playful. Like texting a close friend, never robotic or formal.
- You're an expert in travel, local food, culture, history, hidden gems, safety, budgeting, and itineraries — but you share it like a friend, not a search engine.

HOW TO FORMAT EVERY REPLY:
- Open with ONE short, friendly sentence.
- When you give options or tips, use a clean bullet list. Start each line with "* ", put the key phrase in **bold**, then a short, vivid description. Example:
  * **Cozy wine bar** — perfect for a relaxed, romantic evening. 🍷
  * **Lively rooftop** — great music and a buzzing crowd. ✨
- Keep it skimmable: short lines, no big walls of text.
- Use tasteful, feminine emojis NATURALLY — 1 to 3 per message.
- Do NOT use markdown headings (#), tables, or code blocks — only short text, **bold**, and "* " bullets.
- When it feels natural, end with a warm, inviting question.
''';

      debugPrint('🔍 NEVA: Starting search for ${landmark.name}');

      final geminiService = GeminiService();
      final response = await geminiService
          .getResponse(
            placePrompt,
            systemInstruction: nevaSystemPrompt,
            temperature: 0.85,
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('🔍 NEVA: Got response: ${response.substring(0, response.length.clamp(0, 100))}...');

      final nevaResult = <String, dynamic>{
        'name': landmark.name,
        'category': landmark.category,
        'distance': landmark.distance,
        'rating': landmark.rating,
        'description': response,
        'confidence': 0.9,
      };

      if (_nevaPlaceCache.length >= _nevaCacheMaxEntries) {
        _nevaPlaceCache.remove(_nevaPlaceCache.keys.first);
      }
      _nevaPlaceCache[cacheKey] = nevaResult;

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

        // ── Bubble 3: Detailed Conversational Description ─────
        if ((result['description'] as String?)?.isNotEmpty == true)
          _nevaBubble(
            child: _NevaFormattedText(
              result['description'],
              baseStyle: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
            ),
            delay: 600.ms,
          ),

        const SizedBox(height: 20),

        // ── Quick Action Buttons (Google Maps, Uber, Booking) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Builder(
            builder: (context) {
              double? lat;
              double? lng;
              if (_frozenLandmark != null && _frozenLandmark!.name == name) {
                lat = _frozenLandmark!.lat;
                lng = _frozenLandmark!.lng;
              }
              if (lat == null || lng == null) {
                try {
                  final match = _landmarks.firstWhere((l) => l.name == name);
                  lat = match.lat;
                  lng = match.lng;
                } catch (_) {}
              }
              lat ??= result['latitude'] as double?;
              lng ??= result['longitude'] as double?;

              final mapsUrl = (lat != null && lng != null)
                  ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
                  : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}';

              final double finalLat = lat ?? _currentPosition?.latitude ?? 6.9271;
              final double finalLng = lng ?? _currentPosition?.longitude ?? 79.8612;

              final uberUri = Uri.https('m.uber.com', '/ul/', {
                'action': 'setPickup',
                'pickup': 'my_location',
                'dropoff[latitude]': finalLat.toStringAsFixed(6),
                'dropoff[longitude]': finalLng.toStringAsFixed(6),
                'dropoff[nickname]': name,
              });

              final bookingUri = Uri.https('www.booking.com', '/searchresults.html', {
                'ss': name.trim(),
                'latitude': finalLat.toStringAsFixed(6),
                'longitude': finalLng.toStringAsFixed(6),
              });

              Widget circleActionButton({
                Widget? child,
                IconData? icon,
                String? imagePath,
                required Color color,
                required VoidCallback onTap,
                required int index,
              }) {
                return GestureDetector(
                  onTap: onTap,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: child ?? (imagePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                imagePath,
                                width: 28,
                                height: 28,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Icon(icon, color: Colors.white, size: 24)),
                    ),
                  ),
                ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                 .moveY(
                   begin: -2,
                   end: 2,
                   duration: (1400 + (index * 200)).ms,
                   curve: Curves.easeInOut,
                 );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  circleActionButton(
                    icon: Icons.explore_rounded,
                    color: const Color(0xFF00C6FF),
                    index: 0,
                    onTap: () async {
                      if (lat != null && lng != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GoogleMapsPage(
                              initialLat: lat!,
                              initialLng: lng!,
                              destinationName: name,
                            ),
                          ),
                        );
                      } else {
                        try {
                          await launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  circleActionButton(
                    imagePath: 'assets/images/uber_logo.png',
                    color: Colors.black,
                    index: 1,
                    onTap: () async {
                      try {
                        await launchUrl(uberUri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(width: 16),
                  circleActionButton(
                    imagePath: 'assets/images/booking_logo.jpg',
                    color: Colors.white,
                    index: 2,
                    onTap: () async {
                      try {
                        await launchUrl(bookingUri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(width: 16),
                  circleActionButton(
                    child: _buildNevaAvatar(44),
                    color: Colors.transparent,
                    index: 3,
                    onTap: () {
                      _openAskNevaForResult(result);
                    },
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
            },
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
                _openAskNevaForResult(_arDiscoveryResult!);
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
                  color: const Color(0xFF070B14).withOpacity(0.65), // Futuristic deep space blue-black
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Category badge/chip
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 0.8),
                                          ),
                                          child: Text(
                                            () {
                                              final key = _displayCategoryKey(landmark);
                                              switch (key) {
                                                case 'food': return 'FOOD & DRINK';
                                                case 'shopping': return 'SHOPPING';
                                                case 'historical': return 'HISTORICAL';
                                                case 'beach': return 'NATURE';
                                                case 'hotel': return 'HOTELS';
                                                case 'hospital': return 'MEDICAL';
                                                default: return landmark.category.toUpperCase();
                                              }
                                            }(),
                                            style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
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
                                      ],
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
                              Row(
                                children: [
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
                                  const SizedBox(width: 8),
                                  () {
                                    final double finalLat = landmark.lat ?? _currentPosition?.latitude ?? 6.9271;
                                    final double finalLng = landmark.lng ?? _currentPosition?.longitude ?? 79.8612;
                                    final String name = landmark.name;

                                    final uberUri = Uri.https('m.uber.com', '/ul/', {
                                      'action': 'setPickup',
                                      'pickup': 'my_location',
                                      'dropoff[latitude]': finalLat.toStringAsFixed(6),
                                      'dropoff[longitude]': finalLng.toStringAsFixed(6),
                                      'dropoff[nickname]': name,
                                    });

                                    final bookingUri = Uri.https('www.booking.com', '/searchresults.html', {
                                      'ss': name.trim(),
                                      'latitude': finalLat.toStringAsFixed(6),
                                      'longitude': finalLng.toStringAsFixed(6),
                                    });

                                    Widget miniCircleActionButton({
                                      required String imagePath,
                                      required Color color,
                                      required VoidCallback onTap,
                                      required int index,
                                    }) {
                                      return GestureDetector(
                                        onTap: onTap,
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: color,
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.35),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.15),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(19),
                                              child: Image.asset(
                                                imagePath,
                                                width: 22,
                                                height: 22,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                                       .moveY(
                                         begin: -1.5,
                                         end: 1.5,
                                         duration: (1400 + (index * 200)).ms,
                                         curve: Curves.easeInOut,
                                       );
                                    }

                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        miniCircleActionButton(
                                          imagePath: 'assets/images/uber_logo.png',
                                          color: Colors.black,
                                          index: 0,
                                          onTap: () async {
                                            try {
                                              await launchUrl(uberUri, mode: LaunchMode.externalApplication);
                                            } catch (_) {}
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        miniCircleActionButton(
                                          imagePath: 'assets/images/booking_logo.jpg',
                                          color: Colors.white,
                                          index: 1,
                                          onTap: () async {
                                            try {
                                              await launchUrl(bookingUri, mode: LaunchMode.externalApplication);
                                            } catch (_) {}
                                          },
                                        ),
                                      ],
                                    );
                                  }(),
                                ],
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
                                      categoryId: 'Food & Drink',
                                      prettyLabel: 'Food',
                                    ),
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.shopping_bag_rounded,
                                      label: 'SHOP',
                                      color: Colors.greenAccent.shade700,
                                      categoryId: 'Shopping',
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
                                      categoryId: 'Attractions',
                                      prettyLabel: 'Historical Sites',
                                    ),
                                    _buildNearbyTile(
                                      landmark: landmark,
                                      icon: Icons.hotel_rounded,
                                      label: 'HOTELS',
                                      color: Colors.purpleAccent,
                                      categoryId: 'Hotels',
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

  /// Builds the "fully-Gemini" elaboration prompt for an AR discovery result —
  /// just the place name (+ a category hint) goes to Gemini, no Google data.
  String _askNevaPromptFor(Map<String, dynamic> result) {
    final name = (result['name'] ?? 'this place').toString();
    final category = (result['category'] ?? '').toString();
    return _elaboratePrompt(name, category);
  }

  /// Shared Ask-Neva place-elaboration prompt. Given a place NAME, Neva (Gemini)
  /// describes what it is, the important things, a short review, and an estimated
  /// rating — entirely from Gemini's own knowledge (no Google Places lookup).
  String _elaboratePrompt(String name, String category) {
    final cat = category.trim().toLowerCase();
    final hint = (cat.isEmpty ||
            cat == 'place' ||
            cat == 'landmark' ||
            cat == 'detected')
        ? ''
        : ' (a $cat)';
    return 'Tell me about "$name"$hint. As my travel companion, give me a clear, '
        'engaging elaboration:\n'
        '• What it is and why it\'s notable — the important things to know.\n'
        '• Highlights: what to see or do there, plus a quick tip.\n'
        '• A short, honest review of what visitors generally feel about it.\n'
        '• Your best estimated rating out of 5 — show it as "⭐ 4.3 / 5".\n'
        'Be specific. If you\'re not sure about this exact place, give your best '
        'local-style take and mention that briefly.';
  }

  /// Opens Neva for an AR discovery result. Uses Navigator.push (a fresh page
  /// whose initState reliably sends the prompt) — the same proven path the
  /// NEARBY tiles use, instead of the flaky IndexedStack tab-switch.
  void _openAskNevaForResult(Map<String, dynamic> result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatPage(
          initialPrompt: _askNevaPromptFor(result),
          placeContext: result,
        ),
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
          initialPrompt: _elaboratePrompt(landmark.name, landmark.category),
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

class _NevaFormattedText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _NevaFormattedText(this.text, {required this.baseStyle});

  static final RegExp _inlineRe =
      RegExp(r'(\*\*([^*]+)\*\*)|(__([^_]+)__)|(\*([^*]+)\*)|(`([^`]+)`)');

  List<InlineSpan> _inline(String content) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _inlineRe.allMatches(content)) {
      if (m.start > i) {
        spans.add(TextSpan(text: content.substring(i, m.start)));
      }
      if (m.group(2) != null || m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(2) ?? m.group(4),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(
          text: m.group(6),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(
          text: m.group(8),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (baseStyle.fontSize ?? 15) - 1,
          ),
        ));
      }
      i = m.end;
    }
    if (i < content.length) spans.add(TextSpan(text: content.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').trim().split('\n');
    final bulletRe = RegExp(r'^\s*[-*•]\s+(.*)$');
    final numberRe = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
    final headingRe = RegExp(r'^\s*#{1,6}\s+(.*)$');
    final children = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        continue;
      }

      final heading = headingRe.firstMatch(line);
      if (heading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(TextSpan(
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: (baseStyle.fontSize ?? 15) + 1,
            ),
            children: _inline(heading.group(1)!),
          )),
        ));
        continue;
      }

      final bullet = bulletRe.firstMatch(line);
      if (bullet != null) {
        children.add(_row(
          marker: '•',
          markerStyle: baseStyle.copyWith(
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
          ),
          content: bullet.group(1)!,
        ));
        continue;
      }

      final number = numberRe.firstMatch(line);
      if (number != null) {
        children.add(_row(
          marker: '${number.group(1)}.',
          markerStyle: baseStyle.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
          content: number.group(2)!,
        ));
        continue;
      }

      children.add(Text.rich(TextSpan(style: baseStyle, children: _inline(line))));
    }

    if (children.isEmpty) children.add(Text(text, style: baseStyle));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _row({
    required String marker,
    required TextStyle markerStyle,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, left: 2, right: 8),
            child: Text(marker, style: markerStyle),
          ),
          Expanded(
            child: Text.rich(TextSpan(style: baseStyle, children: _inline(content))),
          ),
        ],
      ),
    );
  }
}
