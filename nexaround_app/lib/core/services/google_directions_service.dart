import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

// ═══════════════════════════════════════════════════════════════════
// Google Directions Service — Walking Route for AR Navigation
// Fetches turn-by-turn walking directions and parses into RouteStep
// objects used by the AR chevron renderer.
// ═══════════════════════════════════════════════════════════════════

class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
}

class RouteStep {
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final double bearing;
  final String instruction;
  final String distanceText;
  final double distanceM;
  final String durationText;
  final String? maneuver; // "turn-left", "turn-right", "straight", etc.
  final String? streetName;
  final List<LatLng> polylinePoints;

  const RouteStep({
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.bearing,
    required this.instruction,
    required this.distanceText,
    required this.distanceM,
    required this.durationText,
    this.maneuver,
    this.streetName,
    this.polylinePoints = const [],
  });

  /// Whether this step requires a turn (vs going straight/starting).
  bool get isTurn =>
      maneuver != null &&
      (maneuver!.contains('turn') ||
          maneuver!.contains('fork') ||
          maneuver!.contains('ramp') ||
          maneuver!.contains('roundabout'));

  /// True for left-bound maneuvers.
  bool get isLeft =>
      maneuver != null &&
      (maneuver!.contains('left'));

  /// True for right-bound maneuvers.
  bool get isRight =>
      maneuver != null &&
      (maneuver!.contains('right'));
}

class WalkingRoute {
  final List<RouteStep> steps;
  final String totalDistance;
  final String totalDuration;
  final double totalDistanceM;
  final List<LatLng> overviewPolyline;

  const WalkingRoute({
    required this.steps,
    required this.totalDistance,
    required this.totalDuration,
    required this.totalDistanceM,
    required this.overviewPolyline,
  });

  /// Remaining distance from a given step index onward.
  double remainingDistanceM(int fromStep) {
    double d = 0;
    for (int i = fromStep; i < steps.length; i++) {
      d += steps[i].distanceM;
    }
    return d;
  }

  /// Human-readable remaining distance.
  String remainingDistanceText(int fromStep) {
    final m = remainingDistanceM(fromStep);
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }
}

class GoogleDirectionsService {
  static final Dio _dio = Dio();
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String _apiKey = ApiConstants.googleMapsApiKey;

  /// Fetch a walking route between two points.
  /// Returns null on failure (API error, no route found, etc.).
  static Future<WalkingRoute?> getWalkingRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      debugPrint('🗺️ Fetching walking route: ($originLat,$originLng) → ($destLat,$destLng)');

      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'origin': '$originLat,$originLng',
          'destination': '$destLat,$destLng',
          'mode': 'walking',
          'key': _apiKey,
        },
      );

      if (response.data['status'] != 'OK') {
        debugPrint('❌ Directions API: ${response.data['status']} — ${response.data['error_message'] ?? ''}');
        return null;
      }

      final routes = response.data['routes'] as List;
      if (routes.isEmpty) {
        debugPrint('❌ Directions API: No routes found');
        return null;
      }

      final route = routes[0];
      final leg = route['legs'][0];

      // Decode overview polyline
      final overviewPoints =
          _decodePolyline(route['overview_polyline']['points'] as String);

      // Parse individual steps
      final List<RouteStep> steps = [];
      final rawSteps = leg['steps'] as List;

      for (final step in rawSteps) {
        final startLoc = step['start_location'];
        final endLoc = step['end_location'];
        final sLat = (startLoc['lat'] as num).toDouble();
        final sLng = (startLoc['lng'] as num).toDouble();
        final eLat = (endLoc['lat'] as num).toDouble();
        final eLng = (endLoc['lng'] as num).toDouble();

        final bearing = _calculateBearing(sLat, sLng, eLat, eLng);

        // Strip HTML tags from instructions
        final rawInstruction = step['html_instructions'] as String? ?? '';
        final instruction = _stripHtml(rawInstruction);

        // Try to extract street name from instruction
        String? streetName;
        final ontoMatch = RegExp(r'(?:onto|on) (.+?)(?:\.|$)').firstMatch(instruction);
        if (ontoMatch != null) {
          streetName = ontoMatch.group(1)?.trim();
        }

        // Decode step-level polyline
        final stepPoints = step['polyline']?['points'] != null
            ? _decodePolyline(step['polyline']['points'] as String)
            : <LatLng>[];

        steps.add(RouteStep(
          startLat: sLat,
          startLng: sLng,
          endLat: eLat,
          endLng: eLng,
          bearing: bearing,
          instruction: instruction,
          distanceText: step['distance']['text'] as String? ?? '',
          distanceM: (step['distance']['value'] as num).toDouble(),
          durationText: step['duration']['text'] as String? ?? '',
          maneuver: step['maneuver'] as String?,
          streetName: streetName,
          polylinePoints: stepPoints,
        ));
      }

      debugPrint('✅ Walking route: ${steps.length} steps, ${leg['distance']['text']}');

      return WalkingRoute(
        steps: steps,
        totalDistance: leg['distance']['text'] as String? ?? '',
        totalDuration: leg['duration']['text'] as String? ?? '',
        totalDistanceM: (leg['distance']['value'] as num).toDouble(),
        overviewPolyline: overviewPoints,
      );
    } catch (e) {
      debugPrint('❌ Directions API error: $e');
      return null;
    }
  }

  /// Compass bearing from point 1 to point 2, in degrees [0..360).
  static double _calculateBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final dLon = (lng2 - lng1) * math.pi / 180;
    final la1 = lat1 * math.pi / 180;
    final la2 = lat2 * math.pi / 180;
    final y = math.sin(dLon) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Decode a Google-encoded polyline string into a list of lat/lng points.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0, lng = 0;

    while (index < encoded.length) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  /// Remove HTML tags and collapse whitespace.
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
