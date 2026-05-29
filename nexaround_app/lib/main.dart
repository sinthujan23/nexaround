import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/app.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize DI
  await configureDependencies();

  // Initialize Cache Service
  await CacheService.init();

  // Initialize Mapbox with dynamic config fetch from backend
  try {
    final response = await http.get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.apiVersion}/config/keys'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final mapboxToken = data['mapbox_access_token'];
      final googleMapsKey = data['google_maps_api_key'];
      
      if (mapboxToken != null && mapboxToken is String && mapboxToken.isNotEmpty) {
        ApiConstants.mapboxAccessToken = mapboxToken;
        MapboxOptions.setAccessToken(mapboxToken);
      }
      
      if (googleMapsKey != null && googleMapsKey is String && googleMapsKey.isNotEmpty) {
        ApiConstants.googleMapsApiKey = googleMapsKey;
        // Pass Google Maps API Key to iOS native side dynamically
        try {
          const platform = MethodChannel('com.nexaround.app/keys');
          await platform.invokeMethod('setGoogleMapsKey', {'key': googleMapsKey});
          debugPrint('Successfully set Google Maps API Key on iOS native side');
        } catch (e) {
          debugPrint('Failed to set Google Maps API Key on native side: $e');
        }
      }
    }
  } catch (e) {
    debugPrint("Failed to fetch keys from backend: $e");
  }

  // Force dark status bar for futuristic feel
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06060A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const NexAroundApp());
}
