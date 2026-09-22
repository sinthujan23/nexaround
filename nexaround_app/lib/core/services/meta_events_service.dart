import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

/// Service responsible for logging Meta (Facebook) App Events for install tracking,
/// campaign attribution, and engagement analytics.
///
/// Automatically tracks app launch / install on startup and provides structured methods
/// for tracking travel & exploration events. Fire-and-forget; analytics errors never block the UI.
class MetaEventsService {
  MetaEventsService._();
  static final MetaEventsService instance = MetaEventsService._();

  final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();
  bool _initialized = false;

  /// Initialize Meta App Events SDK on startup.
  /// Automatically enables auto-logging and logs app activation.
  Future<void> init() async {
    if (_initialized) return;

    // Facebook App Events SDK is supported on Android and iOS
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      // Enable automatic app events (installs, opens, in-app purchases)
      await _facebookAppEvents.setAutoLogAppEventsEnabled(true);

      // Enable advertiser tracking for iOS (works in conjunction with ATT)
      await _facebookAppEvents.setAdvertiserTracking(enabled: true);

      // Log app launch / activation (used by Meta for install attribution)
      await _facebookAppEvents.logActivatedApp();

      _initialized = true;
      debugPrint('[MetaEventsService] Initialized and app activation logged.');
    } catch (e) {
      // Best-effort: Analytics must never crash or block the application
      debugPrint('[MetaEventsService] Initialization failed: $e');
    }
  }

  /// Log a custom event with optional parameters.
  Future<void> logEvent(String name, [Map<String, dynamic>? parameters]) async {
    try {
      await _facebookAppEvents.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('[MetaEventsService] Failed to log event $name: $e');
    }
  }

  /// Log when a user successfully registers / creates an account.
  Future<void> logCompletedRegistration({String registrationMethod = 'email'}) async {
    try {
      await _facebookAppEvents.logCompletedRegistration(
        registrationMethod: registrationMethod,
      );
    } catch (e) {
      debugPrint('[MetaEventsService] Failed to log registration: $e');
    }
  }

  /// Log when a user scans a landmark using AR / camera vision.
  Future<void> logLandmarkScanned(String landmarkName, {String? category}) async {
    await logEvent('landmark_scanned', {
      'landmark_name': landmarkName,
      if (category != null) 'category': category,
    });
  }

  /// Log when a user starts an audio tour or itinerary guide.
  Future<void> logTourStarted(String tourName, {int? stopCount}) async {
    await logEvent('tour_started', {
      'tour_name': tourName,
      if (stopCount != null) 'stop_count': stopCount,
    });
  }

  /// Log when a user creates or saves a trip itinerary.
  Future<void> logItineraryCreated(String destination, {int? days}) async {
    await logEvent('itinerary_created', {
      'destination': destination,
      if (days != null) 'duration_days': days,
    });
  }

  /// Log in-app purchase or ticket booking.
  Future<void> logPurchase({
    required double amount,
    String currency = 'USD',
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _facebookAppEvents.logPurchase(
        amount: amount,
        currency: currency,
        parameters: parameters,
      );
    } catch (e) {
      debugPrint('[MetaEventsService] Failed to log purchase: $e');
    }
  }

  /// Set user ID to attribute events to an authenticated user.
  Future<void> setUserId(String userId) async {
    try {
      await _facebookAppEvents.setUserID(userId);
    } catch (e) {
      debugPrint('[MetaEventsService] Failed to set user ID: $e');
    }
  }

  /// Clear user ID upon logout.
  Future<void> clearUserId() async {
    try {
      await _facebookAppEvents.clearUserID();
    } catch (e) {
      debugPrint('[MetaEventsService] Failed to clear user ID: $e');
    }
  }
}
