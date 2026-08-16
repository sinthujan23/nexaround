import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

/// Fetches public client SDK keys (Mapbox, Google Maps) from the backend and
/// applies them to the relevant SDKs. Safe to call multiple times — subsequent
/// calls simply refresh the keys.
///
/// Called in two places:
///   1. `main()` — eagerly, so the map tiles load before the user navigates.
///   2. After successful authentication — as a retry, in case the first attempt
///      failed (e.g. backend was cold-starting, network was briefly offline).
class ConfigKeyService {
  ConfigKeyService._();

  /// Whether we have already successfully applied the Mapbox token at least
  /// once during this app session. Avoids redundant `setAccessToken` calls.
  static bool _mapboxTokenApplied = false;

  /// Returns `true` if keys were fetched and applied successfully.
  static Future<bool> fetchAndApplyKeys() async {
    try {
      final response = await http
          .get(Uri.parse(
              '${ApiConstants.baseUrl}${ApiConstants.apiVersion}/config/keys'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('ConfigKeyService: backend returned ${response.statusCode}');
        return false;
      }

      final data = jsonDecode(response.body);

      // ── Mapbox ────────────────────────────────────────────────────────
      final mapboxToken = data['mapbox_access_token'];
      if (mapboxToken != null &&
          mapboxToken is String &&
          mapboxToken.isNotEmpty) {
        ApiConstants.mapboxAccessToken = mapboxToken;
        MapboxOptions.setAccessToken(mapboxToken);
        _mapboxTokenApplied = true;
        debugPrint('ConfigKeyService: Mapbox token applied ✓');
      }

      // ── SerpApi ───────────────────────────────────────────────────────
      final serpKey = data['serp_api_key'];
      if (serpKey != null && serpKey is String && serpKey.isNotEmpty) {
        ApiConstants.serpApiKey = serpKey;
      }

      // ── Google Maps ───────────────────────────────────────────────────
      final googleMapsKey = data['google_maps_api_key'];
      if (googleMapsKey != null &&
          googleMapsKey is String &&
          googleMapsKey.isNotEmpty) {
        ApiConstants.googleMapsApiKey = googleMapsKey;
        // Pass the key to iOS native side so GMSServices.provideAPIKey is called.
        try {
          const platform = MethodChannel('com.nexaround.app/keys');
          await platform
              .invokeMethod('setGoogleMapsKey', {'key': googleMapsKey});
          debugPrint(
              'ConfigKeyService: Google Maps key applied on native side ✓');
        } catch (e) {
          debugPrint(
              'ConfigKeyService: Failed to set Google Maps key on native side: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('ConfigKeyService: Failed to fetch keys – $e');
      return false;
    }
  }

  /// Whether the Mapbox access token has been successfully applied at least
  /// once. Useful for widgets that want to guard against rendering a map before
  /// the token is ready.
  static bool get isMapboxReady => _mapboxTokenApplied;
}
