/// Utility to convert provider names and booking search parameters
/// into deep pre-filled search URLs for external booking sites.
class BookingUrlHelper {
  /// Ensures [url] starts with http:// or https://. If missing, prepends https://.
  static String _sanitizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // Strip leading "//" if present (protocol-relative)
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    return 'https://$trimmed';
  }

  /// Try to deduce the provider from the raw URL domain when providerName is
  /// empty or generic (e.g. "Hotel Provider", "Flight Provider").
  static String _deduceProvider(String providerName, String rawUrl) {
    final name = providerName.trim().toLowerCase();
    // If we already know the provider, return as-is
    if (name.isNotEmpty &&
        name != 'hotel provider' &&
        name != 'flight provider') {
      return providerName;
    }
    final lowerUrl = rawUrl.toLowerCase();
    if (lowerUrl.contains('booking.com')) return 'Booking.com';
    if (lowerUrl.contains('agoda')) return 'Agoda';
    if (lowerUrl.contains('expedia')) return 'Expedia';
    if (lowerUrl.contains('hotels.com')) return 'Hotels.com';
    if (lowerUrl.contains('airbnb')) return 'Airbnb';
    if (lowerUrl.contains('google')) return 'Google';
    if (lowerUrl.contains('skyscanner')) return 'Skyscanner';
    if (lowerUrl.contains('kayak')) return 'Kayak';
    if (lowerUrl.contains('getyourguide')) return 'GetYourGuide';
    if (lowerUrl.contains('klook')) return 'Klook';
    if (lowerUrl.contains('viator')) return 'Viator';
    return providerName; // Return as-is if we can't deduce
  }

  /// Cleans location strings by removing duplicate/redundant location tokens.
  /// Example: "Germany, Germany" -> "Germany"
  /// Example: "Colombo, Sri Lanka, Sri Lanka" -> "Colombo, Sri Lanka"
  static String cleanDestination(String input) {
    var str = input.trim();
    if (str.isEmpty) return '';

    final parts = str.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    final uniqueParts = <String>[];
    for (final p in parts) {
      if (!uniqueParts.any((existing) => existing.toLowerCase() == p.toLowerCase())) {
        uniqueParts.add(p);
      }
    }
    return uniqueParts.join(', ');
  }

  /// Builds a deep search URL for hotel recommendations pre-filled with:
  /// - Hotel name / query & destination
  /// - Check-in Date (YYYY-MM-DD)
  /// - Check-out Date (YYYY-MM-DD)
  /// - Number of adult travelers
  static String buildHotelUrl({
    required String rawUrl,
    required String providerName,
    required String hotelName,
    required String destination,
    String checkInDate = '',
    String checkOutDate = '',
    int travelers = 1,
  }) {
    final sanitizedRawUrl = _sanitizeUrl(rawUrl);
    final resolvedProvider = _deduceProvider(providerName, sanitizedRawUrl);
    final provider = resolvedProvider.trim().toLowerCase();
    
    final hName = hotelName.trim();
    final dest = cleanDestination(destination);

    // For Google Hotels: AI-generated hotel names often don't exist as exact
    // matches in Google's database, causing "No results". Always use a
    // destination-based search that guarantees results.
    // For Booking.com / others: their search is more forgiving, so we can
    // include the hotel name in the query.
    String query;
    if (hName.isNotEmpty && dest.isNotEmpty && hName.toLowerCase().contains(dest.toLowerCase())) {
      query = hName;
    } else if (hName.isNotEmpty && dest.isNotEmpty) {
      query = '$hName, $dest';
    } else if (hName.isNotEmpty) {
      query = hName;
    } else {
      query = dest.isNotEmpty ? 'hotels in $dest' : 'hotels';
    }

    // Google Hotels query: always destination-based so it never shows "No results"
    final googleQuery = dest.isNotEmpty ? 'hotels in $dest' : query;
    
    final encodedQuery = Uri.encodeComponent(query);
    final encodedGoogleQuery = Uri.encodeComponent(googleQuery);
    final encodedDest = Uri.encodeComponent(dest.isNotEmpty ? dest : query);

    // Ensure destination-based encoding across all providers so no link returns zero/empty results.
    final safeDestQuery = dest.isNotEmpty ? dest : query;
    final encodedSafeDest = Uri.encodeComponent(safeDestQuery);

    // Always build provider-specific URLs to guarantee destination is pre-filled.
    if (provider.contains('google')) {
      var googleUrl = 'https://www.google.com/travel/hotels?q=$encodedGoogleQuery';
      if (checkInDate.isNotEmpty && checkOutDate.isNotEmpty) {
        googleUrl += '&dates=$checkInDate,$checkOutDate';
      }
      return googleUrl;
    } else if (provider.contains('booking')) {
      var url = 'https://www.booking.com/searchresults.html?ss=$encodedSafeDest';
      if (checkInDate.isNotEmpty) url += '&checkin=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&checkout=$checkOutDate';
      url += '&group_adults=$travelers';
      return url;
    } else if (provider.contains('agoda')) {
      var url = 'https://www.agoda.com/search?city=$encodedSafeDest';
      if (checkInDate.isNotEmpty) url += '&checkIn=$checkInDate';
      if (checkOutDate.isNotEmpty) {
        url += '&los=${_daysBetween(checkInDate, checkOutDate)}';
        url += '&checkOut=$checkOutDate';
      }
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('expedia')) {
      var url = 'https://www.expedia.com/Hotel-Search?destination=$encodedSafeDest';
      if (checkInDate.isNotEmpty) url += '&d1=${_toExpediaDate(checkInDate)}';
      if (checkOutDate.isNotEmpty) url += '&d2=${_toExpediaDate(checkOutDate)}';
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('hotels.com') || (provider.contains('hotels') && !provider.contains('google'))) {
      var url = 'https://www.hotels.com/Hotel-Search?destination=$encodedSafeDest';
      if (checkInDate.isNotEmpty) url += '&startDate=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&endDate=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('airbnb')) {
      var url = 'https://www.airbnb.com/s/$encodedSafeDest/homes';
      if (checkInDate.isNotEmpty) url += '&checkin=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&checkout=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    }

    // Unknown provider: use raw URL if available and no query, else Google Hotels search
    if (sanitizedRawUrl.isNotEmpty && dest.isEmpty) {
      return sanitizedRawUrl;
    }
    var googleUrl = 'https://www.google.com/travel/hotels?q=$encodedGoogleQuery';
    if (checkInDate.isNotEmpty && checkOutDate.isNotEmpty) {
      googleUrl += '&dates=$checkInDate,$checkOutDate';
    }
    return googleUrl;
  }

  /// Builds a deep search URL for flight recommendations pre-filled with:
  /// - Origin / Departure City & Destination
  /// - Departure Date (YYYY-MM-DD)
  /// - Return Date (YYYY-MM-DD)
  /// - Number of adult travelers
  static String buildFlightUrl({
    required String rawUrl,
    required String providerName,
    required String strategyTitle,
    required String destination,
    String departureCity = '',
    String startDate = '',
    String endDate = '',
    int travelers = 1,
    String route = '',
    List<String> airlines = const [],
  }) {
    final sanitizedRawUrl = _sanitizeUrl(rawUrl);

    // If rawUrl is already a valid pre-filled Google Flights search URL from backend, use it!
    if (sanitizedRawUrl.contains('google.com/travel/flights') && sanitizedRawUrl.contains('q=')) {
      return sanitizedRawUrl;
    }

    final resolvedProvider = _deduceProvider(providerName, sanitizedRawUrl);
    final provider = resolvedProvider.trim().toLowerCase();

    // Extract origin & destination from route if available (e.g. "CMB -> LHR" -> "CMB")
    String origin = cleanDestination(departureCity);
    String dest = cleanDestination(destination);
    if (route.isNotEmpty) {
      final parts = route.replaceAll('->', '→').split('→').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        origin = cleanDestination(parts.first);
      }
      if (parts.length > 1) {
        dest = cleanDestination(parts.last);
      }
    }

    final encodedDest = Uri.encodeComponent(dest);
    final encodedOrigin = Uri.encodeComponent(origin);

    // Always build provider-specific URLs to guarantee destination is pre-filled.
    if (provider.contains('google')) {
      var dateQ = origin.isNotEmpty
          ? 'flights from $origin to $dest'
          : 'flights to $dest';
      if (airlines.isNotEmpty) {
        dateQ += ' with ${airlines.take(2).join(", ")}';
      }
      if (startDate.isNotEmpty && endDate.isNotEmpty) {
        dateQ += ' on $startDate through $endDate';
      } else if (startDate.isNotEmpty) {
        dateQ += ' on $startDate';
      }
      return 'https://www.google.com/travel/flights?q=${Uri.encodeComponent(dateQ)}';
    } else if (provider.contains('skyscanner')) {
      if (origin.isNotEmpty && startDate.isNotEmpty && endDate.isNotEmpty) {
        return 'https://www.skyscanner.com/transport/flights-from/$encodedOrigin-to-$encodedDest/?outbounddate=$startDate&inbounddate=$endDate&adultsv2=$travelers';
      }
      return 'https://www.skyscanner.com/transport/flights/to-$encodedDest/';
    } else if (provider.contains('expedia')) {
      if (origin.isNotEmpty && startDate.isNotEmpty && endDate.isNotEmpty) {
        return 'https://www.expedia.com/Flights-Search?trip=roundtrip&leg1=from:$encodedOrigin,to:$encodedDest,departure:${startDate}TANYT&leg2=from:$encodedDest,to:$encodedOrigin,departure:${endDate}TANYT&passengers=adults:$travelers';
      }
      return 'https://www.expedia.com/Flights-Search?destination=$encodedDest';
    } else if (provider.contains('kayak')) {
      if (origin.isNotEmpty && startDate.isNotEmpty && endDate.isNotEmpty) {
        return 'https://www.kayak.com/flights/$encodedOrigin-$encodedDest/$startDate/$endDate/${travelers}adults';
      }
      return 'https://www.kayak.com/flights?a=nexaround&destination=$encodedDest';
    }

    // Unknown provider: use Google Flights as fallback with destination
    if (dest.isNotEmpty) {
      var dateQ = origin.isNotEmpty
          ? 'flights from $origin to $dest'
          : 'flights to $dest';
      if (airlines.isNotEmpty) {
        dateQ += ' with ${airlines.take(2).join(", ")}';
      }
      if (startDate.isNotEmpty && endDate.isNotEmpty) {
        dateQ += ' on $startDate through $endDate';
      } else if (startDate.isNotEmpty) {
        dateQ += ' on $startDate';
      }
      return 'https://www.google.com/travel/flights?q=${Uri.encodeComponent(dateQ)}';
    }

    return sanitizedRawUrl.isNotEmpty
        ? sanitizedRawUrl
        : 'https://www.google.com/travel/flights';
  }

  /// Builds a deep search URL for tour/activity providers pre-filled with destination.
  static String buildToursUrl({
    required String rawUrl,
    required String providerName,
    required String destination,
  }) {
    final sanitizedRawUrl = _sanitizeUrl(rawUrl);
    final resolvedProvider = _deduceProvider(providerName, sanitizedRawUrl);
    final provider = resolvedProvider.trim().toLowerCase();
    final dest = cleanDestination(destination);
    final encodedDest = Uri.encodeComponent(dest);

    if (provider.contains('getyourguide')) {
      return 'https://www.getyourguide.com/s?q=$encodedDest';
    } else if (provider.contains('klook')) {
      return 'https://www.klook.com/search?query=$encodedDest';
    } else if (provider.contains('viator')) {
      return 'https://www.viator.com/search/$encodedDest';
    }

    // Unknown tour provider: use raw URL if available
    return sanitizedRawUrl.isNotEmpty
        ? sanitizedRawUrl
        : 'https://www.google.com/search?q=${Uri.encodeComponent("tours activities $dest")}';
  }

  // ── Date format helpers ────────────────────────────────────────────────────

  /// Convert YYYY-MM-DD to MM/DD/YYYY for Expedia deep links.
  static String _toExpediaDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return '${parts[1]}/${parts[2]}/${parts[0]}';
      }
    } catch (_) {}
    return dateStr;
  }

  /// Calculate the number of days between two YYYY-MM-DD date strings.
  static int _daysBetween(String start, String end) {
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      final diff = e.difference(s).inDays;
      return diff > 0 ? diff : 1;
    } catch (_) {
      return 1;
    }
  }
}
