import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nexaround_app/core/services/cache_service.dart';

class CurrencyService {
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
}
