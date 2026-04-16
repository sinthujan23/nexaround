import 'package:flutter/foundation.dart';

class ApiConstants {
  static String get baseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isEmpty || host == 'localhost') return 'http://localhost:8000';
      return 'http://$host:8000';
    }
    // For Native Mobile (APK/iOS), use the PC's current local IP
    return 'http://172.22.141.243:8000';
  }
  static const String apiVersion = '/api/v1';
  
  // Auth endpoints
  static const String register = '$apiVersion/auth/register';
  static const String login = '$apiVersion/auth/login';
  static const String refreshToken = '$apiVersion/auth/refresh';
  static const String me = '$apiVersion/auth/me';
  static const String updatePreferences = '$apiVersion/auth/me/preferences';
  
  // Attraction endpoints
  static const String attractionsNearby = '$apiVersion/attractions/nearby';
  static const String attractionsSearch = '$apiVersion/attractions/search';
  static const String categories = '$apiVersion/categories';
  
  // Navigation endpoints
  static const String directions = '$apiVersion/navigation/directions';
}
