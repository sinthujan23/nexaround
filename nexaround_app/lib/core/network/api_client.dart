import 'dart:async';
import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static Dio? _dio;
  static bool _isRefreshing = false;
  static Completer<String?>? _refreshCompleter;

  static Dio get instance {
    _dio ??= _createDio();
    return _dio!;
  }

  static void reset() {
    _dio?.close(force: true);
    _dio = null;
    _isRefreshing = false;
    _refreshCompleter = null;
  }

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Auth interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        final path = error.requestOptions.path;
        final isAuthEndpoint = path.contains('/auth/login') ||
            path.contains('/auth/register') ||
            path.contains('/auth/refresh') ||
            path.contains('/auth/verify-otp') ||
            path.contains('/auth/forgot-password') ||
            path.contains('/auth/verify-reset-otp');

        // Automatically refresh expired access token and retry original request
        if (error.response?.statusCode == 401 && !isAuthEndpoint) {
          try {
            final newToken = await _refreshToken();
            if (newToken != null) {
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final retryResponse = await dio.fetch(opts);
              return handler.resolve(retryResponse);
            }
          } catch (_) {}
        }
        return handler.next(error);
      },
    ));

    // Logging interceptor (debug only)
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('📡 API: $obj'),
    ));

    return dio;
  }

  /// Internal token refresh handler with concurrent request locking
  static Future<String?> _refreshToken() async {
    if (_isRefreshing) {
      return _refreshCompleter?.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter?.complete(null);
        return null;
      }

      // Use a separate clean Dio client to avoid interceptor recursion
      final cleanDio = Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

      final response = await cleanDio.post(
        ApiConstants.refreshToken,
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;

        if (newAccess != null) {
          await prefs.setString('access_token', newAccess);
          if (newRefresh != null) {
            await prefs.setString('refresh_token', newRefresh);
          }
          print('🔄 Session: Successfully refreshed access token in background');
          _refreshCompleter?.complete(newAccess);
          return newAccess;
        }
      }

      _refreshCompleter?.complete(null);
      return null;
    } catch (e) {
      print('⚠️ Session: Token refresh failed: $e');
      _refreshCompleter?.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}
