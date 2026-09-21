import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/utils/distance_format.dart';
import 'package:nexaround_app/features/experiences/domain/enquiry_validation.dart';

/// These mirror `nexaround_backend/tests/test_experiences.py`. The server is
/// the authority on every rule here; if the two ever disagree, the user sees a
/// form that passes locally and is rejected on submit.
void main() {
  group('enquiry validation', () {
    test('a complete enquiry passes', () {
      expect(
        validateEnquiry(
          name: 'Test Traveller',
          phone: '+94 71 555 0000',
          email: 'a@b.com',
          partySize: 4,
        ),
        isNull,
      );
    });

    test('a one-character name is rejected', () {
      expect(
        validateEnquiry(name: 'A', phone: '+94715550000'),
        'Please enter your name.',
      );
    });

    test('a number too short to dial is rejected', () {
      expect(
        validateEnquiry(name: 'Traveller', phone: '123'),
        'Please enter a valid phone number.',
      );
    });

    test('an absent email is fine because phone is the required channel', () {
      expect(validateEnquiry(name: 'Traveller', phone: '+94715550000'), isNull);
    });

    test('a malformed email is rejected', () {
      expect(
        validateEnquiry(
          name: 'Traveller',
          phone: '+94715550000',
          email: 'not-an-email',
        ),
        'Please enter a valid email address.',
      );
    });

    test('an implausible party size is rejected', () {
      for (final size in [0, 101]) {
        expect(
          validateEnquiry(
            name: 'Traveller',
            phone: '+94715550000',
            partySize: size,
          ),
          isNotNull,
        );
      }
    });
  });

  group('enquiryPhoneDigits', () {
    test('strips everything that is not a digit, including the plus', () {
      // wa.me rejects a leading '+', so this must match the backend's
      // whatsapp_number() exactly.
      expect(enquiryPhoneDigits('+94 77 123 4567'), '94771234567');
    });

    test('returns null for anything too short to be a number', () {
      expect(enquiryPhoneDigits('123'), isNull);
      expect(enquiryPhoneDigits(null), isNull);
      expect(enquiryPhoneDigits(''), isNull);
    });
  });

  group('formatDistanceCoarse', () {
    test('drops the decimal above 10 km', () {
      // 340.0 km reads as false precision on the "nothing nearby" banner.
      expect(formatDistanceCoarse(340000), '340 km');
      expect(formatDistanceCoarse(8666946), '8667 km');
    });

    test('defers to formatDistance below 10 km, where resolution matters', () {
      expect(formatDistanceCoarse(450), '450 m');
      expect(formatDistanceCoarse(3974), '4.0 km');
    });
  });
}
