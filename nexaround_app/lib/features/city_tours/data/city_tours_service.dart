import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';

/// City Tours from `/city-tours`. Each answer is kept on the device, so a page
/// opened again shows at once and refreshes underneath.
class CityToursService {
  final Dio _dio = ApiClient.instance;

  static const String _base = '${ApiConstants.apiVersion}/city-tours';
  static const String _listKey = 'city_tours_list';
  static String _tourKey(String id) => 'city_tour_$id';

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
