import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

class PermissionService {
  /// Request all necessary permissions on app launch.
  ///
  /// On iOS, permissions can only be prompted ONCE by the system. If the user
  /// denies, subsequent `.request()` calls silently return `denied` — so we
  /// must detect that and offer to open Settings instead.
  static Future<void> requestAllPermissions() async {
    try {
      // Request camera sequentially
      final cameraResult = await requestCameraPermission();
      debugPrint('📷 Camera permission request result: $cameraResult');

      // Small delay to let the iOS animation/system dialog transition finish and avoid collisions
      await Future.delayed(const Duration(milliseconds: 800));

      // Request location sequentially
      final locationResult = await requestLocationPermission();
      debugPrint('📍 Location permission request result: $locationResult');
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  /// Request camera permission specifically, handling iOS denied state.
  /// Returns true if permission is granted after the call.
  static Future<bool> requestCameraPermission() async {
    var status = await Permission.camera.status;
    debugPrint('📷 Camera permission status: $status');

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied || (!kIsWeb && Platform.isIOS && status.isDenied && CacheService.hasRequestedCamera())) {
      // On iOS, after the first denial, `isDenied` persists and `.request()`
      // won't re-trigger the system dialog. We need to check if we can still
      // show the dialog or must redirect to Settings.
      final result = await Permission.camera.request();
      if (result.isGranted || result.isLimited) return true;

      // If still not granted, open app settings
      debugPrint('📷 Camera denied/permanently denied — opening Settings');
      await openAppSettings();
      // Re-check after user returns from Settings
      return await Permission.camera.status.isGranted;
    }

    // First time or restricted — request normally
    await CacheService.setRequestedCamera();
    final result = await Permission.camera.request();
    return result.isGranted || result.isLimited;
  }

  /// Request location permission specifically, handling iOS denied state.
  /// Returns true if permission is granted after the call.
  static Future<bool> requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    debugPrint('📍 Location permission status: $status');

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied || (!kIsWeb && Platform.isIOS && status.isDenied && CacheService.hasRequestedLocation())) {
      final result = await Permission.locationWhenInUse.request();
      if (result.isGranted || result.isLimited) return true;

      debugPrint('📍 Location denied/permanently denied — opening Settings');
      await openAppSettings();
      return await Permission.locationWhenInUse.status.isGranted;
    }

    await CacheService.setRequestedLocation();
    final result = await Permission.locationWhenInUse.request();
    return result.isGranted || result.isLimited;
  }

  /// Check actual permission status — call this instead of assuming `true`.
  static Future<bool> isCameraGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted || status.isLimited;
  }

  /// Check actual location permission status.
  static Future<bool> isLocationGranted() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted || status.isLimited;
  }

  /// Check if location services are enabled without redirecting
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Safe way to get position: checks if service is enabled first to avoid Google popup crashes
  static Future<Position?> getSafePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    final permission = await Permission.locationWhenInUse.status;
    if (!permission.isGranted && !permission.isLimited) {
      debugPrint('📍 getSafePosition: Location permission not granted');
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('Error getting position: $e');
      return null;
    }
  }

  /// Redirect to system location settings
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
