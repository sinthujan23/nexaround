/// Enquiry form rules, with no Flutter or plugin imports so they can be unit
/// tested directly.
///
/// Mirrors `validate_enquiry_payload` in
/// `nexaround_backend/app/services/experience_format.py`. The server is the
/// authority — this exists so the user sees the problem before a round trip,
/// not so the client can decide. Change both together.
library;

/// Digits only, which is also what `wa.me` needs. Matches the backend's
/// `whatsapp_number()`: fewer than 7 digits is not a dialable number.
String? enquiryPhoneDigits(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length < 7 ? null : digits;
}

/// Returns the first problem with the form, or null when it is ready to send.
String? validateEnquiry({
  required String name,
  required String phone,
  String? email,
  int? partySize,
}) {
  if (name.trim().length < 2) return 'Please enter your name.';

  if (enquiryPhoneDigits(phone) == null) {
    return 'Please enter a valid phone number.';
  }

  final trimmedEmail = (email ?? '').trim();
  if (trimmedEmail.isNotEmpty &&
      (!trimmedEmail.contains('@') ||
          !trimmedEmail.split('@').last.contains('.'))) {
    return 'Please enter a valid email address.';
  }

  if (partySize != null && (partySize < 1 || partySize > 100)) {
    return 'Party size must be between 1 and 100.';
  }

  return null;
}
