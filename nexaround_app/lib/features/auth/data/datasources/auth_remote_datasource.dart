import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/auth/data/models/user_model.dart';

class AuthRemoteDatasource {
  final Dio _dio = ApiClient.instance;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
    String language = 'en',
    String? nationality,
  }) async {
    final response = await _dio.post(
      ApiConstants.register,
      data: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'language': language,
        if (nationality != null && nationality.isNotEmpty) 'nationality': nationality,
      },
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {};
  }

  Future<AuthTokensModel> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _dio.post(
      ApiConstants.verifyOtp,
      data: {
        'email': email,
        'otp': otp,
      },
    );
    return AuthTokensModel.fromJson(response.data);
  }

  Future<Map<String, dynamic>> resendOtp({
    required String email,
  }) async {
    final response = await _dio.post(
      ApiConstants.resendOtp,
      data: {
        'email': email,
      },
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {};
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

  Future<AuthTokensModel> googleLogin(String idToken) async {
    final response = await _dio.post(
      ApiConstants.googleLogin,
      data: {'id_token': idToken},
    );
    return AuthTokensModel.fromJson(response.data);
  }

  Future<AuthTokensModel> appleLogin({
    required String idToken,
    required String authorizationCode,
    String? givenName,
    String? familyName,
  }) async {
    final response = await _dio.post(
      ApiConstants.appleLogin,
      data: {
        'id_token': idToken,
        'authorization_code': authorizationCode,
        'given_name': givenName,
        'family_name': familyName,
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

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final response = await _dio.post(
      ApiConstants.forgotPassword,
      data: {'email': email},
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {};
  }

  Future<Map<String, dynamic>> verifyResetOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _dio.post(
      ApiConstants.verifyResetOtp,
      data: {'email': email, 'otp': otp},
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {};
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await _dio.post(
      ApiConstants.resetPassword,
      data: {
        'email': email,
        'reset_token': resetToken,
        'new_password': newPassword,
      },
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {};
  }

  Future<void> deleteAccount() async {
    await _dio.delete(ApiConstants.me);
  }
}
