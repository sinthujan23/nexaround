import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';

void main() {
  group('BookingUrlHelper tests', () {
    test('Google Hotels always uses destination-based search to avoid No Results', () {
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
      // Should use destination-based query, NOT hotel name (which may not exist)
      expect(url, contains('q=hotels%20in%20Bangkok'));
      expect(url, isNot(contains('hotels.com')));
    });

    test('Booking.com provider resolves to booking.com with destination search query', () {
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
      expect(url, contains('ss=Bangkok'));
    });

    test('cleanDestination removes duplicate location tokens', () {
      expect(BookingUrlHelper.cleanDestination('Germany, Germany'), equals('Germany'));
      expect(BookingUrlHelper.cleanDestination('Colombo, Sri Lanka, Sri Lanka'), equals('Colombo, Sri Lanka'));
      expect(BookingUrlHelper.cleanDestination(''), equals(''));
    });

    test('buildHotelUrl cleans duplicate destination tokens like Germany, Germany', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Google Hotels',
        hotelName: 'Grand Hotel Downtown',
        destination: 'Germany, Germany',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 1,
      );

      expect(url, contains('google.com/travel/hotels'));
      // Should use destination-based query with cleaned destination
      expect(url, contains('q=hotels%20in%20Germany'));
      expect(url, isNot(contains('Germany%2C%20Germany')));
    });

    test('Booking.com uses destination in query to guarantee valid results', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Booking.com',
        hotelName: 'Grand Hotel Downtown',
        destination: 'Germany',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 1,
      );

      expect(url, contains('booking.com/searchresults.html'));
      expect(url, contains('ss=Germany'));
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
