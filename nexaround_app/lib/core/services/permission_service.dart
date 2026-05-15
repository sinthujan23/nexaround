import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  /// Request all necessary permissions on app launch
  static Future<void> requestAllPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.locationWhenInUse,
      ].request();
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  /// Check if location services are enabled without redirecting
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Safe way to get position: checks if service is enabled first to avoid Google popup crashes
  static Future<Position?> getSafePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
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
