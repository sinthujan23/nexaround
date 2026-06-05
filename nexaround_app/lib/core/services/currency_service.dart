import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';

class CurrencyService {
  static const List<Map<String, String>> supportedCurrencies = [
    {'code': 'USD', 'name': 'US Dollar', 'symbol': r'$', 'flag': '🇺🇸'},
    {'code': 'EUR', 'name': 'Euro', 'symbol': '€', 'flag': '🇪🇺'},
    {'code': 'GBP', 'name': 'British Pound', 'symbol': '£', 'flag': '🇬🇧'},
    {'code': 'LKR', 'name': 'Sri Lankan Rupee', 'symbol': 'රු', 'flag': '🇱🇰'},
    {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹', 'flag': '🇮🇳'},
    {'code': 'JPY', 'name': 'Japanese Yen', 'symbol': '¥', 'flag': '🇯🇵'},
    {'code': 'CAD', 'name': 'Canadian Dollar', 'symbol': r'C$', 'flag': '🇨🇦'},
    {'code': 'AUD', 'name': 'Australian Dollar', 'symbol': r'A$', 'flag': '🇦🇺'},
    {'code': 'CHF', 'name': 'Swiss Franc', 'symbol': 'CHF', 'flag': '🇨🇭'},
    {'code': 'CNY', 'name': 'Chinese Yuan', 'symbol': '¥', 'flag': '🇨🇳'},
    {'code': 'NZD', 'name': 'New Zealand Dollar', 'symbol': r'NZ$', 'flag': '🇳🇿'},
    {'code': 'AED', 'name': 'UAE Dirham', 'symbol': 'AED', 'flag': '🇦🇪'},
    {'code': 'SAR', 'name': 'Saudi Riyal', 'symbol': 'SR', 'flag': '🇸🇦'},
    {'code': 'SGD', 'name': 'Singapore Dollar', 'symbol': r'S$', 'flag': '🇸🇬'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit', 'symbol': 'RM', 'flag': '🇲🇾'},
    {'code': 'THB', 'name': 'Thai Baht', 'symbol': '฿', 'flag': '🇹🇭'},
    {'code': 'IDR', 'name': 'Indonesian Rupiah', 'symbol': 'Rp', 'flag': '🇮🇩'},
    {'code': 'PHP', 'name': 'Philippine Peso', 'symbol': '₱', 'flag': '🇵🇭'},
    {'code': 'KRW', 'name': 'South Korean Won', 'symbol': '₩', 'flag': '🇰🇷'},
    {'code': 'TRY', 'name': 'Turkish Lira', 'symbol': '₺', 'flag': '🇹🇷'},
    {'code': 'RUB', 'name': 'Russian Ruble', 'symbol': '₽', 'flag': '🇷🇺'},
    {'code': 'BRL', 'name': 'Brazilian Real', 'symbol': r'R$', 'flag': '🇧🇷'},
    {'code': 'ZAR', 'name': 'South African Rand', 'symbol': 'R', 'flag': '🇿🇦'},
    {'code': 'MXN', 'name': 'Mexican Peso', 'symbol': r'Mex$', 'flag': '🇲🇽'},
    {'code': 'SEK', 'name': 'Swedish Krona', 'symbol': 'kr', 'flag': '🇸🇪'},
    {'code': 'NOK', 'name': 'Norwegian Krone', 'symbol': 'kr', 'flag': '🇳🇴'},
    {'code': 'DKK', 'name': 'Danish Krone', 'symbol': 'kr', 'flag': '🇩🇰'},
    {'code': 'HKD', 'name': 'Hong Kong Dollar', 'symbol': r'HK$', 'flag': '🇭🇰'},
    {'code': 'TWD', 'name': 'New Taiwan Dollar', 'symbol': r'NT$', 'flag': '🇹🇼'},
    {'code': 'ILS', 'name': 'Israeli Shekel', 'symbol': '₪', 'flag': '🇮🇱'},
    {'code': 'EGP', 'name': 'Egyptian Pound', 'symbol': 'E£', 'flag': '🇪🇬'},
    {'code': 'PKR', 'name': 'Pakistani Rupee', 'symbol': 'Rs', 'flag': '🇵🇰'},
    {'code': 'BDT', 'name': 'Bangladeshi Taka', 'symbol': '৳', 'flag': '🇧🇩'},
    {'code': 'VND', 'name': 'Vietnamese Dong', 'symbol': '₫', 'flag': '🇻🇳'},
    {'code': 'PLN', 'name': 'Polish Zloty', 'symbol': 'zł', 'flag': '🇵🇱'},
    {'code': 'NGN', 'name': 'Nigerian Naira', 'symbol': '₦', 'flag': '🇳🇬'},
    {'code': 'COP', 'name': 'Colombian Peso', 'symbol': r'Col$', 'flag': '🇨🇴'},
    {'code': 'ARS', 'name': 'Argentine Peso', 'symbol': r'$', 'flag': '🇦🇷'},
    {'code': 'CLP', 'name': 'Chilean Peso', 'symbol': r'CLP$', 'flag': '🇨🇱'},
    {'code': 'PEN', 'name': 'Peruvian Sol', 'symbol': 'S/.', 'flag': '🇵🇪'},
    {'code': 'HUF', 'name': 'Hungarian Forint', 'symbol': 'Ft', 'flag': '🇭🇺'},
    {'code': 'CZK', 'name': 'Czech Koruna', 'symbol': 'Kč', 'flag': '🇨🇿'},
    {'code': 'RON', 'name': 'Romanian Leu', 'symbol': 'lei', 'flag': '🇷🇴'},
    {'code': 'BGN', 'name': 'Bulgarian Lev', 'symbol': 'лв', 'flag': '🇧🇬'},
    {'code': 'UAH', 'name': 'Ukrainian Hryvnia', 'symbol': '₴', 'flag': '🇺🇦'},
    {'code': 'KZT', 'name': 'Kazakhstani Tenge', 'symbol': '₸', 'flag': '🇰🇿'},
    {'code': 'QAR', 'name': 'Qatari Riyal', 'symbol': 'QR', 'flag': '🇶🇦'},
    {'code': 'KWD', 'name': 'Kuwaiti Dinar', 'symbol': 'KD', 'flag': '🇰🇼'},
    {'code': 'BHD', 'name': 'Bahraini Dinar', 'symbol': 'BD', 'flag': '🇧🇭'},
    {'code': 'OMR', 'name': 'Omani Rial', 'symbol': 'RO', 'flag': '🇴🇲'},
    {'code': 'JOD', 'name': 'Jordanian Dinar', 'symbol': 'JD', 'flag': '🇯🇴'},
    {'code': 'LBP', 'name': 'Lebanese Pound', 'symbol': 'L£', 'flag': '🇱🇧'},
    {'code': 'IQD', 'name': 'Iraqi Dinar', 'symbol': 'ID', 'flag': '🇮🇶'},
    {'code': 'YER', 'name': 'Yemeni Rial', 'symbol': 'YR', 'flag': '🇾🇪'},
    {'code': 'IRR', 'name': 'Iranian Rial', 'symbol': 'IR', 'flag': '🇮🇷'},
    {'code': 'AFN', 'name': 'Afghan Afghani', 'symbol': '؋', 'flag': '🇦🇫'},
    {'code': 'ALL', 'name': 'Albanian Lek', 'symbol': 'L', 'flag': '🇦🇱'},
    {'code': 'AMD', 'name': 'Armenian Dram', 'symbol': '֏', 'flag': '🇦🇲'},
    {'code': 'ANG', 'name': 'Neth. Antillean Guilder', 'symbol': 'ƒ', 'flag': '🇨🇼'},
    {'code': 'AOA', 'name': 'Angolan Kwanza', 'symbol': 'Kz', 'flag': '🇦🇴'},
    {'code': 'AWG', 'name': 'Aruban Florin', 'symbol': 'ƒ', 'flag': '🇦🇼'},
    {'code': 'AZN', 'name': 'Azerbaijani Manat', 'symbol': '₼', 'flag': '🇦🇿'},
    {'code': 'BAM', 'name': 'Bosnia-Herzegovina Mark', 'symbol': 'KM', 'flag': '🇧🇦'},
    {'code': 'BBD', 'name': 'Barbadian Dollar', 'symbol': r'$', 'flag': '🇧🇧'},
    {'code': 'BIF', 'name': 'Burundian Franc', 'symbol': 'FBu', 'flag': '🇧🇮'},
    {'code': 'BMD', 'name': 'Bermudian Dollar', 'symbol': r'$', 'flag': '🇧🇲'},
    {'code': 'BND', 'name': 'Brunei Dollar', 'symbol': r'$', 'flag': '🇧🇳'},
    {'code': 'BOB', 'name': 'Bolivian Boliviano', 'symbol': 'Bs', 'flag': '🇧🇴'},
    {'code': 'BSD', 'name': 'Bahamian Dollar', 'symbol': r'$', 'flag': '🇧🇸'},
    {'code': 'BTN', 'name': 'Bhutanese Ngultrum', 'symbol': 'Nu', 'flag': '🇧🇹'},
    {'code': 'BWP', 'name': 'Botswanan Pula', 'symbol': 'P', 'flag': '🇧🇼'},
    {'code': 'BYN', 'name': 'Belarusian Ruble', 'symbol': 'Br', 'flag': '🇧🇾'},
    {'code': 'BZD', 'name': 'Belize Dollar', 'symbol': r'$', 'flag': '🇧🇿'},
    {'code': 'CDF', 'name': 'Congolese Franc', 'symbol': 'FC', 'flag': '🇨🇩'},
    {'code': 'CVE', 'name': 'Cape Verdean Escudo', 'symbol': r'$', 'flag': '🇨🇻'},
    {'code': 'DJF', 'name': 'Djiboutian Franc', 'symbol': 'Fdj', 'flag': '🇩🇯'},
    {'code': 'DOP', 'name': 'Dominican Peso', 'symbol': r'RD$', 'flag': '🇩🇴'},
    {'code': 'DZD', 'name': 'Algerian Dinar', 'symbol': 'DA', 'flag': '🇩🇿'},
    {'code': 'ERN', 'name': 'Eritrean Nakfa', 'symbol': 'Nfk', 'flag': '🇪🇷'},
    {'code': 'ETB', 'name': 'Ethiopian Birr', 'symbol': 'Br', 'flag': '🇪🇹'},
    {'code': 'FJD', 'name': 'Fijian Dollar', 'symbol': r'$', 'flag': '🇫🇯'},
    {'code': 'FKP', 'name': 'Falkland Islands Pound', 'symbol': '£', 'flag': '🇫🇰'},
    {'code': 'GEL', 'name': 'Georgian Lari', 'symbol': '₾', 'flag': '🇬🇪'},
    {'code': 'GHS', 'name': 'Ghanaian Cedi', 'symbol': '₵', 'flag': '🇬🇭'},
    {'code': 'GIP', 'name': 'Gibraltar Pound', 'symbol': '£', 'flag': '🇬🇮'},
    {'code': 'GMD', 'name': 'Gambian Dalasi', 'symbol': 'D', 'flag': '🇬🇲'},
    {'code': 'GNF', 'name': 'Guinean Franc', 'symbol': 'FG', 'flag': '🇬🇳'},
    {'code': 'GTQ', 'name': 'Guatemala Quetzal', 'symbol': 'Q', 'flag': '🇬🇹'},
    {'code': 'GYD', 'name': 'Guyanaese Dollar', 'symbol': r'$', 'flag': '🇬🇾'},
    {'code': 'HNL', 'name': 'Honduran Lempira', 'symbol': 'L', 'flag': '🇭🇳'},
    {'code': 'HTG', 'name': 'Haitian Gourde', 'symbol': 'G', 'flag': '🇭🇹'},
    {'code': 'ISK', 'name': 'Icelandic Krona', 'symbol': 'kr', 'flag': '🇮🇸'},
    {'code': 'JMD', 'name': 'Jamaican Dollar', 'symbol': r'$', 'flag': '🇯🇲'},
    {'code': 'KES', 'name': 'Kenyan Shilling', 'symbol': 'Ksh', 'flag': '🇰🇪'},
    {'code': 'KGS', 'name': 'Kyrgyzstani Som', 'symbol': 'сом', 'flag': '🇰🇬'},
    {'code': 'KHR', 'name': 'Cambodian Riel', 'symbol': '៛', 'flag': '🇰🇭'},
    {'code': 'KMF', 'name': 'Comorian Franc', 'symbol': 'CF', 'flag': '🇰🇲'},
    {'code': 'KPW', 'name': 'North Korean Won', 'symbol': '₩', 'flag': '🇰🇵'},
    {'code': 'LAK', 'name': 'Laotian Kip', 'symbol': '₭', 'flag': '🇱🇦'},
    {'code': 'LSL', 'name': 'Lesotho Loti', 'symbol': 'L', 'flag': '🇱🇸'},
    {'code': 'LYD', 'name': 'Libyan Dinar', 'symbol': 'LD', 'flag': '🇱🇾'},
    {'code': 'MAD', 'name': 'Moroccan Dirham', 'symbol': 'DH', 'flag': '🇲🇦'},
    {'code': 'MDL', 'name': 'Moldovan Leu', 'symbol': 'L', 'flag': '🇲🇩'},
    {'code': 'MGA', 'name': 'Malagasy Ariary', 'symbol': 'Ar', 'flag': '🇲🇬'},
    {'code': 'MKD', 'name': 'Macedonian Denar', 'symbol': 'den', 'flag': '🇲🇰'},
    {'code': 'MMK', 'name': 'Myanmar Kyat', 'symbol': 'K', 'flag': '🇲🇲'},
    {'code': 'MNT', 'name': 'Mongolian Togrog', 'symbol': '₮', 'flag': '🇲🇳'},
    {'code': 'MOP', 'name': 'Macanese Pataca', 'symbol': r'MOP$', 'flag': '🇲🇴'},
    {'code': 'MRU', 'name': 'Mauritanian Ouguiya', 'symbol': 'UM', 'flag': '🇲🇷'},
    {'code': 'MUR', 'name': 'Mauritian Rupee', 'symbol': 'Rs', 'flag': '🇲🇺'},
    {'code': 'MVR', 'name': 'Maldivian Rufiyaa', 'symbol': 'Rf', 'flag': '🇲🇻'},
    {'code': 'MWK', 'name': 'Malawian Kwacha', 'symbol': 'MK', 'flag': '🇲🇼'},
    {'code': 'MZN', 'name': 'Mozambican Metical', 'symbol': 'MT', 'flag': '🇲🇿'},
    {'code': 'NAD', 'name': 'Namibian Dollar', 'symbol': r'$', 'flag': '🇳🇦'},
    {'code': 'NIO', 'name': 'Nicaraguan Cordoba', 'symbol': r'C$', 'flag': '🇳🇮'},
    {'code': 'NPR', 'name': 'Nepalese Rupee', 'symbol': 'Rs', 'flag': '🇳🇵'},
    {'code': 'PAB', 'name': 'Panamanian Balboa', 'symbol': 'B/.', 'flag': '🇵🇦'},
    {'code': 'PGK', 'name': 'Papua New Guinean Kina', 'symbol': 'K', 'flag': '🇵🇬'},
    {'code': 'PYG', 'name': 'Paraguayan Guarani', 'symbol': '₲', 'flag': '🇵🇾'},
    {'code': 'RWF', 'name': 'Rwandan Franc', 'symbol': 'FRw', 'flag': '🇷🇼'},
    {'code': 'SBD', 'name': 'Solomon Islands Dollar', 'symbol': r'$', 'flag': '🇸🇧'},
    {'code': 'SCR', 'name': 'Seychellois Rupee', 'symbol': 'SR', 'flag': '🇸🇨'},
    {'code': 'SDG', 'name': 'Sudanese Pound', 'symbol': 'LS', 'flag': '🇸🇩'},
    {'code': 'SHP', 'name': 'St. Helena Pound', 'symbol': '£', 'flag': '🇸🇭'},
    {'code': 'SLL', 'name': 'Sierra Leonean Leone', 'symbol': 'Le', 'flag': '🇸🇱'},
    {'code': 'SOS', 'name': 'Somali Shilling', 'symbol': 'Sh', 'flag': '🇸🇴'},
    {'code': 'SRD', 'name': 'Surinamese Dollar', 'symbol': r'$', 'flag': '🇸🇷'},
    {'code': 'SSP', 'name': 'South Sudanese Pound', 'symbol': '£', 'flag': '🇸🇸'},
    {'code': 'STN', 'name': 'Sao Tome Dobra', 'symbol': 'Db', 'flag': '🇸🇹'},
    {'code': 'SVC', 'name': 'Salvadoran Colon', 'symbol': '₡', 'flag': '🇸🇻'},
    {'code': 'SZL', 'name': 'Swazi Lilangeni', 'symbol': 'E', 'flag': '🇸🇿'},
    {'code': 'TJS', 'name': 'Tajikistani Somoni', 'symbol': 'ЅМ', 'flag': '🇹🇯'},
    {'code': 'TMT', 'name': 'Turkmenistani Manat', 'symbol': 'T', 'flag': '🇹🇲'},
    {'code': 'TND', 'name': 'Tunisian Dinar', 'symbol': 'DT', 'flag': '🇹🇳'},
    {'code': 'TOP', 'name': 'Tongan Pa\'anga', 'symbol': r'T$', 'flag': '🇹🇴'},
    {'code': 'TTD', 'name': 'Trinidad & Tobago Dollar', 'symbol': r'TT$', 'flag': '🇹🇹'},
    {'code': 'TZS', 'name': 'Tanzanian Shilling', 'symbol': 'TSh', 'flag': '🇹🇿'},
    {'code': 'UGX', 'name': 'Ugandan Shilling', 'symbol': 'USh', 'flag': '🇺🇬'},
    {'code': 'UYU', 'name': 'Uruguayan Peso', 'symbol': r'$U', 'flag': '🇺🇾'},
    {'code': 'UZS', 'name': 'Uzbekistani Som', 'symbol': 'so\'m', 'flag': '🇺🇿'},
    {'code': 'VES', 'name': 'Venezuelan Bolivar', 'symbol': 'Bs.S', 'flag': '🇻🇪'},
    {'code': 'VUV', 'name': 'Vanuatu Vatu', 'symbol': 'VT', 'flag': '🇻🇺'},
    {'code': 'WST', 'name': 'Samoan Tala', 'symbol': r'WS$', 'flag': '🇼🇸'},
    {'code': 'XAF', 'name': 'Central African CFA Franc', 'symbol': 'FCFA', 'flag': '🇨🇲'},
    {'code': 'XCD', 'name': 'East Caribbean Dollar', 'symbol': r'$', 'flag': '🇦🇬'},
    {'code': 'XOF', 'name': 'West African CFA Franc', 'symbol': 'CFA', 'flag': '🇸🇳'},
    {'code': 'XPF', 'name': 'CFP Franc', 'symbol': '₣', 'flag': '🇵🇫'},
    {'code': 'ZMW', 'name': 'Zambian Kwacha', 'symbol': 'ZK', 'flag': '🇿🇲'},
    {'code': 'ZWL', 'name': 'Zimbabwean Dollar', 'symbol': r'$', 'flag': '🇿🇼'},
  ];
  // We can use a free API like ExchangeRate-API or similar
  static const String _baseUrl = 'https://open.er-api.com/v6/latest';

  static Future<Map<String, double>> getExchangeRates(String baseCurrency) async {
    // 1. Check local cache first
    try {
      final cachedRates = CacheService.getCachedCurrencyRates(baseCurrency);
      if (cachedRates != null && cachedRates.isNotEmpty) {
        return cachedRates;
      }
    } catch (e) {
      // Ignore cache read failures and proceed to fetch
    }

    try {
      final response = await http.get(Uri.parse('$_baseUrl/$baseCurrency'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = data['rates'] as Map<String, dynamic>;
        final Map<String, double> parsedRates = rates.map((key, value) => MapEntry(key, (value as num).toDouble()));
        
        // 2. Cache the newly fetched rates
        try {
          await CacheService.cacheCurrencyRates(baseCurrency, parsedRates);
        } catch (_) {
          // Ignore cache write failures
        }
        
        return parsedRates;
      }
      return _getFallbackRates(baseCurrency);
    } catch (e) {
      return _getFallbackRates(baseCurrency);
    }
  }

  static Map<String, double> _getFallbackRates(String base) {
    // Basic fallback rates if API fails
    final Map<String, double> usdBase = {
      'USD': 1.0,
      'EUR': 0.92,
      'GBP': 0.79,
      'LKR': 300.0,
      'INR': 83.0,
      'JPY': 150.0,
    };

    if (base == 'USD') return usdBase;
    
    // Calculate relative to USD if base is different
    final baseToUsd = 1.0 / (usdBase[base] ?? 1.0);
    return usdBase.map((key, value) => MapEntry(key, value * baseToUsd));
  }

  /// Converts a value from one currency to another using the provided rates of the target currency.
  static double convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
    required Map<String, double> ratesOfToCurrency,
  }) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) {
      return amount;
    }
    final rate = ratesOfToCurrency[from];
    if (rate == null || rate == 0) {
      return amount; // Can't convert
    }
    return amount / rate;
  }

  /// Attempts to parse and convert a price text like "USD 25", "$15", "LKR 1,500" or "50 EUR"
  /// to the target currency. Returns the original string if parsing or conversion fails.
  static String convertPriceText(
    String originalText, {
    required String targetCurrency,
    required Map<String, double> ratesOfTargetCurrency,
    String? defaultOriginalCurrency,
  }) {
    if (originalText.trim().isEmpty) return '';
    
    final cleanText = originalText.trim();
    if (cleanText.toLowerCase() == 'free') return 'Free';
    
    // Extract first number (handling commas, decimals)
    final numRegex = RegExp(r'(\d[\d,]*\.?\d*)');
    final numMatch = numRegex.firstMatch(cleanText);
    if (numMatch == null) return originalText;
    
    final numStr = numMatch.group(1)!.replaceAll(',', '');
    final double? amount = double.tryParse(numStr);
    if (amount == null) return originalText;
    
    // Determine the source currency
    String sourceCurrency = defaultOriginalCurrency ?? 'USD';
    
    final codeRegex = RegExp(r'\b([A-Z]{3})\b');
    final codeMatch = codeRegex.firstMatch(cleanText.toUpperCase());
    if (codeMatch != null) {
      sourceCurrency = codeMatch.group(1)!;
    } else {
      if (cleanText.contains(r'$')) {
        sourceCurrency = 'USD';
      } else if (cleanText.contains('€')) {
        sourceCurrency = 'EUR';
      } else if (cleanText.contains('£')) {
        sourceCurrency = 'GBP';
      } else if (cleanText.contains('₹')) {
        sourceCurrency = 'INR';
      } else if (cleanText.contains('¥')) {
        sourceCurrency = 'JPY';
      } else if (cleanText.contains('රු') || cleanText.toLowerCase().contains('lkr')) {
        sourceCurrency = 'LKR';
      } else if (cleanText.toLowerCase().contains('rs') || cleanText.toLowerCase().contains('inr')) {
        sourceCurrency = 'INR';
      }
    }
    
    final convertedAmount = convert(
      amount: amount,
      fromCurrency: sourceCurrency,
      toCurrency: targetCurrency,
      ratesOfToCurrency: ratesOfTargetCurrency,
    );
    
    final formattedAmount = formatAmount(convertedAmount);
    return '$targetCurrency $formattedAmount';
  }
}
