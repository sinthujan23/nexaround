import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static SharedPreferences? _prefsOrNull;
  static SharedPreferences get _prefs => _prefsOrNull!;

  /// Idempotent — safe to call again from the FCM background isolate, which has
  /// its own memory and must initialise SharedPreferences separately.
  static Future<void> init() async {
    _prefsOrNull ??= await SharedPreferences.getInstance();
  }

  /// Re-read from disk so the main isolate picks up values written by the FCM
  /// background isolate (e.g. notifications saved while the app was backgrounded).
  static Future<void> reload() async {
    await _prefsOrNull?.reload();
    notificationsNotifier.value++;
  }

  // Global State for Background Discovery Engine
  static final ValueNotifier<String?> discoveryResultNotifier = ValueNotifier(null);
  static final ValueNotifier<bool> isDiscoveringNotifier = ValueNotifier(false);

  // Global State for Location Override (Search)
  static double? overriddenLatitude;
  static double? overriddenLongitude;

  // Onboarding
  static bool isFirstTime() {
    return _prefs.getBool('first_time') ?? true;
  }

  static Future<void> setOnboardingComplete() async {
    await _prefs.setBool('first_time', false);
  }

  // Auth Session
  static bool isLoggedIn() {
    return _prefs.getBool('is_logged_in') ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool('is_logged_in', value);
  }

  // Permission Request Flags
  static bool hasRequestedCamera() {
    return _prefs.getBool('has_requested_camera') ?? false;
  }

  static Future<void> setRequestedCamera() async {
    await _prefs.setBool('has_requested_camera', true);
  }

  static bool hasRequestedLocation() {
    return _prefs.getBool('has_requested_location') ?? false;
  }

  static Future<void> setRequestedLocation() async {
    await _prefs.setBool('has_requested_location', true);
  }

  // Essential Details (Example: User Data)
  static Future<void> saveUserData(String key, String value) async {
    await _prefs.setString(key, value);
  }

  static String? getUserData(String key) {
    return _prefs.getString(key);
  }

  // Vision / AR Cache
  static Future<void> cacheVisionResult(String key, String jsonValue) async {
    await _prefs.setString('vision_cache_$key', jsonValue);
    await _prefs.setInt('vision_cache_time_$key', DateTime.now().millisecondsSinceEpoch);
  }

  static String? getCachedVisionResult(String key) {
    // Optional: Add expiration check (e.g., 1 hour)
    final timestamp = _prefs.getInt('vision_cache_time_$key') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // If cache is older than 30 minutes, ignore it for fresh discovery
    if (now - timestamp > 1800000) return null;
    
    return _prefs.getString('vision_cache_$key');
  }

  // Saved Places
  static final ValueNotifier<int> savedPlacesNotifier = ValueNotifier(0);

  static List<String> getSavedPlaceJsons() {
    return _prefs.getStringList('saved_places_data') ?? [];
  }

  static bool isPlaceSaved(String placeId) {
    final List<String> current = getSavedPlaceJsons();
    return current.any((jsonStr) {
      try {
        final data = json.decode(jsonStr);
        return data['id'] == placeId || data['name'] == placeId;
      } catch (_) {
        return false;
      }
    });
  }

  static Future<void> toggleSavedPlace(Map<String, dynamic> placeData) async {
    final List<String> current = getSavedPlaceJsons();
    final String placeId = placeData['id']?.toString() ?? placeData['name']?.toString() ?? '';
    
    int index = -1;
    for (int i = 0; i < current.length; i++) {
      try {
        final decoded = json.decode(current[i]);
        if (decoded['id'] == placeId || decoded['name'] == placeId) {
          index = i;
          break;
        }
      } catch (_) {}
    }

    if (index != -1) {
      current.removeAt(index);
    } else {
      current.add(json.encode(placeData));
    }
    await _prefs.setStringList('saved_places_data', current);
    savedPlacesNotifier.value++;
  }

  // Favorite / Pinned Places (Heart)
  static final ValueNotifier<int> favoritePlacesNotifier = ValueNotifier(0);

  static List<String> getFavoritePlaceJsons() {
    return _prefs.getStringList('favorite_places_data') ?? [];
  }

  static bool isPlaceFavorite(String placeId) {
    final List<String> current = getFavoritePlaceJsons();
    return current.any((jsonStr) {
      try {
        final data = json.decode(jsonStr);
        return data['id'] == placeId || data['name'] == placeId;
      } catch (_) {
        return false;
      }
    });
  }

  static Future<void> toggleFavoritePlace(Map<String, dynamic> placeData) async {
    final List<String> current = getFavoritePlaceJsons();
    final String placeId = placeData['id']?.toString() ?? placeData['name']?.toString() ?? '';
    
    int index = -1;
    for (int i = 0; i < current.length; i++) {
      try {
        final decoded = json.decode(current[i]);
        if (decoded['id'] == placeId || decoded['name'] == placeId) {
          index = i;
          break;
        }
      } catch (_) {}
    }

    if (index != -1) {
      current.removeAt(index);
    } else {
      current.add(json.encode(placeData));
    }
    await _prefs.setStringList('favorite_places_data', current);
    favoritePlacesNotifier.value++;
  }

  // Attractions Caching
  static Future<void> cacheAttractions(List<Map<String, dynamic>> placesJson) async {
    final List<String> list = placesJson.map((p) => json.encode(p)).toList();
    await _prefs.setStringList('cached_attractions_list', list);
  }

  static Future<void> mergeAndCacheAttractions(List<Map<String, dynamic>> placesJson) async {
    final existing = getCachedAttractions();
    final List<Map<String, dynamic>> merged = List.from(existing);
    for (final newItem in placesJson) {
      if (!merged.any((item) => item['name'] == newItem['name'] || item['id'] == newItem['id'])) {
        merged.add(newItem);
      }
    }
    // Limit to 500 entries to prevent infinite growth
    if (merged.length > 500) {
      merged.removeRange(0, merged.length - 500);
    }
    await cacheAttractions(merged);
  }

  static List<Map<String, dynamic>> getCachedAttractions() {
    final List<String> list = _prefs.getStringList('cached_attractions_list') ?? [];
    return list.map((str) => json.decode(str) as Map<String, dynamic>).toList();
  }

  // Currency Caching (24 hours expiry)
  static Future<void> cacheCurrencyRates(String baseCurrency, Map<String, double> rates) async {
    await _prefs.setString('currency_cache_$baseCurrency', json.encode(rates));
    await _prefs.setInt('currency_cache_time_$baseCurrency', DateTime.now().millisecondsSinceEpoch);
  }

  static Map<String, double>? getCachedCurrencyRates(String baseCurrency) {
    final timestamp = _prefs.getInt('currency_cache_time_$baseCurrency') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 24 hours in milliseconds = 24 * 60 * 60 * 1000 = 86,400,000
    if (now - timestamp > 86400000) return null;
    
    final jsonStr = _prefs.getString('currency_cache_$baseCurrency');
    if (jsonStr == null) return null;
    
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (_) {
      return null;
    }
  }

  // ── Explorer stats (gamification) ──────────────────────────────────────
  // Local XP / places-visited counters powering the profile's "Explorer Level"
  // and "Places Visited". Bumped by completing a Mini Tour. Level is derived
  // from XP so the two never drift apart.
  static const int xpPerLevel = 100;
  static final ValueNotifier<int> statsNotifier = ValueNotifier(0);

  static int getExplorerXp() => _prefs.getInt('explorer_xp') ?? 0;
  static int getPlacesVisited() => _prefs.getInt('places_visited') ?? 0;

  static int explorerLevelForXp(int xp) => 1 + (xp ~/ xpPerLevel);
  static int getExplorerLevel() => explorerLevelForXp(getExplorerXp());

  /// XP earned inside the current level, 0..[xpPerLevel].
  static int getXpIntoLevel() => getExplorerXp() % xpPerLevel;

  /// Record a completed exploration. Returns true if the explorer level rose.
  static Future<bool> addExploration({required int placesVisited, required int xp}) async {
    final beforeLevel = getExplorerLevel();
    await _prefs.setInt('explorer_xp', getExplorerXp() + xp);
    await _prefs.setInt('places_visited', getPlacesVisited() + placesVisited);
    statsNotifier.value++;
    return getExplorerLevel() > beforeLevel;
  }

  // ── Mini Tour history ──────────────────────────────────────────────────
  // Completed mini tours are kept locally (there's no backend table for them).
  // Newest first. Each record: {area, places:[..], xp, date(ISO)}.
  static final ValueNotifier<int> historyNotifier = ValueNotifier(0);

  static Future<void> addMiniTourHistory({
    required String area,
    required List<String> placeNames,
    required int xp,
  }) async {
    final list = _prefs.getStringList('mini_tour_history') ?? [];
    list.insert(
      0,
      json.encode({
        'area': area,
        'places': placeNames,
        'xp': xp,
        'date': DateTime.now().toIso8601String(),
      }),
    );
    await _prefs.setStringList('mini_tour_history', list);
    historyNotifier.value++;
  }

  static List<Map<String, dynamic>> getMiniTourHistory() {
    final list = _prefs.getStringList('mini_tour_history') ?? [];
    return list
        .map((s) {
          try {
            return json.decode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  // ── Odyssey list cache ─────────────────────────────────────────────────
  // Caches the raw itinerary JSON for Odysseys so Blueprints renders instantly
  // on open and survives a slow/failed network (no spinner / retry screen).
  static Future<void> cacheOdysseys(List<Map<String, dynamic>> raw) async {
    await _prefs.setStringList(
      'odysseys_cache',
      raw.map((e) => json.encode(e)).toList(),
    );
  }

  static List<Map<String, dynamic>> getCachedOdysseysRaw() {
    final list = _prefs.getStringList('odysseys_cache') ?? [];
    return list
        .map((s) {
          try {
            return json.decode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  // ── Museum list cache ──────────────────────────────────────────────────
  static Future<void> cacheMuseums(List<Map<String, dynamic>> raw) async {
    await _prefs.setStringList(
      'museums_cache',
      raw.map((e) => json.encode(e)).toList(),
    );
  }

  static List<Map<String, dynamic>> getCachedMuseumsRaw() {
    final list = _prefs.getStringList('museums_cache') ?? [];
    return list
        .map((s) {
          try {
            return json.decode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  // ── Museum itinerary cache ─────────────────────────────────────────────
  static Future<void> cacheItinerary(
      String slug, String duration, Map<String, dynamic> raw) async {
    await _prefs.setString('itinerary_cache_${slug}_$duration', json.encode(raw));
  }

  static Map<String, dynamic>? getCachedItineraryRaw(String slug, String duration) {
    final str = _prefs.getString('itinerary_cache_${slug}_$duration');
    if (str == null) return null;
    try {
      return json.decode(str) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Notifications (bell inbox) ─────────────────────────────────────────
  // Locally-stored inbox shown by the homepage bell. Fed by FCM messages
  // (foreground + on-tap). Each record: {title, body, type, data, date, read}.
  static final ValueNotifier<int> notificationsNotifier = ValueNotifier(0);

  static Future<void> addNotification({
    required String title,
    required String body,
    String type = '',
    String? id,
    Map<String, dynamic>? data,
  }) async {
    // Re-read first: the same notification may have been written by the
    // background isolate already.
    await _prefsOrNull?.reload();
    final list = _prefs.getStringList('notifications') ?? [];
    // Dedup by message id so background + foreground + tap don't triple-add.
    if (id != null && id.isNotEmpty) {
      for (final s in list) {
        try {
          if ((json.decode(s) as Map)['id'] == id) return;
        } catch (_) {}
      }
    }
    list.insert(
      0,
      json.encode({
        'id': id ?? '',
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'date': DateTime.now().toIso8601String(),
        'read': false,
      }),
    );
    if (list.length > 50) list.removeRange(50, list.length);
    await _prefs.setStringList('notifications', list);
    notificationsNotifier.value++;
  }

  static List<Map<String, dynamic>> getNotifications() {
    final list = _prefs.getStringList('notifications') ?? [];
    return list
        .map((s) {
          try {
            return json.decode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static int unreadNotifications() =>
      getNotifications().where((n) => n['read'] != true).length;

  static Future<void> markNotificationsRead() async {
    final list = getNotifications();
    for (final n in list) {
      n['read'] = true;
    }
    await _prefs.setStringList(
      'notifications',
      list.map((n) => json.encode(n)).toList(),
    );
    notificationsNotifier.value++;
  }

  static Future<void> clearNotifications() async {
    await _prefs.remove('notifications');
    notificationsNotifier.value++;
  }

  static bool areNotificationsEnabled() {
    return _prefs.getBool('notifications_enabled') ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    await _prefs.setBool('notifications_enabled', value);
  }

  // User Preferences Local Storage
  static Future<void> saveUserPreferences(Map<String, dynamic> preferences) async {
    await _prefs.setString('user_preferences_json', json.encode(preferences));
  }

  static Map<String, dynamic> getUserPreferences() {
    final str = _prefs.getString('user_preferences_json');
    if (str == null) return {};
    try {
      return json.decode(str) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // Coordinates caching for nearby places to avoid redundant api queries
  static Future<void> saveLastFetchCoords(double lat, double lng) async {
    await _prefs.setDouble('last_fetch_lat', lat);
    await _prefs.setDouble('last_fetch_lng', lng);
  }

  static double? getLastFetchLat() {
    return _prefs.getDouble('last_fetch_lat');
  }

  static double? getLastFetchLng() {
    return _prefs.getDouble('last_fetch_lng');
  }

  static Future<void> clearLastFetchCoords() async {
    await _prefs.remove('last_fetch_lat');
    await _prefs.remove('last_fetch_lng');
  }

  // Hybrid Places Caching (Expires after 24 hours)
  static Future<void> cacheHybridPlaces(String locationName, String categoryName, List<Map<String, dynamic>> placesJson) async {
    final key = 'hybrid_places_v2_${locationName.replaceAll(' ', '_')}_$categoryName';
    await _prefs.setString(key, json.encode(placesJson));
    await _prefs.setInt('${key}_time', DateTime.now().millisecondsSinceEpoch);
  }

  static List<Map<String, dynamic>>? getCachedHybridPlaces(String locationName, String categoryName) {
    final key = 'hybrid_places_v2_${locationName.replaceAll(' ', '_')}_$categoryName';
    final timestamp = _prefs.getInt('${key}_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 24 hours expiry (86,400,000 milliseconds)
    if (now - timestamp > 86400000) return null;
    
    final jsonStr = _prefs.getString(key);
    if (jsonStr == null) return null;
    try {
      final decoded = json.decode(jsonStr) as List<dynamic>;
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return null;
    }
  }

  // Get all cached hybrid places for a category across all locations within 24 hours
  static List<Map<String, dynamic>> getAllCachedHybridPlacesForCategory(String categoryName) {
    final List<Map<String, dynamic>> allPlaces = [];
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('hybrid_places_v2_') && key.endsWith('_$categoryName') && !key.endsWith('_time')) {
        final timestamp = _prefs.getInt('${key}_time') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // 24 hours expiry (86,400,000 milliseconds)
        if (now - timestamp <= 86400000) {
          final jsonStr = _prefs.getString(key);
          if (jsonStr != null) {
            try {
              final decoded = json.decode(jsonStr) as List<dynamic>;
              allPlaces.addAll(decoded.map((e) => e as Map<String, dynamic>));
            } catch (_) {}
          }
        }
      }
    }
    
    // Deduplicate by place ID to avoid duplicate results from overlapping searches
    final Map<String, Map<String, dynamic>> unique = {};
    for (final p in allPlaces) {
      final id = p['id'] as String?;
      if (id != null) {
        unique[id] = p;
      }
    }
    return unique.values.toList();
  }

  static Future<void> clearHybridPlacesCache() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('hybrid_places_v2_')) {
        await _prefs.remove(key);
      }
    }
  }



  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}

