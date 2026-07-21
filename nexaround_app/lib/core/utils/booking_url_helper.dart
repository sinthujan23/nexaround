/// Utility to convert provider names and booking search parameters
/// into deep pre-filled search URLs for external booking sites.
class BookingUrlHelper {
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
    // If rawUrl is already a deep URL (has query parameters), use it directly
    if (rawUrl.contains('?') && (rawUrl.contains('&') || rawUrl.contains('='))) {
      return rawUrl;
    }

    final provider = providerName.trim().toLowerCase();
    final query = hotelName.trim().isNotEmpty
        ? '${hotelName.trim()} ${destination.trim()}'
        : destination.trim();
    final encodedQuery = Uri.encodeComponent(query);
    final encodedDest = Uri.encodeComponent(destination.trim());

    if (provider.contains('booking')) {
      var url = 'https://www.booking.com/searchresults.html?ss=$encodedQuery';
      if (checkInDate.isNotEmpty) url += '&checkin=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&checkout=$checkOutDate';
      url += '&group_adults=$travelers';
      return url;
    } else if (provider.contains('agoda')) {
      var url = 'https://www.agoda.com/search?text=$encodedQuery';
      if (checkInDate.isNotEmpty) url += '&checkIn=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&checkOut=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('expedia')) {
      var url = 'https://www.expedia.com/Hotel-Search?destination=$encodedQuery';
      if (checkInDate.isNotEmpty) url += '&startDate=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&endDate=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('hotels')) {
      var url = 'https://www.hotels.com/Hotel-Search?destination=$encodedQuery';
      if (checkInDate.isNotEmpty) url += '&startDate=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&endDate=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    } else if (provider.contains('airbnb')) {
      var url = 'https://www.airbnb.com/s/$encodedDest/homes?query=$encodedQuery';
      if (checkInDate.isNotEmpty) url += '&checkin=$checkInDate';
      if (checkOutDate.isNotEmpty) url += '&checkout=$checkOutDate';
      url += '&adults=$travelers';
      return url;
    }

    return rawUrl.isNotEmpty
        ? rawUrl
        : 'https://www.google.com/travel/hotels?q=$encodedQuery';
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
  }) {
    // If rawUrl is already a deep URL (has query parameters), use it directly
    if (rawUrl.contains('?') && (rawUrl.contains('&') || rawUrl.contains('='))) {
      return rawUrl;
    }

    final provider = providerName.trim().toLowerCase();
    final origin = departureCity.trim().isNotEmpty ? departureCity.trim() : '';
    final dest = destination.trim();
    final encodedDest = Uri.encodeComponent(dest);
    final encodedOrigin = Uri.encodeComponent(origin);

    if (provider.contains('google')) {
      var dateQ = origin.isNotEmpty
          ? 'flights from $origin to $dest'
          : 'flights to $dest';
      if (startDate.isNotEmpty && endDate.isNotEmpty) {
        dateQ += ' on $startDate return $endDate';
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
      return 'https://www.kayak.com/flights/$encodedDest';
    }

    return rawUrl.isNotEmpty
        ? rawUrl
        : 'https://www.google.com/travel/flights?q=${Uri.encodeComponent("flights to $dest")}';
  }
}
