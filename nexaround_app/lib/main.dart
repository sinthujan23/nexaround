import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nexaround_app/app/app.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/config_key_service.dart';
import 'package:nexaround_app/core/services/connectivity_service.dart';
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/core/services/session_tracker.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/core/network/auth_token_cache.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  // Before the first screen builds: image widgets read the token synchronously
  // to authenticate photo requests, and an unauthenticated one is served from
  // the server's disk cache only.
  await AuthTokenCache.load();

  // Initialize DI
  await configureDependencies();

  // Initialize Cache Service
  await CacheService.init();
  // Clear attractions cache on app startup to force a fresh fetch from Google Places
  await CacheService.cacheAttractions([]);

  // Initialize Hive Local Database for Travel Stories
  await Hive.initFlutter();
  await Hive.openBox('travel_stories_box');

  // Firebase + push notifications (FCM). Non-fatal if it fails so the app
  // still runs without notifications.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Network connectivity monitoring (non-fatal if it fails).
  try {
    await ConnectivityService.instance.init();
  } catch (e) {
    debugPrint('Connectivity service init failed: $e');
  }

  // Fetch public client SDK keys (Mapbox token, Google Maps key) from the
  // backend. This no longer requires authentication so it works at startup.
  await ConfigKeyService.fetchAndApplyKeys();

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
