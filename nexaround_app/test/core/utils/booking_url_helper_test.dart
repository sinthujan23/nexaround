import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';

void main() {
  group('BookingUrlHelper tests', () {
    test('Google Hotels provider resolves to google.com/travel/hotels with hotel name query', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Google Hotels',
        hotelName: 'Lilit Bang Lumphu Hotel - Bangkok',
        destination: 'Bangkok',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 1,
      );

      expect(url, contains('google.com/travel/hotels'));
      expect(url, contains('q=Lilit%20Bang%20Lumphu%20Hotel%20-%20Bangkok'));
      expect(url, isNot(contains('hotels.com')));
    });

    test('Booking.com provider resolves to booking.com with hotel name search query', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Booking.com',
        hotelName: 'Lilit Bang Lumphu Hotel - Bangkok',
        destination: 'Bangkok',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 2,
      );

      expect(url, contains('booking.com/searchresults.html'));
      expect(url, contains('ss=Lilit%20Bang%20Lumphu%20Hotel%20-%20Bangkok'));
    });

    test('Google Flights provider resolves to google.com/travel/flights with airlines', () {
      final url = BookingUrlHelper.buildFlightUrl(
        rawUrl: '',
        providerName: 'Google Flights',
        strategyTitle: 'Fly from Kochi with layover',
        destination: 'Addis Ababa',
        departureCity: 'Kochi',
        startDate: '2026-08-12',
        endDate: '2026-08-19',
        travelers: 1,
        route: 'COK → ADD',
        airlines: ['IndiGo', 'Ethiopian Airlines'],
      );

      expect(url, contains('google.com/travel/flights'));
      expect(url, contains('flights%20from%20COK%20to%20ADD%20with%20IndiGo%2C%20Ethiopian%20Airlines'));
    });
  });
}
