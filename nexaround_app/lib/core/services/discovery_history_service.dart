import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

class DiscoveryHistoryService {
  /// Get cached discovery history synchronously (0ms delay)
  static List<Map<String, dynamic>> getCachedHistory() {
    return CacheService.getCachedDiscoveryHistory();
  }

  static Future<List<Map<String, dynamic>>> fetchHistory() async {
    try {
      final response = await ApiClient.instance.get(ApiConstants.discoveryHistory);
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        final list = data.map((item) => item as Map<String, dynamic>).toList();
        // Persist to local cache for instant future loads
        await CacheService.cacheDiscoveryHistory(list);
        return list;
      }
      return getCachedHistory();
    } catch (e) {
      print('❌ Error fetching discovery history: $e');
      return getCachedHistory();
    }
  }

  static Future<bool> saveHistoryItem({
    required String location,
    required String mode,
    required String result,
  }) async {
    // Immediately save locally so history list updates instantly
    final cached = getCachedHistory();
    final newItem = {
      'location': location,
      'mode': mode,
      'result': result,
      'created_at': DateTime.now().toIso8601String(),
    };
    cached.insert(0, newItem);
    await CacheService.cacheDiscoveryHistory(cached);

    try {
      final response = await ApiClient.instance.post(
        ApiConstants.discoveryHistory,
        data: {
          'location': location,
          'mode': mode,
          'result': result,
        },
      );
      return response.statusCode == 201;
    } catch (e) {
      print('❌ Error saving discovery history: $e');
      return false;
    }
  }
}
