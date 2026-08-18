import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';
import 'package:nexaround_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDatasource _remoteDatasource;

  AuthRepositoryImpl(this._remoteDatasource);

  @override
  Future<Either<Failure, String>> register({
    required String email,
    required String password,
    required String displayName,
    String language = 'en',
  }) async {
    try {
      final result = await _remoteDatasource.register(
        email: email,
        password: password,
        displayName: displayName,
        language: language,
      );
      final registeredEmail = result['email'] as String? ?? email;
      return Right(registeredEmail);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final result = await _remoteDatasource.verifyOtp(
        email: email,
        otp: otp,
      );
      await _saveTokens(result.accessToken, result.refreshToken);
      await CacheService.saveCachedUser(result.user);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> resendOtp({
    required String email,
  }) async {
    try {
      final result = await _remoteDatasource.resendOtp(email: email);
      final message = result['message'] as String? ?? 'OTP sent';
      return Right(message);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _remoteDatasource.login(
        email: email,
        password: password,
      );
      await _saveTokens(result.accessToken, result.refreshToken);
      await CacheService.saveCachedUser(result.user);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> googleLogin(String idToken) async {
    try {
      final result = await _remoteDatasource.googleLogin(idToken);
      await _saveTokens(result.accessToken, result.refreshToken);
      await CacheService.saveCachedUser(result.user);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> appleLogin({
    required String idToken,
    required String authorizationCode,
    String? givenName,
    String? familyName,
  }) async {
    try {
      final result = await _remoteDatasource.appleLogin(
        idToken: idToken,
        authorizationCode: authorizationCode,
        givenName: givenName,
        familyName: familyName,
      );
      await _saveTokens(result.accessToken, result.refreshToken);
      await CacheService.saveCachedUser(result.user);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AuthTokens>> refreshToken(String refreshToken) async {
    try {
      final result = await _remoteDatasource.refreshToken(refreshToken);
      await _saveTokens(result.accessToken, result.refreshToken);
      await CacheService.saveCachedUser(result.user);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async {
    try {
      final user = await _remoteDatasource.getCurrentUser();
      await CacheService.saveCachedUser(user);
      return Right(user);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> updatePreferences(
      Map<String, dynamic> preferences) async {
    try {
      final user = await _remoteDatasource.updatePreferences(preferences);
      return Right(user);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> forgotPassword({required String email}) async {
    try {
      final result = await _remoteDatasource.forgotPassword(email: email);
      final message = result['message'] as String? ?? 'Password reset code sent to email.';
      return Right(message);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> verifyResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final result = await _remoteDatasource.verifyResetOtp(email: email, otp: otp);
      final resetToken = result['reset_token'] as String? ?? '';
      return Right(resetToken);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    try {
      final result = await _remoteDatasource.resetPassword(
        email: email,
        resetToken: resetToken,
        newPassword: newPassword,
      );
      final message = result['message'] as String? ?? 'Password reset successfully.';
      return Right(message);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await CacheService.setLoggedIn(false);
    await CacheService.clearUserData();
  }

  @override
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return (token != null && token.isNotEmpty) || CacheService.isLoggedIn();
  }

  // --- Private helpers ---

  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
    await CacheService.setLoggedIn(true);
  }

  Failure _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const NetworkFailure('Connection timed out. Please try again.');
    }
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      String? detailStr;
      if (e.response!.data is Map) {
        final rawDetail = e.response!.data['detail'];
        if (rawDetail is String) {
          detailStr = rawDetail;
        } else if (rawDetail is List && rawDetail.isNotEmpty) {
          final firstErr = rawDetail.first;
          if (firstErr is Map && firstErr.containsKey('msg')) {
            detailStr = firstErr['msg'].toString();
          } else {
            detailStr = rawDetail.toString();
          }
        }
      }
      if (statusCode == 401) {
        return AuthFailure(detailStr ?? 'Invalid credentials');
      }
      if (statusCode == 409) {
        return AuthFailure(detailStr ?? 'Email already registered');
      }
      if (statusCode == 422) {
        return AuthFailure(detailStr ?? 'Invalid input data. Please check your details.');
      }
      return ServerFailure(detailStr ?? 'Server error ($statusCode)');
    }
    return NetworkFailure('Could not reach server: ${e.message ?? 'No internet connection'}');
  }
}
