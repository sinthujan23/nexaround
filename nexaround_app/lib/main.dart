import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nexaround_app/app/app.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/core/services/session_tracker.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

/// Handles FCM messages while the app is backgrounded/terminated. Must be a
/// top-level function and runs in its own isolate. The OS renders the
/// `notification` payload itself; here we also record it into the local inbox
/// so it shows up under the bell when the user opens the app.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await CacheService.init();
    final n = message.notification;
    await CacheService.addNotification(
      id: message.messageId,
      title: (n?.title ?? message.data['title'] ?? 'NexAround').toString(),
      body: (n?.body ?? message.data['body'] ?? '').toString(),
      type: (message.data['type'] ?? '').toString(),
      data: message.data.map((k, v) => MapEntry(k, v)),
    );
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DI
  await configureDependencies();

  // Initialize Cache Service
  await CacheService.init();
  // Clear attractions cache on app startup to force a fresh fetch from Google Places
  await CacheService.cacheAttractions([]);

  // Firebase + push notifications (FCM). Non-fatal if it fails so the app
  // still runs without notifications.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

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

  // Start session tracking for real engagement metrics (DAU + avg session).
  SessionTracker.instance.start();

  // Force dark status bar for futuristic feel
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06060A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const NexAroundApp());
}
