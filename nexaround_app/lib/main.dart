import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nexaround_app/app/app.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/config_key_service.dart';
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/core/services/session_tracker.dart';
import 'package:nexaround_app/app/di/injection.dart';
import 'package:nexaround_app/core/network/auth_token_cache.dart';
import 'package:nexaround_app/core/services/meta_events_service.dart';
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

  // debugPrint still writes to the platform log channel in release builds.
  // The app makes ~250 of these calls, several on per-GPS-fix and per-compass
  // paths, and each one crosses the Dart/platform boundary. Silence them in
  // release only — debug and profile builds keep every log exactly as before.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Initialize DI
  await configureDependencies();

  // Until runApp draws its first frame the user sees only the blank native
  // launch screen, so await nothing here that the first screens don't read
  // synchronously, and run what is awaited side by side:
  //  - the auth token: image widgets read it to authenticate photo requests,
  //    and an unauthenticated one is served from the server's disk cache only
  //  - CacheService: the router and splash read login and onboarding state
  //  - Hive: travel stories read their box synchronously
  //  - Firebase: quick on its own; the notification setup that needs it is
  //    slow and runs after runApp
  await Future.wait([
    AuthTokenCache.load(),
    CacheService.init(),
    _openLocalDatabase(),
    _initFirebase(),
  ]);

  // Clear attractions cache on app startup to force a fresh fetch from Google Places
  await CacheService.cacheAttractions([]);

  // Fetch public client SDK keys (Mapbox token, Google Maps key) from the
  // backend. A network call of up to 10 s, so not awaited: the splash waits
  // on it before opening any screen that may show a map.
  unawaited(ConfigKeyService.fetchOnLaunch());

  // Start session tracking for real engagement metrics (DAU + avg session).
  SessionTracker.instance.start();

  // Initialize Meta (Facebook) App Events & install tracking.
  MetaEventsService.instance.init();

  // Force dark status bar for futuristic feel
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06060A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const NexAroundApp());

  // Push notifications (FCM): asks for permission, then fetches the device
  // token. That can take seconds — the prompt waits on the user, and iOS
  // waits up to 10 s for the APNs token — so it runs behind the first frame.
  // Non-fatal if Firebase failed: the app still runs without notifications.
  unawaited(NotificationService.instance.init());
}

/// Initialize Hive Local Database for Travel Stories
Future<void> _openLocalDatabase() async {
  await Hive.initFlutter();
  await Hive.openBox('travel_stories_box');
}

/// Non-fatal if it fails, so the app still runs without notifications.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
}
