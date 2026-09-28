import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';

/// Persists Odysseys on the backend by reusing the `/itineraries` endpoints.
/// An Odyssey is just an Itinerary whose JSON `items` start with an
/// `odyssey_meta` block (see [Odyssey.toItineraryItems]).
class OdysseyRepository {
  final Dio _dio = ApiClient.instance;

  /// The collection endpoint MUST keep its trailing slash. The backend route is
  /// `/itineraries/`; calling it without the slash triggers a 307→301 redirect
  /// (which even bounces via http://), and HTTP clients drop the Authorization
  /// header across redirects — surfacing as a 401 "Not authenticated".
  static final String _collection = '${ApiConstants.itineraries}/';

  /// Bumped whenever the saved set changes so list screens can refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Kick off server-side AI generation. Returns immediately with a
  /// `status: "generating"` Odyssey; the backend fills in the plan in the
  /// background and the status flips to `active` (or `failed`).
  Future<Odyssey> requestGeneration({
    required String destination,
    required String mood,
    required double budget,
    required int days,
    String currency = 'USD',
    int travelers = 1,
    bool includeFlights = false,
    String departureCity = '',
    String departureCountry = '',
    String nationality = '',
    bool hasVisa = false,
    String? flightStartDate,
    String? flightEndDate,
    bool includeHotels = false,
    String? hotelCheckInDate,
    String? hotelCheckOutDate,
    String? startDate,
    String? endDate,
    // What the place picker resolved. All optional — the backend resolves the
    // destination itself, so omitting these only costs it a lookup.
    // Where the traveller wants the trip to begin and end inside the country.
    // Both optional and independent: a blank end means the planner chooses it.
    String entryCity = '',
    String exitCity = '',
    // The traveller asked to stay in the entry city for the whole trip. Only
    // ever true when entry and exit are the same place.
    bool onlyThisCity = false,
    // Where those two places are. The picker knows to the metre; sending only
    // the name makes the route planner infer it, and its inference becomes the
    // leg coordinates the hotel search then uses.
    double? entryLatitude,
    double? entryLongitude,
    double? exitLatitude,
    double? exitLongitude,
    String destinationPlaceId = '',
    double? destinationLatitude,
    double? destinationLongitude,
    String destinationAddress = '',
    // Where the traveller is flying from. The name is derived from these and
    // is not always usable, so the point itself travels alongside it.
    double? departureLatitude,
    double? departureLongitude,
    // The airport(s) shown on "Travelling from" ("DWC,DXB", or the one the
    // traveller picked). Used as the flight origin; empty lets the backend
    // resolve it from the city, as every older build does.
    String departureAirport = '',
    // The route the traveller was shown and accepted, exactly as
    // [previewRoute] returned it. Null means "decide it during generation",
    // which is what every older build does and still works.
    Map<String, dynamic>? presetRoute,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/odyssey/generate',
      data: {
        'destination': destination,
        'mood': mood,
        'budget': budget,
        'days': days,
        'currency': currency,
        'travelers': travelers,
        'include_flights': includeFlights,
        'departure_city': departureCity,
        'departure_country': departureCountry,
        'nationality': nationality,
        'has_visa': hasVisa,
        'flight_start_date': flightStartDate,
        'flight_end_date': flightEndDate,
        'include_hotels': includeHotels,
        'hotel_check_in_date': hotelCheckInDate,
        'hotel_check_out_date': hotelCheckOutDate,
        'start_date': startDate,
        'end_date': endDate,
        'entry_city': entryCity,
        'exit_city': exitCity,
        'only_this_city': onlyThisCity,
        'entry_latitude': entryLatitude,
        'entry_longitude': entryLongitude,
        'exit_latitude': exitLatitude,
        'exit_longitude': exitLongitude,
        'destination_place_id': destinationPlaceId,
        'destination_latitude': destinationLatitude,
        'destination_longitude': destinationLongitude,
        'destination_address': destinationAddress,
        'departure_latitude': departureLatitude,
        'departure_longitude': departureLongitude,
        if (departureAirport.isNotEmpty) 'departure_airport': departureAirport,
        if (presetRoute != null) 'preset_route': presetRoute,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// The cities a trip would visit, before committing to generating it.
  ///
  /// Generation plans this route anyway as its first step; asking for it here
  /// lets the traveller see and change it first. Whatever comes back is handed
  /// straight to [requestGeneration] as `presetRoute` if they accept it, so
  /// approving a preview costs no extra planning call.
  ///
  /// [excludeCities] asks for a different region: the cities already turned
  /// down. Returns null when the route could not be planned — the caller
  /// generates without a preview rather than blocking the trip on it.
  Future<Map<String, dynamic>?> previewRoute({
    required String destination,
    required String mood,
    required int days,
    int travelers = 1,
    bool includeFlights = false,
    String departureCity = '',
    String departureCountry = '',
    double? departureLatitude,
    double? departureLongitude,
    String? startDate,
    String? hotelCheckInDate,
    String entryCity = '',
    String exitCity = '',
    // The traveller asked to stay in the entry city for the whole trip. Only
    // ever true when entry and exit are the same place.
    bool onlyThisCity = false,
    double? entryLatitude,
    double? entryLongitude,
    double? exitLatitude,
    double? exitLongitude,
    String destinationPlaceId = '',
    double? destinationLatitude,
    double? destinationLongitude,
    String destinationAddress = '',
    List<String> excludeCities = const [],
  }) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.itineraries}/odyssey/route-preview',
        data: {
          'destination': destination,
          'mood': mood,
          'days': days,
          'travelers': travelers,
          'include_flights': includeFlights,
          'departure_city': departureCity,
          'departure_country': departureCountry,
          'departure_latitude': departureLatitude,
          'departure_longitude': departureLongitude,
          'start_date': startDate,
          'hotel_check_in_date': hotelCheckInDate,
          'entry_city': entryCity,
          'exit_city': exitCity,
          'only_this_city': onlyThisCity,
          'entry_latitude': entryLatitude,
          'entry_longitude': entryLongitude,
          'exit_latitude': exitLatitude,
          'exit_longitude': exitLongitude,
          'destination_place_id': destinationPlaceId,
          'destination_latitude': destinationLatitude,
          'destination_longitude': destinationLongitude,
          'destination_address': destinationAddress,
          'exclude_cities': excludeCities,
        },
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      return (response.data as Map).cast<String, dynamic>();
    } catch (_) {
      // A preview is a convenience. Generation still plans its own route, so
      // a failure here must never stop the traveller creating a trip.
      return null;
    }
  }

  /// Re-trigger generation for a failed Odyssey.
  Future<Odyssey> retryGeneration(String id) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/$id/odyssey/retry',
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Persist edits to an existing Odyssey (e.g. per-place check-off marking
  /// activities visited, or flipping status to `completed`). Sends the whole
  /// plan back via PUT so the nested `visited` flags and status are saved.
  Future<Odyssey> updateOdyssey(Odyssey odyssey) async {
    final id = odyssey.id;
    if (id == null) {
      throw ArgumentError('Cannot update an Odyssey without an id');
    }
    final response = await _dio.put(
      '${ApiConstants.itineraries}/$id',
      data: {
        'title': odyssey.title,
        'items': odyssey.toItineraryItems(),
        'status': odyssey.status,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Save an already-built Odyssey directly (used if a plan is generated
  /// client-side). Returns it with the backend id attached.
  Future<Odyssey> save(Odyssey odyssey) async {
    final response = await _dio.post(
      _collection,
      data: {
        'title': odyssey.title,
        'trip_date': null,
        'items': odyssey.toItineraryItems(),
        'status': odyssey.status,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// Request the AI to replace a single booking partner. Returns the updated Odyssey.
  Future<Odyssey> swapPartner({
    required String itineraryId,
    required String partnerName,
    String reason = '',
  }) async {
    final response = await _dio.post(
      '${ApiConstants.itineraries}/$itineraryId/odyssey/swap-partner',
      data: {
        'partner_name': partnerName,
        'reason': reason,
      },
    );
    revision.value++;
    final json = (response.data as Map).cast<String, dynamic>();
    return Odyssey.fromItinerary(json);
  }

  /// All saved Odysseys for the current user, newest first. Caches the raw
  /// result locally so [getCachedOdysseys] can render it instantly next time.
  Future<List<Odyssey>> getMyOdysseys() async {
    final response = await _dio.get(_collection);
    final raw = (response.data as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where(Odyssey.isOdyssey)
        .toList();
    await CacheService.cacheOdysseys(raw);
    return _sorted(raw.map(Odyssey.fromItinerary).toList());
  }

  /// The last cached Odyssey list (from the previous successful fetch). Returns
  /// an empty list if nothing is cached yet. Synchronous — no network.
  List<Odyssey> getCachedOdysseys() =>
      _sorted(CacheService.getCachedOdysseysRaw().map(Odyssey.fromItinerary).toList());

  List<Odyssey> _sorted(List<Odyssey> list) {
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  /// Fetch a single Odyssey by its itinerary ID (network first, cached fallback).
  Future<Odyssey?> getOdysseyById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.itineraries}/$id');
      final json = (response.data as Map).cast<String, dynamic>();
      final odyssey = Odyssey.fromItinerary(json);

      // Cache the full fresh Odyssey immediately so lists and details have full data
      final cachedRaw = CacheService.getCachedOdysseysRaw();
      final idx = cachedRaw.indexWhere((item) => item['id']?.toString() == id);
      if (idx != -1) {
        cachedRaw[idx] = json;
      } else {
        cachedRaw.insert(0, json);
      }
      await CacheService.cacheOdysseys(cachedRaw);
      revision.value++;

      return odyssey;
    } catch (_) {
      final cached = getCachedOdysseys();
      return cached.where((o) => o.id == id).firstOrNull;
    }
  }

  /// The airports nearest a point, for the planner's "Travelling from".
  ///
  /// `suggested` is what the flight search would use from there (for Jebel
  /// Ali "DWC,DXB"; for Kinniya "CMB", not the nearer but little-flown
  /// Jaffna), and the list starts with it. Never throws: a failure returns
  /// nothing and the field keeps the place name, as before.
  Future<NearestAirports> nearestAirports({
    required double latitude,
    required double longitude,
    String place = '',
    String country = '',
  }) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.itineraries}/odyssey/nearest-airports',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          if (place.isNotEmpty) 'place': place,
          if (country.isNotEmpty) 'country': country,
        },
      );
      final data = response.data is Map ? response.data as Map : const {};
      final airports = ((data['airports'] as List?) ?? const [])
          .whereType<Map>()
          .map(AirportOption.fromJson)
          .where((a) => a.iata.isNotEmpty)
          .toList();
      return NearestAirports(
        suggested: (data['suggested'] ?? '').toString(),
        airports: airports,
      );
    } catch (_) {
      return const NearestAirports();
    }
  }

  /// Ride apps answered per country, for the rest of the app session.
  static final Map<String, List<RideApp>> _rideAppsByCountry = {};

  /// Ride apps a traveller can use in a country, for the itinerary's buttons
  /// under transport stops.
  ///
  /// The backend asks Gemini with Google Search, finds each app's store page
  /// and caches both for a month; this keeps them for the session so
  /// reopening trips does not ask again. An empty answer is not kept, so a
  /// failed lookup is retried the next time a plan opens. Never throws: a
  /// failure just means no buttons.
  Future<List<RideApp>> getRideApps(String countryCode) async {
    final code = countryCode.trim().toUpperCase();
    if (code.length != 2) return const [];
    final known = _rideAppsByCountry[code];
    if (known != null) return known;
    try {
      final response = await _dio.get(
        '${ApiConstants.itineraries}/odyssey/ride-apps',
        queryParameters: {'country': code},
      );
      final data = response.data is Map ? response.data as Map : const {};
      final apps = <RideApp>[];
      final links = data['links'];
      if (links is List) {
        for (final link in links.whereType<Map>()) {
          final app = RideApp.fromJson(link);
          if (app.name.isNotEmpty) apps.add(app);
        }
      }
      // A backend from before store links still sends the names.
      final names = data['apps'];
      if (apps.isEmpty && names is List) {
        for (final name in names) {
          final text = name.toString().trim();
          if (text.isNotEmpty) apps.add(RideApp(name: text));
        }
      }
      if (apps.isNotEmpty) _rideAppsByCountry[code] = apps;
      return apps;
    } catch (_) {
      return const [];
    }
  }

  Future<void> delete(String id) async {
    await _dio.delete('${ApiConstants.itineraries}/$id');
    final cachedRaw = CacheService.getCachedOdysseysRaw();
    cachedRaw.removeWhere((item) => item['id']?.toString() == id);
    await CacheService.cacheOdysseys(cachedRaw);
    revision.value++;
  }
}

/// A ride app shown as a button under the itinerary's transport stops, with
/// the store pages a tap opens.
class RideApp {
  final String name;
  final String iosUrl;
  final String androidUrl;
  final String iconUrl;

  const RideApp({
    required this.name,
    this.iosUrl = '',
    this.androidUrl = '',
    this.iconUrl = '',
  });

  factory RideApp.fromJson(Map json) => RideApp(
        name: (json['name'] ?? '').toString().trim(),
        iosUrl: (json['ios_url'] ?? '').toString().trim(),
        androidUrl: (json['android_url'] ?? '').toString().trim(),
        iconUrl: (json['icon_url'] ?? '').toString().trim(),
      );

  /// This device's store page for the app. The store shows "Open" when it is
  /// installed and "Install" when it is not. With no verified page, a web
  /// search for the app, so every button still does something.
  String urlFor(TargetPlatform platform) {
    final store = platform == TargetPlatform.iOS ? iosUrl : androidUrl;
    if (store.isNotEmpty) return store;
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent('$name app')}';
  }
}

/// One airport near the traveller, as "Travelling from" shows it.
class AirportOption {
  final String iata;
  final String name;
  final String city;
  final String countryCode;
  final String country;
  final int distanceKm;

  const AirportOption({
    required this.iata,
    this.name = '',
    this.city = '',
    this.countryCode = '',
    this.country = '',
    this.distanceKm = 0,
  });

  factory AirportOption.fromJson(Map json) => AirportOption(
        iata: (json['iata'] ?? '').toString().trim().toUpperCase(),
        name: (json['name'] ?? '').toString().trim(),
        city: (json['city'] ?? '').toString().trim(),
        countryCode: (json['country_code'] ?? '').toString().trim(),
        country: (json['country'] ?? '').toString().trim(),
        distanceKm: (json['distance_km'] as num?)?.round() ?? 0,
      );

  /// "Al Maktoum International Airport (DWC)".
  String get label => name.isNotEmpty ? '$name ($iata)' : iata;
}

/// The nearest airports and the code list the flight search would use.
class NearestAirports {
  final String suggested;
  final List<AirportOption> airports;

  const NearestAirports({this.suggested = '', this.airports = const []});
}
