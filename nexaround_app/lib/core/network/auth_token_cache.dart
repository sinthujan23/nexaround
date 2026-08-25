import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synchronously-readable copy of the access token, for image requests.
///
/// Widgets build synchronously, so an image widget cannot await
/// SharedPreferences to attach an Authorization header — and without that
/// header the backend treats a photo request as anonymous. Anonymous requests
/// are served from the server's disk cache only and 404 on a miss, by design,
/// so that the photo endpoint cannot be used as a free proxy to Google. The
/// practical effect was that a photo nobody had already downloaded could never
/// be downloaded *by* anyone: the app fell through to a category icon and the
/// backend had to pre-warm photos out of band to compensate.
///
/// Holding the token in memory lets [imageHeaders] be read during build, so a
/// photo request arrives authenticated and the server is free to fetch it from
/// Google on the spot. Per-user spend caps still apply on the server side.
///
/// Kept in sync by [ApiClient], which already reads and writes the token.
class AuthTokenCache {
  static String? _token;

  static String? get token => _token;

  /// Headers for a request to **our own** backend, or null when signed out —
  /// passing null leaves the request unauthenticated rather than sending
  /// "Bearer null".
  ///
  /// Prefer [headersFor] at any call site whose URL is not certainly ours.
  static Map<String, String>? get imageHeaders =>
      _token == null ? null : {'Authorization': 'Bearer $_token'};

  /// Headers for [url], and only if [url] points at our backend.
  ///
  /// Image widgets are pointed at all sorts of hosts — Unsplash covers, avatar
  /// CDNs, Mapbox tiles — and attaching the bearer token to those would hand a
  /// third party a live credential for this account. So the origin is checked
  /// rather than assumed.
  static Map<String, String>? headersFor(String? url) {
    if (url == null || !url.startsWith(ApiConstants.baseUrl)) return null;
    return imageHeaders;
  }

  /// Record the token the app is now using. Called on login, on refresh, and
  /// whenever a request reads it out of storage.
  static void set(String? value) => _token = value;

  static void clear() => _token = null;

  /// Prime the cache from storage. Call once at startup, before the first
  /// screen builds, so images on the very first frame are authenticated.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
  }
}
