import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

/// Wraps Firebase Cloud Messaging: asks permission, grabs the device token,
/// registers it with the backend, and funnels incoming messages into the local
/// notification inbox ([CacheService]) that the homepage bell reads.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  String? _token;
  bool _initialized = false;

  /// Set by the app shell to route a notification tap (e.g. open Blueprints).
  void Function(Map<String, dynamic> data)? onOpen;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      // iOS: also surface heads-up notifications while the app is foregrounded.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _token = await _fm.getToken();
      debugPrint('📲 FCM token: $_token');

      FirebaseMessaging.onMessage.listen(_record);
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      _fm.onTokenRefresh.listen((t) {
        _token = t;
        syncToken();
      });

      // App launched from terminated state by tapping a notification.
      final initial = await _fm.getInitialMessage();
      if (initial != null) _opened(initial);
    } catch (e) {
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
  }

  /// Notification tapped (from background/terminated) → record + route.
  void _opened(RemoteMessage m) {
    _record(m);
    onOpen?.call(m.data.map((k, v) => MapEntry(k, v)));
  }

  /// Push the device token to the backend. Safe to call repeatedly; requires
  /// the user to be authenticated (the auth interceptor adds the Bearer token).
  Future<void> syncToken() async {
    final t = _token ??= await _fm.getToken();
    if (t == null || t.isEmpty) return;
    try {
      await ApiClient.instance.post(ApiConstants.fcmToken, data: {'token': t});
      debugPrint('📲 FCM token synced to backend');
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }
}
