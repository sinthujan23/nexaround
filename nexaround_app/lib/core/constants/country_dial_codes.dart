/// Country dial codes for the phone number input.
///
/// Each entry holds the ISO alpha-2 code, the country name, the international
/// dial code (without +), and a min/max digit count for the national part so
/// the form can validate without a heavy regex library.
class CountryDialCode {
  final String iso;
  final String name;
  final String dialCode;
  final int minDigits;
  final int maxDigits;

  const CountryDialCode({
    required this.iso,
    required this.name,
    required this.dialCode,
    this.minDigits = 6,
    this.maxDigits = 12,
  });

  /// Flag emoji from 2-letter ISO code.
  String get flag {
    if (iso.length != 2) return '🌐';
    final first = iso.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = iso.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  /// "+94" etc.
  String get formatted => '+$dialCode';

  /// "+94 · Sri Lanka"
  String get displayLabel => '$formatted · $name';
}

/// All country dial codes, ordered with common travel destinations first.
///
/// The first entry is the default picked by the form.
const List<CountryDialCode> countryDialCodes = [
  // Popular travel / booking countries first
  CountryDialCode(iso: 'LK', name: 'Sri Lanka', dialCode: '94', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'IN', name: 'India', dialCode: '91', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'US', name: 'United States', dialCode: '1', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'GB', name: 'United Kingdom', dialCode: '44', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'AE', name: 'United Arab Emirates', dialCode: '971', minDigits: 7, maxDigits: 9),
  CountryDialCode(iso: 'QA', name: 'Qatar', dialCode: '974', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'AU', name: 'Australia', dialCode: '61', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'CA', name: 'Canada', dialCode: '1', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'DE', name: 'Germany', dialCode: '49', minDigits: 6, maxDigits: 12),
  CountryDialCode(iso: 'FR', name: 'France', dialCode: '33', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'IT', name: 'Italy', dialCode: '39', minDigits: 6, maxDigits: 11),
  CountryDialCode(iso: 'ES', name: 'Spain', dialCode: '34', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'JP', name: 'Japan', dialCode: '81', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'SG', name: 'Singapore', dialCode: '65', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'MY', name: 'Malaysia', dialCode: '60', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'TH', name: 'Thailand', dialCode: '66', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'MV', name: 'Maldives', dialCode: '960', minDigits: 7, maxDigits: 7),
  CountryDialCode(iso: 'SA', name: 'Saudi Arabia', dialCode: '966', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'OM', name: 'Oman', dialCode: '968', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'BH', name: 'Bahrain', dialCode: '973', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'KW', name: 'Kuwait', dialCode: '965', minDigits: 8, maxDigits: 8),

  // Rest of world, alphabetical
  CountryDialCode(iso: 'AF', name: 'Afghanistan', dialCode: '93', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'AL', name: 'Albania', dialCode: '355', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'DZ', name: 'Algeria', dialCode: '213', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'AR', name: 'Argentina', dialCode: '54', minDigits: 10, maxDigits: 11),
  CountryDialCode(iso: 'AM', name: 'Armenia', dialCode: '374', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'AT', name: 'Austria', dialCode: '43', minDigits: 7, maxDigits: 12),
  CountryDialCode(iso: 'AZ', name: 'Azerbaijan', dialCode: '994', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'BD', name: 'Bangladesh', dialCode: '880', minDigits: 8, maxDigits: 10),
  CountryDialCode(iso: 'BY', name: 'Belarus', dialCode: '375', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'BE', name: 'Belgium', dialCode: '32', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'BT', name: 'Bhutan', dialCode: '975', minDigits: 7, maxDigits: 8),
  CountryDialCode(iso: 'BO', name: 'Bolivia', dialCode: '591', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'BA', name: 'Bosnia', dialCode: '387', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'BR', name: 'Brazil', dialCode: '55', minDigits: 10, maxDigits: 11),
  CountryDialCode(iso: 'BN', name: 'Brunei', dialCode: '673', minDigits: 7, maxDigits: 7),
  CountryDialCode(iso: 'BG', name: 'Bulgaria', dialCode: '359', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'KH', name: 'Cambodia', dialCode: '855', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'CM', name: 'Cameroon', dialCode: '237', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'CL', name: 'Chile', dialCode: '56', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'CN', name: 'China', dialCode: '86', minDigits: 11, maxDigits: 11),
  CountryDialCode(iso: 'CO', name: 'Colombia', dialCode: '57', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'CR', name: 'Costa Rica', dialCode: '506', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'HR', name: 'Croatia', dialCode: '385', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'CU', name: 'Cuba', dialCode: '53', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'CY', name: 'Cyprus', dialCode: '357', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'CZ', name: 'Czechia', dialCode: '420', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'DK', name: 'Denmark', dialCode: '45', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'DO', name: 'Dominican Republic', dialCode: '1809'),
  CountryDialCode(iso: 'EC', name: 'Ecuador', dialCode: '593', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'EG', name: 'Egypt', dialCode: '20', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'ET', name: 'Ethiopia', dialCode: '251', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'FI', name: 'Finland', dialCode: '358', minDigits: 7, maxDigits: 10),
  CountryDialCode(iso: 'GE', name: 'Georgia', dialCode: '995', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'GH', name: 'Ghana', dialCode: '233', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'GR', name: 'Greece', dialCode: '30', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'GT', name: 'Guatemala', dialCode: '502', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'HN', name: 'Honduras', dialCode: '504', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'HK', name: 'Hong Kong', dialCode: '852', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'HU', name: 'Hungary', dialCode: '36', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'IS', name: 'Iceland', dialCode: '354', minDigits: 7, maxDigits: 7),
  CountryDialCode(iso: 'ID', name: 'Indonesia', dialCode: '62', minDigits: 9, maxDigits: 12),
  CountryDialCode(iso: 'IR', name: 'Iran', dialCode: '98', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'IQ', name: 'Iraq', dialCode: '964', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'IE', name: 'Ireland', dialCode: '353', minDigits: 7, maxDigits: 9),
  CountryDialCode(iso: 'IL', name: 'Israel', dialCode: '972', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'JM', name: 'Jamaica', dialCode: '1876'),
  CountryDialCode(iso: 'JO', name: 'Jordan', dialCode: '962', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'KZ', name: 'Kazakhstan', dialCode: '7', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'KE', name: 'Kenya', dialCode: '254', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'KR', name: 'South Korea', dialCode: '82', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'LA', name: 'Laos', dialCode: '856', minDigits: 8, maxDigits: 10),
  CountryDialCode(iso: 'LV', name: 'Latvia', dialCode: '371', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'LB', name: 'Lebanon', dialCode: '961', minDigits: 7, maxDigits: 8),
  CountryDialCode(iso: 'LT', name: 'Lithuania', dialCode: '370', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'LU', name: 'Luxembourg', dialCode: '352', minDigits: 6, maxDigits: 9),
  CountryDialCode(iso: 'MG', name: 'Madagascar', dialCode: '261', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'MT', name: 'Malta', dialCode: '356', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'MX', name: 'Mexico', dialCode: '52', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'MA', name: 'Morocco', dialCode: '212', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'MZ', name: 'Mozambique', dialCode: '258', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'MM', name: 'Myanmar', dialCode: '95', minDigits: 7, maxDigits: 10),
  CountryDialCode(iso: 'NP', name: 'Nepal', dialCode: '977', minDigits: 8, maxDigits: 10),
  CountryDialCode(iso: 'NL', name: 'Netherlands', dialCode: '31', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'NZ', name: 'New Zealand', dialCode: '64', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'NG', name: 'Nigeria', dialCode: '234', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'NO', name: 'Norway', dialCode: '47', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'PK', name: 'Pakistan', dialCode: '92', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'PA', name: 'Panama', dialCode: '507', minDigits: 7, maxDigits: 8),
  CountryDialCode(iso: 'PY', name: 'Paraguay', dialCode: '595', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'PE', name: 'Peru', dialCode: '51', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'PH', name: 'Philippines', dialCode: '63', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'PL', name: 'Poland', dialCode: '48', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'PT', name: 'Portugal', dialCode: '351', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'RO', name: 'Romania', dialCode: '40', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'RU', name: 'Russia', dialCode: '7', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'RW', name: 'Rwanda', dialCode: '250', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'SN', name: 'Senegal', dialCode: '221', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'RS', name: 'Serbia', dialCode: '381', minDigits: 8, maxDigits: 9),
  CountryDialCode(iso: 'SK', name: 'Slovakia', dialCode: '421', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'SI', name: 'Slovenia', dialCode: '386', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'ZA', name: 'South Africa', dialCode: '27', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'SE', name: 'Sweden', dialCode: '46', minDigits: 7, maxDigits: 10),
  CountryDialCode(iso: 'CH', name: 'Switzerland', dialCode: '41', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'TW', name: 'Taiwan', dialCode: '886', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'TZ', name: 'Tanzania', dialCode: '255', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'TT', name: 'Trinidad and Tobago', dialCode: '1868'),
  CountryDialCode(iso: 'TN', name: 'Tunisia', dialCode: '216', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'TR', name: 'Turkey', dialCode: '90', minDigits: 10, maxDigits: 10),
  CountryDialCode(iso: 'UA', name: 'Ukraine', dialCode: '380', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'UY', name: 'Uruguay', dialCode: '598', minDigits: 8, maxDigits: 8),
  CountryDialCode(iso: 'UZ', name: 'Uzbekistan', dialCode: '998', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'VN', name: 'Vietnam', dialCode: '84', minDigits: 9, maxDigits: 10),
  CountryDialCode(iso: 'ZM', name: 'Zambia', dialCode: '260', minDigits: 9, maxDigits: 9),
  CountryDialCode(iso: 'ZW', name: 'Zimbabwe', dialCode: '263', minDigits: 9, maxDigits: 9),
];

/// Find a [CountryDialCode] by ISO code, or null.
CountryDialCode? dialCodeForIso(String iso) {
  final upper = iso.toUpperCase();
  for (final c in countryDialCodes) {
    if (c.iso == upper) return c;
  }
  return null;
}

/// Try to detect the country from a phone string that starts with a dial code
/// (with or without +). Returns the best match, or null.
CountryDialCode? detectCountryFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;

  // Try longest dial codes first for best match (e.g. +1809 before +1).
  CountryDialCode? best;
  int bestLen = 0;
  for (final c in countryDialCodes) {
    if (digits.startsWith(c.dialCode) && c.dialCode.length > bestLen) {
      best = c;
      bestLen = c.dialCode.length;
    }
  }
  return best;
}
