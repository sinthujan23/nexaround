import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static late final SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

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
      final data = json.decode(jsonStr);
      return data['id'] == placeId;
    });
  }

  static Future<void> toggleSavedPlace(Map<String, dynamic> placeData) async {
    final List<String> current = getSavedPlaceJsons();
    final String placeId = placeData['id'];
    
    int index = -1;
    for (int i = 0; i < current.length; i++) {
      if (json.decode(current[i])['id'] == placeId) {
        index = i;
        break;
      }
    }

    if (index != -1) {
      current.removeAt(index);
    } else {
      current.add(json.encode(placeData));
    }
    await _prefs.setStringList('saved_places_data', current);
    savedPlacesNotifier.value++;
  }

  // Attractions Caching
  static Future<void> cacheAttractions(List<Map<String, dynamic>> placesJson) async {
    final List<String> list = placesJson.map((p) => json.encode(p)).toList();
    await _prefs.setStringList('cached_attractions_list', list);
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

  // ── Notifications (bell inbox) ─────────────────────────────────────────
  // Locally-stored inbox shown by the homepage bell. Fed by FCM messages
  // (foreground + on-tap). Each record: {title, body, type, data, date, read}.
  static final ValueNotifier<int> notificationsNotifier = ValueNotifier(0);

  static Future<void> addNotification({
    required String title,
    required String body,
    String type = '',
    Map<String, dynamic>? data,
  }) async {
    final list = _prefs.getStringList('notifications') ?? [];
    list.insert(
      0,
      json.encode({
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

  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}
