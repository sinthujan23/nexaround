import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/auth/data/models/user_model.dart';

class AuthRemoteDatasource {
  final Dio _dio = ApiClient.instance;

  Future<AuthTokensModel> register({
    required String email,
    required String password,
    required String displayName,
    String language = 'en',
  }) async {
    final response = await _dio.post(
      ApiConstants.register,
      data: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'language': language,
      },
    );
    return AuthTokensModel.fromJson(response.data);
  }

  Future<AuthTokensModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: {
        'email': email,
        'password': password,
      },
    );
    return AuthTokensModel.fromJson(response.data);
  }

  Future<AuthTokensModel> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      ApiConstants.refreshToken,
      data: {'refresh_token': refreshToken},
    );
    return AuthTokensModel.fromJson(response.data);
  }

  Future<UserModel> getCurrentUser() async {
    final response = await _dio.get(ApiConstants.me);
    return UserModel.fromJson(response.data);
  }

  Future<UserModel> updatePreferences(Map<String, dynamic> preferences) async {
    final response = await _dio.put(
      ApiConstants.updatePreferences,
      data: preferences,
    );
    return UserModel.fromJson(response.data);
  }
}
