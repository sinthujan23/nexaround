import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

/// One Neva reply from the backend: her text, plus the real places she found
/// when the question was "where is…" (empty otherwise), nearest first.
class NevaReply {
  final String text;
  final List<AttractionEntity> places;
  final String query;

  const NevaReply({required this.text, this.places = const [], this.query = ''});
}

/// Neva through `POST /api/v1/neva/chat`, which can search Google Maps near
/// the user and answer from what it finds (client request, 2026-10-01: "respond
/// with map integrated when asking help for location").
///
/// Returns null on any failure so the chat can fall back to the plain Gemini
/// proxy it used before — an older backend, a timeout or a 503 must never
/// leave the user without an answer.
class NevaService {
  static final _options = Options(
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  );

  static Future<NevaReply?> chat({
    required String message,
    double? latitude,
    double? longitude,
    String? area,
  }) async {
    try {
      final response = await ApiClient.instance.post(
        '${ApiConstants.apiVersion}/neva/chat',
        data: {
          'message': message,
          if (latitude != null && longitude != null) 'latitude': latitude,
          if (latitude != null && longitude != null) 'longitude': longitude,
          if (area != null && area.isNotEmpty && area != 'Nearby') 'area': area,
        },
        options: _options,
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map) return null;
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) return null;
      final places = <AttractionEntity>[];
      for (final raw in (data['places'] as List?) ?? const []) {
        if (raw is! Map) continue;
        try {
          places.add(AttractionModel.fromJson(raw.cast<String, dynamic>()));
        } catch (e) {
          debugPrint('Neva place skipped: $e');
        }
      }
      return NevaReply(
        text: text,
        places: places,
        query: (data['query'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('Neva chat endpoint failed, falling back: $e');
      return null;
    }
  }
}
