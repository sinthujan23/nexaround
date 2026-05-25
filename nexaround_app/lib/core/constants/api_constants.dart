class ApiConstants {
  static const String baseUrl = 'https://api.nexaround.com';
  static const String apiVersion = '/api/v1';
  static const String googleMapsApiKey = 'AIzaSyAxGlCCI4yoOn3umPPyX1VypSzL2Sutz9U';
  static const String geminiApiKey = 'AIzaSyC2y9dsp2ODG_eUy3OFpwonN8MH8TRE9oY';
  
  // Auth endpoints
  static const String register = '$apiVersion/auth/register';
  static const String login = '$apiVersion/auth/login';
  static const String googleLogin = '$apiVersion/auth/google';
  static const String appleLogin = '$apiVersion/auth/apple';
  static const String refreshToken = '$apiVersion/auth/refresh';
  static const String me = '$apiVersion/auth/me';
  static const String updatePreferences = '$apiVersion/auth/me/preferences';
  
  // Attraction endpoints
  static const String attractionsNearby = '$apiVersion/attractions/nearby';
  static const String attractionsSearch = '$apiVersion/attractions/search';
  static const String categories = '$apiVersion/categories';
  
  // Navigation endpoints
  static const String directions = '$apiVersion/navigation/directions';
  
  // Itinerary endpoints
  static const String itineraries = '$apiVersion/itineraries';
  
  // Mapbox Configuration
  static const String mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN_HERE';
  
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
