import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/constants/countries.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/data/models/experience_model.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// One active country where vendors exist.
class ExperienceCountry {
  final String code;
  final String name;
  final int count;
  final double? latitude;
  final double? longitude;

  const ExperienceCountry({
    required this.code,
    required this.name,
    this.count = 0,
    this.latitude,
    this.longitude,
  });

  factory ExperienceCountry.fromJson(Map<String, dynamic> json) {
    String rawCode = (json['code'] ?? '').toString().trim().toUpperCase();
    String rawName = (json['name'] ?? '').toString().trim();

    // Map dial code or numeric legacy values like 94 or +94 to LK
    if (rawCode == '94' || rawCode == '+94') {
      rawCode = 'LK';
    }

    // Resolve name from countries.dart if empty or numeric
    String resolvedName = rawName;
    if (resolvedName.isEmpty || resolvedName == '94' || resolvedName == rawCode) {
      if (rawCode == 'LK') {
        resolvedName = 'Sri Lanka';
      } else {
        for (final entry in countryCodes.entries) {
          if (entry.value.toUpperCase() == rawCode) {
            resolvedName = entry.key;
            break;
          }
        }
      }
    }

    return ExperienceCountry(
      code: rawCode,
      name: resolvedName.isNotEmpty ? resolvedName : rawCode,
      count: (json['count'] as num?)?.toInt() ?? 0,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  /// Flag emoji for 2-letter ISO country code.
  String get flag {
    final clean = (code == '94' ? 'LK' : code).toUpperCase();
    if (clean.length != 2) return '🌐';
    final firstChar = clean.codeUnitAt(0);
    final secondChar = clean.codeUnitAt(1);
    if (firstChar < 0x41 || firstChar > 0x5A || secondChar < 0x41 || secondChar > 0x5A) {
      return '🌐';
    }
    final first = firstChar - 0x41 + 0x1F1E6;
    final second = secondChar - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }
}

/// One page of nearest-first results, plus what the tab needs to decide
/// whether to show the "nothing nearby" banner.
class ExperiencesResult {
  final List<ExperiencePackageEntity> packages;
  final int total;
  final double? nearestDistanceM;

  /// False when the closest result is beyond the server's threshold. The app
  /// does not hardcode 50 km — the server sends both this and the threshold,
  /// so the rule can be retuned without an app release.
  final bool hasNearby;
  final int nearbyThresholdM;

  /// Admin > Settings > "Browse by country": the list is by country, with no
  /// distances, and "Near me" makes no sense.
  final bool countryMode;

  const ExperiencesResult({
    this.packages = const [],
    this.total = 0,
    this.nearestDistanceM,
    this.hasNearby = false,
    this.nearbyThresholdM = 50000,
    this.countryMode = false,
  });
}

/// The active countries, plus the browse mode the server reports with them.
class ExperienceCountries {
  final List<ExperienceCountry> countries;

  /// See [ExperiencesResult.countryMode]. Null when unknown: nothing saved yet,
  /// or a server from before the mode was reported.
  final bool? countryMode;

  const ExperienceCountries({this.countries = const [], this.countryMode});
}

/// Fetches, plus a stale-while-revalidate disk cache in [CacheService]: a
/// screen paints the saved copy at once, then replaces it with the network
/// result, and keeps the saved copy when the network fails.
class ExperiencesService {
  /// How many pages deep the tab will go. With no radius cap, paging forever
  /// eventually walks the user onto another continent for no value.
  static const int maxPages = 5;
  static const int pageSize = 20;

  /// How far the user may move before a saved list stops standing in for a
  /// fresh one: beyond this its distances and nearest-first order are wrong.
  static const double cacheRadiusM = 2000;

  /// Older than this, a saved list or package is not shown even offline, so a
  /// traveller is not quoted last month's prices.
  static const Duration cacheMaxAge = Duration(days: 7);

  static Future<ExperienceCountries> fetchActiveCountries() async {
    try {
      final response = await ApiClient.instance.get(ApiConstants.experiencesCountries);
      final data = response.data;
      if (data is Map<String, dynamic> && data['countries'] is List) {
        CacheService.cacheExperienceCountries(data);
        return _parseCountries(data);
      }
    } catch (e) {
      debugPrint('❌ Error fetching experience countries: $e');
    }
    return cachedCountries();
  }

  /// The countries and mode from the last successful fetch; empty and unknown
  /// if there is none.
  static ExperienceCountries cachedCountries() {
    final data = CacheService.getCachedExperienceCountries();
    return data == null ? const ExperienceCountries() : _parseCountries(data);
  }

  static ExperienceCountries _parseCountries(Map<String, dynamic> data) {
    final raw = data['countries'];
    return ExperienceCountries(
      countries: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(ExperienceCountry.fromJson)
              .toList()
          : const [],
      countryMode: data['country_mode'] as bool?,
    );
  }

  /// [latitude] and [longitude] may be null only in country mode, where the
  /// server lists by country and ignores them.
  static Future<ExperiencesResult> fetchNearby({
    double? latitude,
    double? longitude,
    String? category,
    String? countryCode,
    int limit = pageSize,
    int offset = 0,
  }) async {
    final response = await ApiClient.instance.get(
      ApiConstants.experiencesNearby,
      queryParameters: {
        if (latitude != null && longitude != null) ...{
          'lat': latitude,
          'lng': longitude,
        },
        'limit': limit,
        'offset': offset,
        if (category != null && category.isNotEmpty) 'category': category,
        if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) return const ExperiencesResult();

    // Only the first page: it is what a screen paints before the network
    // answers, and later pages are fetched on scroll anyway.
    if (offset == 0) {
      CacheService.cacheExperiencesNearby(_nearbyKey(category, countryCode), {
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'lat': latitude,
        'lng': longitude,
        'data': data,
      });
    }
    return _parseNearby(data);
  }

  /// The first page saved for these filters, or null when there is none, it
  /// is older than [cacheMaxAge], or it is a nearest-first list fetched more
  /// than [cacheRadiusM] from here. A by-country list has no distances, so
  /// it holds wherever the user is.
  static ExperiencesResult? cachedNearby({
    double? latitude,
    double? longitude,
    String? category,
    String? countryCode,
  }) {
    final entry = CacheService.getCachedExperiencesNearby(
        _nearbyKey(category, countryCode));
    if (entry == null || !_isFresh(entry)) return null;
    final data = entry['data'];
    if (data is! Map<String, dynamic>) return null;
    if (data['country_mode'] == true) return _parseNearby(data);

    final lat = (entry['lat'] as num?)?.toDouble();
    final lng = (entry['lng'] as num?)?.toDouble();
    if (lat == null || lng == null || latitude == null || longitude == null) {
      return null;
    }
    if (geo.Geolocator.distanceBetween(lat, lng, latitude, longitude) >
        cacheRadiusM) {
      return null;
    }
    return _parseNearby(data);
  }

  static String _nearbyKey(String? category, String? countryCode) =>
      '${countryCode ?? ''}|${category ?? ''}';

  static bool _isFresh(Map<String, dynamic> entry) {
    final savedAt = (entry['saved_at'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    return age >= 0 && age < cacheMaxAge.inMilliseconds;
  }

  static ExperiencesResult _parseNearby(Map<String, dynamic> data) {
    final rawPackages = data['packages'];
    return ExperiencesResult(
      packages: rawPackages is List
          ? rawPackages
              .whereType<Map<String, dynamic>>()
              .map(ExperiencePackageModel.fromJson)
              .toList()
          : const [],
      total: (data['total'] as num?)?.toInt() ?? 0,
      nearestDistanceM: (data['nearest_distance_m'] as num?)?.toDouble(),
      hasNearby: data['has_nearby'] as bool? ?? false,
      nearbyThresholdM: (data['nearby_threshold_m'] as num?)?.toInt() ?? 50000,
      countryMode: data['country_mode'] as bool? ?? false,
    );
  }

  /// The full package, or null when it could not be fetched. A 404 also drops
  /// the saved copy, so a removed package stops appearing offline.
  static Future<ExperiencePackageEntity?> fetchPackage(
    String packageId, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.experiencePackages}/$packageId',
        queryParameters: {
          if (latitude != null) 'lat': latitude,
          if (longitude != null) 'lng': longitude,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        CacheService.cacheExperienceDetail(packageId, {
          'saved_at': DateTime.now().millisecondsSinceEpoch,
          'data': data,
        });
        return ExperiencePackageModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching experience package: $e');
      if (e is DioException && e.response?.statusCode == 404) {
        CacheService.removeCachedExperienceDetail(packageId);
      }
      return null;
    }
  }

  /// The package as last fetched, or null when there is none or it is older
  /// than [cacheMaxAge].
  ///
  /// [distanceM] replaces the saved distance, which was measured from wherever
  /// the user stood then: pass the card's fresh one, or nothing to show none.
  static ExperiencePackageEntity? cachedPackage(
    String packageId, {
    double? distanceM,
  }) {
    final entry = CacheService.getCachedExperienceDetail(packageId);
    if (entry == null || !_isFresh(entry)) return null;
    final data = entry['data'];
    if (data is! Map<String, dynamic>) return null;
    return ExperiencePackageModel.fromJson({...data, 'distance_m': distanceM});
  }

  /// Submits an enquiry. Returns null on success, or a message to show.
  static Future<String?> submitEnquiry({
    required String packageId,
    required String contactName,
    required String contactPhone,
    String? contactEmail,
    DateTime? preferredDate,
    int? partySize,
    String? pickupLocation,
    String? message,
  }) async {
    try {
      await ApiClient.instance.post(
        ApiConstants.experienceEnquiries,
        data: {
          'package_id': packageId,
          'contact_name': contactName,
          'contact_phone': contactPhone,
          if (contactEmail != null && contactEmail.isNotEmpty)
            'contact_email': contactEmail,
          if (preferredDate != null)
            'preferred_date':
                preferredDate.toIso8601String().split('T').first,
          if (partySize != null) 'party_size': partySize,
          if (pickupLocation != null && pickupLocation.isNotEmpty)
            'pickup_location': pickupLocation,
          if (message != null && message.isNotEmpty) 'message': message,
        },
      );
      return null;
    } catch (e) {
      debugPrint('❌ Error submitting experience enquiry: $e');
      // The server's own sentence when it has one, e.g. a date past the
      // vendor's booking window.
      return (e is DioException ? safeServerDetail(e.response) : null) ??
          'Could not send your request. Please try again.';
    }
  }
}
