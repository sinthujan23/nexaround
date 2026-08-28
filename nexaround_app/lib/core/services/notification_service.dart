import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';

/// Wraps Firebase Cloud Messaging: asks permission, grabs the device token,
/// registers it with the backend, and funnels incoming messages into the local
/// notification inbox ([CacheService]) that the homepage bell reads.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  String? _token;
  String? _apnsToken;
  bool _initialized = false;
  String debugStatus = 'Initializing...';

  String? get token => _token;
  String? get apnsToken => _apnsToken;

  /// Set by the app shell to route a notification tap (e.g. open Blueprints).
  void Function(Map<String, dynamic> data)? onOpen;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      debugStatus = 'Requesting permissions...';
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      // iOS: also surface heads-up notifications while the app is foregrounded.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Set listeners up first so a token that arrives late still gets synced.
      FirebaseMessaging.onMessage.listen(_record);
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      _fm.onTokenRefresh.listen((t) {
        _token = t;
        debugStatus = 'Token refreshed: $t';
        syncToken();
      });

      // iOS: getToken() throws/returns null until the APNs token is set (the
      // plugin registers for remote notifications during requestPermission).
      // Wait briefly for it. Android has no APNs step.
      if (!kIsWeb && Platform.isIOS) {
        debugStatus = 'Fetching APNs token...';
        String? apns = await _fm.getAPNSToken();
        for (int i = 0; i < 10 && apns == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
          apns = await _fm.getAPNSToken();
        }
        _apnsToken = apns;
        debugPrint('📲 APNs token: $apns');
        if (apns == null) {
          debugStatus = 'APNs token is NULL (check Certs/Provisioning Profile)';
          debugPrint('⚠️ WARNING: APNs token is null! APNs certificate (.p8/.p12) might be missing in Firebase Console or Push Notifications capability is missing in Provisioning Profile.');
        } else {
          debugStatus = 'APNs token: ${apns.length > 10 ? apns.substring(0, 10) : apns}...';
        }
      }

      try {
        debugStatus = 'Fetching FCM token...';
        _token = await _fm.getToken();
        debugPrint('📲 FCM token: $_token');
        if (_token != null) {
          debugStatus = 'FCM Token: ${_token!.length > 15 ? _token!.substring(0, 15) : _token!}...';
        } else {
          debugStatus = 'FCM Token is NULL';
        }
      } catch (e, stack) {
        debugStatus = 'FCM getToken failed: $e';
        debugPrint('❌ FCM getToken failed: $e\n$stack');
        debugPrint('💡 Suggestion: If on iOS, make sure APNs key/certificates are uploaded to Firebase Console, Bundle ID matches, and Push Notifications capability is enabled in Xcode/Developer Portal.');
      }

      // App launched from terminated state by tapping a notification.
      final initial = await _fm.getInitialMessage();
      if (initial != null) _opened(initial);
    } catch (e) {
      debugStatus = 'Init failed: $e';
      debugPrint('Notification init failed: $e');
    }
  }

  /// Foreground message → drop it into the bell inbox.
  void _record(RemoteMessage m) {
    final n = m.notification;
    CacheService.addNotification(
      id: m.messageId,
      title: (n?.title ?? m.data['title'] ?? 'NexAround').toString(),
      body: (n?.body ?? m.data['body'] ?? '').toString(),
      type: (m.data['type'] ?? '').toString(),
      data: m.data.map((k, v) => MapEntry(k, v)),
    );

    if (m.data['type'] == 'discovery_ready') {
      DiscoveryHistoryService.fetchHistory().then((history) {
        if (history.isNotEmpty) {
          final latest = history.first;
          CacheService.discoveryResultNotifier.value = latest['result'] as String?;
          CacheService.isDiscoveringNotifier.value = false;
        }
      }).catchError((e) {
        debugPrint('Error fetching discovery history in foreground: $e');
      });
    }
  }

  /// Notification tapped (from background/terminated) → record + route.
  void _opened(RemoteMessage m) {
    _record(m);
    onOpen?.call(m.data.map((k, v) => MapEntry(k, v)));
  }

  /// Push the device token to the backend. Safe to call repeatedly; requires
  /// the user to be authenticated (the auth interceptor adds the Bearer token).
  Future<void> syncToken() async {
    try {
      final t = _token ??= await _fm.getToken();
      if (t == null || t.isEmpty) return;
      await ApiClient.instance.post(ApiConstants.fcmToken, data: {'token': t});
      debugPrint('📲 FCM token synced to backend');
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }
}
