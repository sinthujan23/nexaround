import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

class DiscoveryHistoryService {
  static Future<List<Map<String, dynamic>>> fetchHistory() async {
    try {
      final response = await ApiClient.instance.get(ApiConstants.discoveryHistory);
      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> data = response.data;
        return data.map((item) => item as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      print('❌ Error fetching discovery history: $e');
      return [];
    }
  }

  static Future<bool> saveHistoryItem({
    required String location,
    required String mode,
    required String result,
  }) async {
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
