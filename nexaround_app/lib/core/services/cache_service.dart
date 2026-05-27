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

  static Future<void> clearAll() async {
    await _prefs.clear();
  }
}
