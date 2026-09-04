import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Global singleton that tracks real-time network connectivity.
///
/// Uses `connectivity_plus` for change events and verifies with a real DNS
/// lookup (google.com) to avoid false positives (e.g. connected to Wi-Fi
/// without internet). Exposes [isOnline] as a [ValueNotifier] so any widget
/// can cheaply listen via `ValueListenableBuilder`.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _initialized = false;

  /// `true` when the device can reach the internet; `false` otherwise.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  /// Fires every time the connectivity state changes (online ↔ offline).
  /// Widgets that need to auto-retry on reconnection can listen here.
  final ValueNotifier<int> reconnectTrigger = ValueNotifier<int>(0);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Initial check
    await checkNow();

    // Listen for changes
    _sub = _connectivity.onConnectivityChanged.listen((results) async {
      // connectivity_plus v6 delivers a List<ConnectivityResult>
      final hasTransport = results.any((r) => r != ConnectivityResult.none);
      if (!hasTransport) {
        _setOnline(false);
      } else {
        // Transport available – verify actual internet access
        await checkNow();
      }
    });
  }

  /// On-demand connectivity verification. Returns `true` if online.
  Future<bool> checkNow() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _setOnline(online);
      return online;
    } on SocketException {
      _setOnline(false);
      return false;
    } on TimeoutException {
      _setOnline(false);
      return false;
    } catch (_) {
      _setOnline(false);
      return false;
    }
  }

  void _setOnline(bool value) {
    final wasOffline = !isOnline.value;
    if (isOnline.value != value) {
      isOnline.value = value;
      debugPrint('🌐 Connectivity: ${value ? "ONLINE" : "OFFLINE"}');
    }
    // If transitioning from offline → online, bump the reconnect trigger
    if (wasOffline && value) {
      reconnectTrigger.value++;
      debugPrint('🔄 Connectivity: Reconnected (trigger #${reconnectTrigger.value})');
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
