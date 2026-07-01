class ApiConstants {
  static const String baseUrl = 'https://api.nexaround.com';
  static const String apiVersion = '/api/v1';
  static String googleMapsApiKey = '';
  static String geminiApiKey = '';
  
  // Custom Google Sign-In credentials (from Google Cloud Project with Google Drive API enabled)
  // Leave empty to use defaults from google-services.json / GoogleService-Info.plist
  static const String googleClientId = '';       // For iOS OAuth Client ID
  static const String googleServerClientId = '501648798743-s475las96nn5m01l105dikmm74ghuhf9.apps.googleusercontent.com'; // For Web OAuth Client ID (used as serverClientId on Android/iOS)
  
  // Secure proxy endpoints
  static const String geminiProxy = '$apiVersion/proxy/gemini/generate';
  static const String mapboxProxy = '$apiVersion/proxy/mapbox/directions';
  static const String googleMapsProxy = '$apiVersion/proxy/google-maps';
  
  // Auth endpoints
  static const String register = '$apiVersion/auth/register';
  static const String login = '$apiVersion/auth/login';
  static const String googleLogin = '$apiVersion/auth/google';
  static const String appleLogin = '$apiVersion/auth/apple';
  static const String refreshToken = '$apiVersion/auth/refresh';
  static const String me = '$apiVersion/auth/me';
  static const String updatePreferences = '$apiVersion/auth/me/preferences';
  static const String fcmToken = '$apiVersion/auth/me/fcm-token';
  
  // Attraction endpoints
  static const String attractionsNearby = '$apiVersion/attractions/nearby';
  static const String attractionsSearch = '$apiVersion/attractions/search';
  static const String categories = '$apiVersion/categories';
  
  // Navigation endpoints
  static const String directions = '$apiVersion/navigation/directions';
  
  // Itinerary endpoints
  static const String itineraries = '$apiVersion/itineraries';
  
  // Travel Stories endpoints
  static const String travelStories = '$apiVersion/travel-stories';
  
  // Discovery endpoints
  static const String discoveryHistory = '$apiVersion/discovery/history';
  
  // Mapbox Configuration
  static String mapboxAccessToken = '';
  
  // Mapbox Tile Style URLs (for flutter_map)
  static String mapboxStyleUrl(String styleId) =>
    'https://api.mapbox.com/styles/v1/mapbox/$styleId/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxAccessToken';
  
  static String get mapboxStreets => mapboxStyleUrl('streets-v12');
  static String get mapboxLight => mapboxStyleUrl('light-v11');
  static String get mapboxDark => mapboxStyleUrl('dark-v11');
  static String get mapboxSatellite => mapboxStyleUrl('satellite-streets-v12');
  static String get mapboxOutdoors => mapboxStyleUrl('outdoors-v12');
  static String get mapboxNavigation => mapboxStyleUrl('navigation-night-v1');
}
