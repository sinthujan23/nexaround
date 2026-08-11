import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/utils/booking_url_helper.dart';

void main() {
  group('BookingUrlHelper tests', () {
    test('Google Travel uses hotel name and destination search with pre-filled dates', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Google Travel',
        hotelName: 'Lilit Bang Lumphu Hotel',
        destination: 'Bangkok',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 1,
      );

      expect(url, contains('google.com/travel/hotels'));
      expect(url, contains('q=Lilit%20Bang%20Lumphu%20Hotel%20Bangkok'));
      expect(url, contains('dates=2026-08-10,2026-08-12'));
    });

    test('Booking.com provider resolves to booking.com deep search query with checkin/checkout dates', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Booking.com',
        hotelName: 'Lilit Bang Lumphu Hotel',
        destination: 'Bangkok',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 2,
      );

      expect(url, contains('booking.com/searchresults.html'));
      expect(url, contains('ss=Lilit%20Bang%20Lumphu%20Hotel%20Bangkok'));
      expect(url, contains('checkin=2026-08-10'));
      expect(url, contains('checkout=2026-08-12'));
    });

    test('Agoda provider without direct agoda serpApiLink falls back to Google Travel search', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Agoda',
        hotelName: 'Taj Fateh Prakash Palace',
        destination: 'Udaipur',
        checkInDate: '2026-08-11',
        checkOutDate: '2026-08-13',
        travelers: 1,
        serpApiLink: 'https://www.tajhotels.com/en-in/taj-fateh-prakash-palace-udaipur/',
      );

      // Non-agoda serpApiLink must not be used under Agoda provider label; fallback to Google Travel
      expect(url, contains('google.com/travel/hotels'));
      expect(url, contains('q=Taj%20Fateh%20Prakash%20Palace%20Udaipur'));
    });

    test('cleanHotelQuery strips room type suffixes and noise', () {
      expect(
        BookingUrlHelper.cleanHotelQuery('De Lavender Luxury sea view Guest Houses - Family Room with Sea View', 'Karnataka'),
        equals('De Lavender Luxury sea view Guest Houses Karnataka'),
      );
      expect(
        BookingUrlHelper.cleanHotelQuery('Eco Village - No Alcohol Zone - Three-Bedroom Villa', 'Karnataka'),
        equals('Eco Village - No Alcohol Zone Karnataka'),
      );
    });

    test('cleanDestination removes duplicate location tokens', () {
      expect(BookingUrlHelper.cleanDestination('Germany, Germany'), equals('Germany'));
      expect(BookingUrlHelper.cleanDestination('Colombo, Sri Lanka, Sri Lanka'), equals('Colombo, Sri Lanka'));
      expect(BookingUrlHelper.cleanDestination(''), equals(''));
    });

    test('buildHotelUrl cleans duplicate destination tokens like Germany, Germany', () {
      final url = BookingUrlHelper.buildHotelUrl(
        rawUrl: '',
        providerName: 'Google Travel',
        hotelName: 'Grand Hotel Downtown',
        destination: 'Germany, Germany',
        checkInDate: '2026-08-10',
        checkOutDate: '2026-08-12',
        travelers: 1,
      );

      expect(url, contains('google.com/travel/hotels'));
      expect(url, contains('q=Grand%20Hotel%20Downtown%20Germany'));
      expect(url, isNot(contains('Germany%2C%20Germany')));
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
