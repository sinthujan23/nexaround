import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nexaround_app/core/constants/api_constants.dart';

/// Represents a real, live-verified hotel listing fetched via SerpAPI (Google Hotels).
class SerpHotel {
  final String name;
  final double rating;
  final int reviews;
  final String pricePerNight;
  final String totalPrice;
  final String description;
  final String photoUrl;
  final String bookingUrl;
  final String providerName;

  const SerpHotel({
    required this.name,
    required this.rating,
    required this.reviews,
    required this.pricePerNight,
    required this.totalPrice,
    required this.description,
    required this.photoUrl,
    required this.bookingUrl,
    required this.providerName,
  });
}

/// Service to query SerpAPI's Google Hotels engine for real-time hotel availability,
/// pricing, ratings, and deep booking URLs based on trip dates and destination.
class SerpHotelService {
  static Future<List<SerpHotel>> fetchAvailableHotels({
    required String destination,
    String checkInDate = '',
    String checkOutDate = '',
    int adults = 2,
    String currency = 'USD',
    double minRating = 4.0,
  }) async {
    final apiKey = ApiConstants.serpApiKey;
    if (apiKey.isEmpty) {
      debugPrint('SerpAPI key not set; skipping live hotel search.');
      return [];
    }

    try {
      final query = 'hotels in $destination';
      final Map<String, String> params = {
        'engine': 'google_hotels',
        'q': query,
        if (checkInDate.isNotEmpty) 'check_in_date': checkInDate,
        if (checkOutDate.isNotEmpty) 'check_out_date': checkOutDate,
        'adults': adults.toString(),
        'currency': currency,
        'api_key': apiKey,
      };

      final Uri uri = Uri.parse('https://serpapi.com/search.json').replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('SerpAPI Google Hotels error: HTTP ${response.statusCode}');
        return [];
      }

      final Map<String, dynamic> body = jsonDecode(response.body);
      final List<dynamic> properties = body['properties'] ?? [];
      final List<SerpHotel> results = [];

      for (final p in properties) {
        if (p is! Map<String, dynamic>) continue;
        final name = p['name']?.toString() ?? '';
        if (name.isEmpty) continue;

        final rating = (p['overall_rating'] as num?)?.toDouble() ?? 0.0;
        
        // Filter out hotels below minimum rating
        if (rating < minRating) continue;
        
        final reviews = (p['reviews'] as num?)?.toInt() ?? 0;
        final pricePerNight = p['rate_per_night']?['lowest']?.toString() ?? '';
        final totalPrice = p['total_rate']?['lowest']?.toString() ?? '';
        final description = p['description']?.toString() ?? 'Verified hotel offering great amenities and convenient access.';
        
        final images = p['images'] as List<dynamic>?;
        final photoUrl = (images != null && images.isNotEmpty) ? images.first['original_image']?.toString() ?? '' : '';

        // Extract direct booking URL or deep search link
        final link = p['link']?.toString() ?? 'https://www.booking.com/searchresults.html?ss=${Uri.encodeComponent(name)}';

        results.add(
          SerpHotel(
            name: name,
            rating: rating,
            reviews: reviews,
            pricePerNight: pricePerNight,
            totalPrice: totalPrice,
            description: description,
            photoUrl: photoUrl,
            bookingUrl: link,
            providerName: 'Booking.com',
          ),
        );

        if (results.length >= 4) break;
      }

      return results;
    } catch (e) {
      debugPrint('SerpHotelService exception: $e');
      return [];
    }
  }
}
