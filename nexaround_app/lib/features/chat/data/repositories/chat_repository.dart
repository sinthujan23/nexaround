import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

class ChatRepository {
  final Dio _dio = ApiClient.instance;

  Future<String> sendMessage(String message, {String? context}) async {
    final response = await _dio.post(
      '${ApiConstants.baseUrl}/chat/message',
      data: {
        'message': message,
        'context': context ?? '',
      },
    );

    if (response.statusCode == 200) {
      return response.data['response'];
    } else {
      throw Exception('Failed to send message');
    }
  }
}
