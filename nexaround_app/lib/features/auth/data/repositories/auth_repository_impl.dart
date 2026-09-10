import 'package:nexaround_app/core/network/auth_token_cache.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/core/error/user_message.dart';
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
    String? nationality,
  }) async {
    try {
      final result = await _remoteDatasource.register(
        email: email,
        password: password,
        displayName: displayName,
        language: language,
        nationality: nationality,
      );
      final registeredEmail = result['email'] as String? ?? email;
      return Right(registeredEmail);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
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
      return Left(ServerFailure(userMessageFor(e)));
    }
  }

  @override
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    AuthTokenCache.clear();
    await CacheService.setLoggedIn(false);
    await CacheService.clearUserData();
  }

  @override
  Future<Either<Failure, void>> deleteAccount() async {
    try {
      await _remoteDatasource.deleteAccount();
      await logout();
      return const Right(null);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(userMessageFor(e)));
    }
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
    // Images authenticate off this copy, so it has to move with the token.
    AuthTokenCache.set(accessToken);
    await CacheService.setLoggedIn(true);
  }

  Failure _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const NetworkFailure('Connection timed out. Please try again.');
    }
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      // Only the backend's deliberate sentences come through; validator output
      // and server faults are replaced with a fixed message.
      final detailStr = safeServerDetail(e.response);
      if (statusCode == 401) {
        return AuthFailure(detailStr ?? 'Invalid credentials', statusCode);
      }
      if (statusCode == 409) {
        return AuthFailure(detailStr ?? 'Email already registered', statusCode);
      }
      if (statusCode == 422 || statusCode == 400) {
        return AuthFailure(detailStr ?? 'Invalid input data. Please check your details.', statusCode);
      }
      if (statusCode == 429) {
        return AuthFailure(detailStr ?? 'Too many attempts. Please wait a moment and try again.', statusCode);
      }
      return ServerFailure(detailStr ?? userMessageFor(e), statusCode);
    }
    return NetworkFailure(userMessageFor(e));
  }
}
