/// Can this budget buy the trip at all?
///
/// Mirrors `app/services/trip_cost_floor.py` on the backend. The server is the
/// authority and rejects an impossible budget with HTTP 422; this copy exists
/// so the traveller is told before pressing Generate rather than after a round
/// trip. Keep the two in sync — a test in the backend suite compares them.
///
/// Two principles, same as the server's:
///   * The figures are hostel-and-street-food *floors*, not realistic budgets.
///     They separate "impossible" from "tight", and being too low is the safe
///     direction.
///   * When the destination cannot be identified, [minimumBudget] returns null
///     and the caller must allow the request. Blocking a real trip is a worse
///     failure than letting an absurd one through.
class TripCostFloor {
  const TripCostFloor._();

  /// Daily on-the-ground minimum per traveller, in USD.
  static const Map<String, double> dailyFloorUsd = {
    'budget': 20.0,
    'moderate': 35.0,
    'upper': 60.0,
    'expensive': 90.0,
    'premium': 140.0,
  };

  static const String defaultTier = 'moderate';

  /// Cheapest plausible return airfare for any international hop, per traveller.
  static const double internationalFlightFloorUsd =
      120.0;

  static const Map<String, String> countryTier = {
    'AF': 'budget', 'AL': 'budget', 'AM': 'budget', 'BA': 'budget', 'BD': 'budget', 'BF': 'budget',
    'BI': 'budget', 'BJ': 'budget', 'BO': 'budget', 'BY': 'budget', 'CD': 'budget', 'CF': 'budget',
    'CG': 'budget', 'CI': 'budget', 'CM': 'budget', 'CO': 'budget', 'EC': 'budget', 'EG': 'budget',
    'ER': 'budget', 'ET': 'budget', 'GE': 'budget', 'GH': 'budget', 'GM': 'budget', 'GN': 'budget',
    'GT': 'budget', 'GW': 'budget', 'HN': 'budget', 'HT': 'budget', 'ID': 'budget', 'IN': 'budget',
    'IR': 'budget', 'KG': 'budget', 'KH': 'budget', 'KM': 'budget', 'LA': 'budget', 'LK': 'budget',
    'LR': 'budget', 'LS': 'budget', 'MD': 'budget', 'MG': 'budget', 'MK': 'budget', 'ML': 'budget',
    'MM': 'budget', 'MN': 'budget', 'MR': 'budget', 'MW': 'budget', 'MZ': 'budget', 'NE': 'budget',
    'NI': 'budget', 'NP': 'budget', 'PE': 'budget', 'PH': 'budget', 'PK': 'budget', 'PY': 'budget',
    'RS': 'budget', 'RW': 'budget', 'SD': 'budget', 'SL': 'budget', 'SN': 'budget', 'SO': 'budget',
    'SS': 'budget', 'ST': 'budget', 'SV': 'budget', 'SY': 'budget', 'SZ': 'budget', 'TD': 'budget',
    'TG': 'budget', 'TJ': 'budget', 'TL': 'budget', 'TN': 'budget', 'UA': 'budget', 'UG': 'budget',
    'UZ': 'budget', 'VN': 'budget', 'XK': 'budget', 'YE': 'budget', 'ZM': 'budget', 'ZW': 'budget',
    'AO': 'moderate', 'AR': 'moderate', 'AZ': 'moderate', 'BG': 'moderate', 'BR': 'moderate', 'BW': 'moderate',
    'BZ': 'moderate', 'CL': 'moderate', 'CN': 'moderate', 'CR': 'moderate', 'CU': 'moderate', 'CV': 'moderate',
    'DJ': 'moderate', 'DM': 'moderate', 'DO': 'moderate', 'DZ': 'moderate', 'FJ': 'moderate', 'FM': 'moderate',
    'GA': 'moderate', 'GD': 'moderate', 'GQ': 'moderate', 'GY': 'moderate', 'HU': 'moderate', 'IQ': 'moderate',
    'JM': 'moderate', 'JO': 'moderate', 'KE': 'moderate', 'KI': 'moderate', 'KP': 'moderate', 'KZ': 'moderate',
    'LB': 'moderate', 'LY': 'moderate', 'MA': 'moderate', 'ME': 'moderate', 'MH': 'moderate', 'MU': 'moderate',
    'MX': 'moderate', 'MY': 'moderate', 'NA': 'moderate', 'NG': 'moderate', 'NR': 'moderate', 'PA': 'moderate',
    'PG': 'moderate', 'PL': 'moderate', 'PS': 'moderate', 'RO': 'moderate', 'RU': 'moderate', 'SB': 'moderate',
    'SK': 'moderate', 'SR': 'moderate', 'TH': 'moderate', 'TM': 'moderate', 'TO': 'moderate', 'TR': 'moderate',
    'TT': 'moderate', 'TV': 'moderate', 'TZ': 'moderate', 'UY': 'moderate', 'VC': 'moderate', 'VE': 'moderate',
    'VU': 'moderate', 'WS': 'moderate', 'ZA': 'moderate', 'AE': 'upper', 'BH': 'upper', 'BN': 'upper',
    'CY': 'upper', 'CZ': 'upper', 'EE': 'upper', 'ES': 'upper', 'GR': 'upper', 'HR': 'upper',
    'IT': 'upper', 'KR': 'upper', 'KW': 'upper', 'LT': 'upper', 'LV': 'upper', 'MT': 'upper',
    'OM': 'upper', 'PT': 'upper', 'QA': 'upper', 'SA': 'upper', 'SI': 'upper', 'SM': 'upper',
    'TW': 'upper', 'VA': 'upper', 'AD': 'expensive', 'AG': 'expensive', 'AT': 'expensive', 'AU': 'expensive',
    'BB': 'expensive', 'BE': 'expensive', 'BS': 'expensive', 'BT': 'expensive', 'CA': 'expensive', 'DE': 'expensive',
    'FI': 'expensive', 'FR': 'expensive', 'GB': 'expensive', 'HK': 'expensive', 'IE': 'expensive', 'IL': 'expensive',
    'JP': 'expensive', 'KN': 'expensive', 'LC': 'expensive', 'MO': 'expensive', 'MV': 'expensive', 'NL': 'expensive',
    'NZ': 'expensive', 'PW': 'expensive', 'SC': 'expensive', 'SE': 'expensive', 'SG': 'expensive', 'US': 'expensive',
    'CH': 'premium', 'DK': 'premium', 'IS': 'premium', 'LI': 'premium', 'LU': 'premium', 'MC': 'premium',
    'NO': 'premium',
  };

  /// Free-text place names we recognise. Only unambiguous ones belong here: a
  /// wrong entry blocks a real trip, a missing one merely allows one through.
  static const Map<String, String> placeCountry = {
    'sri lanka': 'LK', 'colombo': 'LK', 'kandy': 'LK',
    'galle': 'LK', 'jaffna': 'LK', 'trincomalee': 'LK',
    'ella': 'LK', 'sigiriya': 'LK', 'nuwara eliya': 'LK',
    'anuradhapura': 'LK', 'negombo': 'LK', 'mirissa': 'LK',
    'arugam bay': 'LK', 'batticaloa': 'LK', 'matara': 'LK',
    'kinniya': 'LK', 'dambulla': 'LK', 'polonnaruwa': 'LK',
    'hikkaduwa': 'LK', 'dubai': 'AE', 'abu dhabi': 'AE',
    'uae': 'AE', 'united arab emirates': 'AE', 'sharjah': 'AE',
    'doha': 'QA', 'qatar': 'QA', 'riyadh': 'SA',
    'jeddah': 'SA', 'saudi arabia': 'SA', 'muscat': 'OM',
    'oman': 'OM', 'kuwait': 'KW', 'bahrain': 'BH',
    'manama': 'BH', 'istanbul': 'TR', 'turkey': 'TR',
    'antalya': 'TR', 'india': 'IN', 'delhi': 'IN',
    'mumbai': 'IN', 'chennai': 'IN', 'bangalore': 'IN',
    'goa': 'IN', 'kerala': 'IN', 'kochi': 'IN',
    'jaipur': 'IN', 'agra': 'IN', 'nepal': 'NP',
    'kathmandu': 'NP', 'pokhara': 'NP', 'maldives': 'MV',
    'male': 'MV', 'bangkok': 'TH', 'thailand': 'TH',
    'phuket': 'TH', 'chiang mai': 'TH', 'krabi': 'TH',
    'pattaya': 'TH', 'singapore': 'SG', 'malaysia': 'MY',
    'kuala lumpur': 'MY', 'penang': 'MY', 'langkawi': 'MY',
    'vietnam': 'VN', 'hanoi': 'VN', 'ho chi minh': 'VN',
    'da nang': 'VN', 'indonesia': 'ID', 'bali': 'ID',
    'jakarta': 'ID', 'cambodia': 'KH', 'siem reap': 'KH',
    'phnom penh': 'KH', 'philippines': 'PH', 'manila': 'PH',
    'cebu': 'PH', 'boracay': 'PH', 'japan': 'JP',
    'tokyo': 'JP', 'osaka': 'JP', 'kyoto': 'JP',
    'south korea': 'KR', 'seoul': 'KR', 'busan': 'KR',
    'china': 'CN', 'beijing': 'CN', 'shanghai': 'CN',
    'hong kong': 'HK', 'taiwan': 'TW', 'taipei': 'TW',
    'london': 'GB', 'united kingdom': 'GB', 'uk': 'GB',
    'england': 'GB', 'scotland': 'GB', 'edinburgh': 'GB',
    'manchester': 'GB', 'paris': 'FR', 'france': 'FR',
    'nice': 'FR', 'germany': 'DE', 'berlin': 'DE',
    'munich': 'DE', 'frankfurt': 'DE', 'amsterdam': 'NL',
    'netherlands': 'NL', 'italy': 'IT', 'rome': 'IT',
    'milan': 'IT', 'venice': 'IT', 'florence': 'IT',
    'naples': 'IT', 'spain': 'ES', 'barcelona': 'ES',
    'madrid': 'ES', 'seville': 'ES', 'portugal': 'PT',
    'lisbon': 'PT', 'porto': 'PT', 'greece': 'GR',
    'athens': 'GR', 'santorini': 'GR', 'mykonos': 'GR',
    'switzerland': 'CH', 'zurich': 'CH', 'geneva': 'CH',
    'interlaken': 'CH', 'norway': 'NO', 'oslo': 'NO',
    'iceland': 'IS', 'reykjavik': 'IS', 'denmark': 'DK',
    'copenhagen': 'DK', 'sweden': 'SE', 'stockholm': 'SE',
    'finland': 'FI', 'helsinki': 'FI', 'prague': 'CZ',
    'czech republic': 'CZ', 'vienna': 'AT', 'austria': 'AT',
    'poland': 'PL', 'warsaw': 'PL', 'krakow': 'PL',
    'hungary': 'HU', 'budapest': 'HU', 'croatia': 'HR',
    'dubrovnik': 'HR', 'ireland': 'IE', 'dublin': 'IE',
    'belgium': 'BE', 'brussels': 'BE', 'usa': 'US',
    'united states': 'US', 'new york': 'US', 'los angeles': 'US',
    'san francisco': 'US', 'las vegas': 'US', 'miami': 'US',
    'chicago': 'US', 'canada': 'CA', 'toronto': 'CA',
    'vancouver': 'CA', 'montreal': 'CA', 'mexico': 'MX',
    'cancun': 'MX', 'mexico city': 'MX', 'brazil': 'BR',
    'rio de janeiro': 'BR', 'sao paulo': 'BR', 'argentina': 'AR',
    'buenos aires': 'AR', 'peru': 'PE', 'lima': 'PE',
    'colombia': 'CO', 'chile': 'CL', 'egypt': 'EG',
    'cairo': 'EG', 'morocco': 'MA', 'marrakech': 'MA',
    'south africa': 'ZA', 'cape town': 'ZA', 'johannesburg': 'ZA',
    'kenya': 'KE', 'nairobi': 'KE', 'tanzania': 'TZ',
    'zanzibar': 'TZ', 'australia': 'AU', 'sydney': 'AU',
    'melbourne': 'AU', 'new zealand': 'NZ', 'auckland': 'NZ',
    'queenstown': 'NZ', 'afghanistan': 'AF', 'albania': 'AL',
    'algeria': 'DZ', 'america': 'US', 'andorra': 'AD',
    'angola': 'AO', 'antigua': 'AG', 'antigua and barbuda': 'AG',
    'armenia': 'AM', 'azerbaijan': 'AZ', 'bahamas': 'BS',
    'bangladesh': 'BD', 'barbados': 'BB', 'belarus': 'BY',
    'belize': 'BZ', 'benin': 'BJ', 'bhutan': 'BT',
    'bolivia': 'BO', 'bosnia': 'BA', 'bosnia and herzegovina': 'BA',
    'botswana': 'BW', 'britain': 'GB', 'brunei': 'BN',
    'bulgaria': 'BG', 'burkina faso': 'BF', 'burma': 'MM',
    'burundi': 'BI', 'cabo verde': 'CV', 'cameroon': 'CM',
    'cape verde': 'CV', 'central african republic': 'CF', 'chad': 'TD',
    'comoros': 'KM', 'congo': 'CG', 'congo-kinshasa': 'CD',
    'costa rica': 'CR', 'cote d\'ivoire': 'CI', 'cuba': 'CU',
    'cyprus': 'CY', 'czechia': 'CZ', 'democratic republic of the congo': 'CD',
    'djibouti': 'DJ', 'dominica': 'DM', 'dominican republic': 'DO',
    'dprk': 'KP', 'drc': 'CD', 'east timor': 'TL',
    'ecuador': 'EC', 'el salvador': 'SV', 'emirates': 'AE',
    'equatorial guinea': 'GQ', 'eritrea': 'ER', 'estonia': 'EE',
    'eswatini': 'SZ', 'ethiopia': 'ET', 'fiji': 'FJ',
    'gabon': 'GA', 'gambia': 'GM', 'georgia': 'GE',
    'ghana': 'GH', 'great britain': 'GB', 'grenada': 'GD',
    'guatemala': 'GT', 'guinea': 'GN', 'guinea-bissau': 'GW',
    'guyana': 'GY', 'haiti': 'HT', 'holland': 'NL',
    'honduras': 'HN', 'iran': 'IR', 'iraq': 'IQ',
    'israel': 'IL', 'ivory coast': 'CI', 'jamaica': 'JM',
    'jordan': 'JO', 'kazakhstan': 'KZ', 'kiribati': 'KI',
    'korea': 'KR', 'kosovo': 'XK', 'kyrgyzstan': 'KG',
    'laos': 'LA', 'latvia': 'LV', 'lebanon': 'LB',
    'lesotho': 'LS', 'liberia': 'LR', 'libya': 'LY',
    'liechtenstein': 'LI', 'lithuania': 'LT', 'luxembourg': 'LU',
    'macao': 'MO', 'macedonia': 'MK', 'madagascar': 'MG',
    'malawi': 'MW', 'mali': 'ML', 'malta': 'MT',
    'marshall islands': 'MH', 'mauritania': 'MR', 'mauritius': 'MU',
    'micronesia': 'FM', 'moldova': 'MD', 'monaco': 'MC',
    'mongolia': 'MN', 'montenegro': 'ME', 'mozambique': 'MZ',
    'myanmar': 'MM', 'namibia': 'NA', 'nauru': 'NR',
    'new guinea': 'PG', 'nicaragua': 'NI', 'niger': 'NE',
    'nigeria': 'NG', 'north korea': 'KP', 'north macedonia': 'MK',
    'northern ireland': 'GB', 'pakistan': 'PK', 'palau': 'PW',
    'palestine': 'PS', 'panama': 'PA', 'papua': 'PG',
    'papua new guinea': 'PG', 'paraguay': 'PY', 'republic of korea': 'KR',
    'romania': 'RO', 'russia': 'RU', 'rwanda': 'RW',
    's korea': 'KR', 'saint kitts and nevis': 'KN', 'saint lucia': 'LC',
    'saint vincent and the grenadines': 'VC', 'samoa': 'WS', 'san marino': 'SM',
    'sao tome and principe': 'ST', 'senegal': 'SN', 'serbia': 'RS',
    'seychelles': 'SC', 'sierra leone': 'SL', 'slovakia': 'SK',
    'slovenia': 'SI', 'solomon islands': 'SB', 'somalia': 'SO',
    'south sudan': 'SS', 'st kitts': 'KN', 'st lucia': 'LC',
    'sudan': 'SD', 'suriname': 'SR', 'swaziland': 'SZ',
    'syria': 'SY', 'tajikistan': 'TJ', 'timor-leste': 'TL',
    'togo': 'TG', 'tonga': 'TO', 'trinidad': 'TT',
    'trinidad and tobago': 'TT', 'tunisia': 'TN', 'turkmenistan': 'TM',
    'tuvalu': 'TV', 'uganda': 'UG', 'ukraine': 'UA',
    'united states of america': 'US', 'uruguay': 'UY', 'uzbekistan': 'UZ',
    'vanuatu': 'VU', 'vatican': 'VA', 'vatican city': 'VA',
    'venezuela': 'VE', 'wales': 'GB', 'yemen': 'YE',
    'zambia': 'ZM', 'zimbabwe': 'ZW',
  };

  /// Units of each currency per 1 USD. Used only to compare against a floor,
  /// never to price anything.
  static const Map<String, double> fxPerUsd = {
    'USD': 1.0,
    'LKR': 300.0,
    'INR': 83.0,
    'EUR': 0.92,
    'GBP': 0.79,
    'AUD': 1.52,
    'CAD': 1.36,
    'JPY': 150.0,
    'CNY': 7.24,
    'SGD': 1.34,
    'MYR': 4.7,
    'THB': 36.0,
    'AED': 3.67,
    'SAR': 3.75,
    'QAR': 3.64,
    'CHF': 0.88,
    'NZD': 1.64,
    'ZAR': 18.5,
    'TRY': 32.0,
    'IDR': 15700.0,
    'PHP': 56.0,
    'VND': 25000.0,
    'PKR': 278.0,
    'BDT': 110.0,
    'NPR': 133.0,
    'MVR': 15.4,
    'KRW': 1330.0,
    'HKD': 7.82,
    'TWD': 32.0,
    'BRL': 5.05,
    'MXN': 17.0,
    'EGP': 48.0,
    'MAD': 10.0,
    'KES': 130.0,
    'NGN': 1500.0,
    'SEK': 10.5,
    'NOK': 10.7,
    'DKK': 6.9,
    'PLN': 3.95,
    'CZK': 23.0,
    'HUF': 360.0,
    'RON': 4.57,
    'ARS': 900.0,
  };

  /// Below this length a place name is too collidable to match loosely:
  /// 'nice' turned "somewhere nice" into a trip to France, and 'male', 'goa'
  /// and 'ella' hide inside ordinary words. Short names still match when they
  /// are the whole input, which is what a destination field normally holds.
  static const int _minLooseMatch = 5;

  static String _normalise(String text, {bool keepCommas = false}) {
    var raw = text.toLowerCase();
    if (!keepCommas) raw = raw.replaceAll(',', ' ');
    return raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
  }

  /// Best-effort country code for a free-text place name; null when unsure.
  ///
  /// Three widening steps: the whole input, then any comma-separated part of it
  /// ('Dubai, UAE'), then a run of whole words inside it. Substring matching is
  /// deliberately not used — it read 'nice' out of 'somewhere nice'.
  static String? countryFor(String place) {
    final text = _normalise(place);
    if (text.isEmpty) return null;

    final exact = placeCountry[text];
    if (exact != null) return exact;

    for (final part in _normalise(place, keepCommas: true).split(',')) {
      final hit = placeCountry[part.trim()];
      if (hit != null) return hit;
    }

    final words = text.split(' ');
    String? best;
    var bestLen = 0;
    placeCountry.forEach((name, code) {
      if (name.length < _minLooseMatch || name.length <= bestLen) return;
      final nameWords = name.split(' ');
      for (var i = 0; i + nameWords.length <= words.length; i++) {
        var match = true;
        for (var j = 0; j < nameWords.length; j++) {
          if (words[i + j] != nameWords[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          best = code;
          bestLen = name.length;
          return;
        }
      }
    });
    return best;
  }

  static double _roundUp(double value) {
    if (value <= 0) return 0;
    for (final step in [10, 50, 100, 500, 1000, 5000, 10000]) {
      if (value <= step * 20) return (value / step).ceil() * step.toDouble();
    }
    return (value / 50000).ceil() * 50000.0;
  }

  /// Cheapest budget that could conceivably buy this trip, in [currency].
  ///
  /// Returns null when the destination or currency is unrecognised — the caller
  /// must then allow the request through.
  static double? minimumBudget({
    required String destination,
    required int days,
    int travelers = 1,
    String currency = 'USD',
    String departureCountry = '',
    bool includeFlights = false,
  }) {
    final country = countryFor(destination);
    if (country == null) return null;

    final code = currency.trim().toUpperCase();
    final rate = fxPerUsd[code];
    if (rate == null) return null;

    final d = days < 1 ? 1 : days;
    final t = travelers < 1 ? 1 : travelers;

    final tier = countryTier[country] ?? defaultTier;
    final daily = dailyFloorUsd[tier] ?? dailyFloorUsd[defaultTier]!;
    final groundUsd = daily * d * t;

    // A flight floor applies only when a border is actually crossed. A blank
    // departure country is treated as domestic: under-counting is the safe
    // direction.
    final departure = departureCountry.trim().toUpperCase();
    final departureCode =
        departure.length == 2 ? departure : (countryFor(departureCountry) ?? '');
    final crossesBorder = departureCode.isNotEmpty && departureCode != country;
    final flightUsd = ((crossesBorder || includeFlights) && departureCode != country)
        ? internationalFlightFloorUsd * t
        : 0.0;

    return _roundUp((groundUsd + flightUsd) * rate);
  }

  /// One sentence a traveller can act on, matching the server's wording.
  static String shortfallMessage({
    required String destination,
    required double minimum,
    required String currency,
    required int days,
    int travelers = 1,
    bool includesFlight = false,
  }) {
    final amount = '$currency ${_thousands(minimum)}';
    final who = travelers == 1 ? '' : ' for $travelers travellers';
    final flight = includesFlight ? ' including flights' : '';
    // Attributive, so always singular: 'a 3-day trip', never 'a 3-days trip'.
    return 'A $days-day trip to $destination$who needs at least '
        'about $amount$flight. Please raise your budget to continue.';
  }

  static String _thousands(double value) {
    final digits = value.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}
