import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:latlong2/latlong2.dart' as ll;
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour_trip.dart';

/// City Tours from `/city-tours`. Each answer is kept on the device, so a page
/// opened again shows at once and refreshes underneath.
class CityToursService {
  final Dio _dio = ApiClient.instance;

  static const String _base = '${ApiConstants.apiVersion}/city-tours';
  static const String _listKey = 'city_tours_list';
  static String _tourKey(String id) => 'city_tour_$id';
  static String _tripKey(String id) => 'city_tour_trip_$id';
  static String _planKey(String id) => 'city_tour_plan_$id';
  static String _legKey(CityTourStep ride, CityTourStep from, CityTourStep to) =>
      'city_tour_leg_${ride.directionsMode}_${from.lat},${from.lng}_${to.lat},${to.lng}';

  Future<List<CityTourCard>> getTours() async {
    final response = await _dio.get(_base);
    final raw = (response.data as Map).cast<String, dynamic>();
    await CacheService.saveUserData(_listKey, json.encode(raw));
    return _cards(raw);
  }

  List<CityTourCard> cachedTours() {
    final raw = _read(_listKey);
    return raw == null ? const [] : _cards(raw);
  }

  Future<CityTour> getTour(String id) async {
    final response = await _dio.get('$_base/$id');
    final raw = (response.data as Map).cast<String, dynamic>();
    await CacheService.saveUserData(_tourKey(id), json.encode(raw));
    return CityTour.fromJson(raw);
  }

  CityTour? cachedTour(String id) {
    final raw = _read(_tourKey(id));
    return raw == null ? null : CityTour.fromJson(raw);
  }

  /// Tells the server an Experience was opened from a guide, so the tap
  /// counts for the partner report. Affiliate taps are counted by the /go
  /// address they open. Never throws: the traveller is already on their way.
  Future<void> recordTap(String tourId, String linkId) async {
    try {
      await _dio.post('$_base/$tourId/links/$linkId/tap');
    } catch (e) {
      debugPrint('City tour tap not recorded: $e');
    }
  }

  // Trips: saved on the traveller's account (signed in only). The latest
  // answer is kept on the device too, so a reopened guide shows its times at
  // once; every change still waits for the server.

  /// The traveller's running or finished trip on a guide, or null.
  Future<CityTourTrip?> getTrip(String tourId) async {
    final response = await _dio.get('$_base/$tourId/trip');
    return _saveTrip(tourId, response.data);
  }

  CityTourTrip? cachedTrip(String tourId) {
    final raw = _read(_tripKey(tourId));
    final trip = raw?['trip'];
    return trip is Map ? CityTourTrip.fromJson(trip.cast<String, dynamic>()) : null;
  }

  /// The other days' finished trips still shown, from the latest answer: a
  /// day done keeps its ticks after the next day starts.
  List<CityTourTrip> cachedDayTrips(String tourId) {
    final raw = _read(_tripKey(tourId));
    final list = raw?['day_trips'];
    if (list is! List) return const [];
    return [
      for (final t in list)
        if (t is Map) CityTourTrip.fromJson(t.cast<String, dynamic>()),
    ];
  }

  /// Starts one day of the guide now ([dayId]; the first day when null). A
  /// trip already running on the guide ends.
  Future<CityTourTrip> startTrip(String tourId, {String? dayId}) async {
    final response = await _dio.post(
      '$_base/$tourId/trip',
      data: dayId == null ? null : {'day_id': dayId},
    );
    return (await _saveTrip(tourId, response.data))!;
  }

  // The days a traveller picked for a guide, on this device only.

  List<String>? savedPlan(String tourId) {
    final raw = _read(_planKey(tourId));
    final days = raw?['days'];
    return days is List ? days.map((e) => e.toString()).toList() : null;
  }

  Future<void> savePlan(String tourId, List<String> dayIds) =>
      CacheService.saveUserData(_planKey(tourId), json.encode({'days': dayIds}));

  /// [at] is when the traveller tapped, so a retry keeps that time. [skip]
  /// ends the step without visiting it.
  Future<CityTourTrip> markDone(String tourId, String stepId, DateTime at, {bool skip = false}) async {
    final response = await _dio.post(
      '$_base/$tourId/trip/done',
      data: {'step_id': stepId, 'at': at.toUtc().toIso8601String(), if (skip) 'skip': true},
    );
    return (await _saveTrip(tourId, response.data))!;
  }

  /// Takes back a step's "Mark done" or "Skip": any one, in any order.
  Future<CityTourTrip> undoDone(String tourId, String stepId) async {
    final response = await _dio.post('$_base/$tourId/trip/undo', data: {'step_id': stepId});
    return (await _saveTrip(tourId, response.data))!;
  }

  /// Stops a running trip, or closes a finished one: the trip in hand, or
  /// with [dayId] that day's. Returns the trip in hand after (another day's
  /// finished one can take its place).
  Future<CityTourTrip?> endTrip(String tourId, {String? dayId}) async {
    final response = await _dio.delete(
      '$_base/$tourId/trip',
      queryParameters: dayId == null ? null : {'day_id': dayId},
    );
    // A server from before answers with nothing.
    if (response.data is Map) return _saveTrip(tourId, response.data);
    await CacheService.saveUserData(_tripKey(tourId), json.encode({'trip': null}));
    return null;
  }

  Future<CityTourTrip?> _saveTrip(String tourId, dynamic data) async {
    final raw = (data as Map).cast<String, dynamic>();
    await CacheService.saveUserData(_tripKey(tourId), json.encode(raw));
    final trip = raw['trip'];
    return trip is Map ? CityTourTrip.fromJson(trip.cast<String, dynamic>()) : null;
  }

  static List<CityTourCard> _cards(Map<String, dynamic> raw) =>
      (raw['tours'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CityTourCard.fromJson(e.cast<String, dynamic>()))
          .toList();

  /// A ride's street route from one stop to the next, if this device has it.
  /// The way between two fixed places doesn't change, so it is fetched once.
  List<ll.LatLng>? cachedLegRoute(CityTourStep ride, CityTourStep from, CityTourStep to) {
    final points = _read(_legKey(ride, from, to))?['points'];
    if (points is! List) return null;
    return [
      for (final p in points.whereType<List>())
        ll.LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
  }

  /// The ride's street route from Google Directions; null when it has none
  /// (a boat, no public transport there) or the fetch failed.
  Future<List<ll.LatLng>?> getLegRoute(CityTourStep ride, CityTourStep from, CityTourStep to) async {
    final mode = ride.directionsMode;
    if (mode == null || !from.hasPin || !to.hasPin) return null;
    final answer = await GooglePlacesService.getDirections(
      originLat: from.lat!,
      originLng: from.lng!,
      destLat: to.lat!,
      destLng: to.lng!,
      profile: mode,
      exactOrigin: true,
    );
    final points = answer?['polyline'];
    if (points is! List<LatLng> || points.length < 2) return null;
    await CacheService.saveUserData(
      _legKey(ride, from, to),
      json.encode({
        'points': [
          for (final p in points) [p.latitude, p.longitude],
        ],
      }),
    );
    return [for (final p in points) ll.LatLng(p.latitude, p.longitude)];
  }

  static Map<String, dynamic>? _read(String key) {
    final text = CacheService.getUserData(key);
    if (text == null) return null;
    try {
      return (json.decode(text) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}
