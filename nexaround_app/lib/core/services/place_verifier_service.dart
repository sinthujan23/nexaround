import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:nexaround_app/core/constants/api_constants.dart';

/// Verifies AI-suggested place names against the Google Places Text Search API.
/// Used to filter hallucinated or too-far-away locations from Neva's discovery results.
class PlaceVerifierService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/place/textsearch/json';

  /// Helper to calculate distance between two coordinates in meters
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // double.pi / 180
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) *
        (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742000 * math.asin(math.sqrt(a)); // 2 * R; R = 6371000 meters
  }

  /// Returns `true` if the [placeName] exists in Google Maps near [locationContext]
  /// and is optionally within 15km of the [centerLat]/[centerLng] center.
  static Future<bool> placeExists(
    String placeName,
    String locationContext, {
    double? centerLat,
    double? centerLng,
  }) async {
    final apiKey = ApiConstants.googleMapsApiKey;
    if (apiKey.isEmpty) {
      print('🔍 PlaceVerifier: API key is empty, skipping verification.');
      return true; // Can't verify without key — let it through
    }

    final queryStr = '$placeName $locationContext';
    final query = Uri.encodeQueryComponent(queryStr);
    final url = Uri.parse('$_baseUrl?query=$query&key=$apiKey');

    print('🔍 PlaceVerifier: Querying Google Places API for "$queryStr"');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'] as String?;
        final results = data['results'] as List?;
        print('🔍 PlaceVerifier: API Response status: $status, results count: ${results?.length ?? 0}');
        if (status == 'OK' && results != null && results.isNotEmpty) {
          if (centerLat != null && centerLng != null) {
            // Check if any search result is within 25km (to match app search constraints)
            for (final result in results) {
              final geometry = result['geometry'] as Map?;
              final loc = geometry?['location'] as Map?;
              final lat = (loc?['lat'] as num?)?.toDouble();
              final lng = (loc?['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final distM = _calculateDistance(centerLat, centerLng, lat, lng);
                print('🔍 PlaceVerifier: Found "$placeName" at ($lat, $lng). Distance from user: ${(distM / 1000).toStringAsFixed(2)} km');
                if (distM <= 25000) {
                  print('🔍 PlaceVerifier: "$placeName" is within 25km (valid).');
                  return true;
                }
              }
            }
            print('🔍 PlaceVerifier: "$placeName" found but is TOO FAR (> 25km). Flagging as invalid.');
            return false; // None of the found places are within 25km
          }
          return true;
        } else {
          print('🔍 PlaceVerifier: "$placeName" NOT found in Google Maps. Flagging as invalid.');
          return false;
        }
      } else {
        print('🔍 PlaceVerifier: HTTP request failed with code: ${response.statusCode}');
      }
    } catch (e) {
      print('🔍 PlaceVerifier: Error checking place "$placeName": $e');
      // Network error — allow the place through rather than silently hiding content
    }
    return true;
  }

  /// Parses all [[Place Name]] tokens from [text] and returns the unique list.
  static List<String> extractPlaceNames(String text) {
    final regex = RegExp(r'\[\[([^\]]+)\]\]');
    return regex
        .allMatches(text)
        .map((m) => m.group(1)!.trim())
        .toSet()
        .toList();
  }

  /// Verifies every [[Place Name]] in [aiResponse] against Google Places.
  /// Returns a set of place names that could NOT be verified (hallucinated or too far).
  static Future<Set<String>> findHallucinatedPlaces(
    String aiResponse,
    String locationContext, {
    double? centerLat,
    double? centerLng,
  }) async {
    final places = extractPlaceNames(aiResponse);
    if (places.isEmpty) return {};

    final Set<String> hallucinated = {};

    await Future.wait(
      places.map((place) async {
        final valid = await placeExists(
          place,
          locationContext,
          centerLat: centerLat,
          centerLng: centerLng,
        );
        if (!valid) hallucinated.add(place);
      }),
    );

    return hallucinated;
  }

  /// Removes entire stop blocks for hallucinated places from the Gemini response.
  static String filterHallucinatedStops(
    String aiResponse,
    Set<String> hallucinatedPlaces,
  ) {
    if (hallucinatedPlaces.isEmpty) return aiResponse;

    var result = aiResponse;

    for (final place in hallucinatedPlaces) {
      // Match the stop block: from the line containing [[Place]] to the next
      // line that starts a new stop (line starting with - **  or ### or similar).
      // We use a greedy approach: remove the paragraph that contains [[place]].
      final escapedPlace = RegExp.escape(place);

      // Strategy: split by double-newline paragraphs, drop any paragraph
      // that references this hallucinated place.
      final paragraphs = result.split(RegExp(r'\n(?=[-*]|\d+\.|##|###|\*\*)'));
      final filtered = paragraphs
          .where((p) => !p.contains('[[${place}]]') && !p.contains('**${place}**'))
          .toList();
      result = filtered.join('\n');
    }

    return result.trim();
  }

  /// Removes any lines containing external Google Maps links or raw HTTP/HTTPS URLs
  /// to keep the layout clean and ensure the user only relies on clickable place names.
  static String cleanRawUrls(String text) {
    final lines = text.split('\n');
    final cleanedLines = lines.where((line) {
      final lower = line.toLowerCase();
      if (lower.contains('google.com/maps') || 
          lower.contains('maps.google') ||
          lower.contains('http://') || 
          lower.contains('https://')) {
        return false;
      }
      return true;
    }).toList();
    return cleanedLines.join('\n');
  }
}
