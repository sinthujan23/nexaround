import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
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

  /// Starts the guide now; a trip already running on it ends.
  Future<CityTourTrip> startTrip(String tourId) async {
    final response = await _dio.post('$_base/$tourId/trip');
    return (await _saveTrip(tourId, response.data))!;
  }

  /// [at] is when the traveller tapped, so a retry keeps that time.
  Future<CityTourTrip> markDone(String tourId, String stepId, DateTime at) async {
    final response = await _dio.post(
      '$_base/$tourId/trip/done',
      data: {'step_id': stepId, 'at': at.toUtc().toIso8601String()},
    );
    return (await _saveTrip(tourId, response.data))!;
  }

  /// Takes back the last "Mark done".
  Future<CityTourTrip> undoDone(String tourId) async {
    final response = await _dio.post('$_base/$tourId/trip/undo');
    return (await _saveTrip(tourId, response.data))!;
  }

  /// Stops a running trip, or closes a finished one.
  Future<void> endTrip(String tourId) async {
    await _dio.delete('$_base/$tourId/trip');
    await CacheService.saveUserData(_tripKey(tourId), json.encode({'trip': null}));
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
