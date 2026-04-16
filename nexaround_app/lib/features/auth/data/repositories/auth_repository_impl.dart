import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';
import 'package:nexaround_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDatasource _remoteDatasource;

  AuthRepositoryImpl(this._remoteDatasource);

  @override
  Future<Either<Failure, AuthTokens>> register({
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
      await _saveTokens(result.accessToken, result.refreshToken);
      return Right(result);
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
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  @override
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token') != null;
  }

  // --- Private helpers ---

  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
  }

  Failure _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const NetworkFailure('Connection timed out');
    }
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final detail =
          e.response!.data is Map ? e.response!.data['detail'] : null;
      if (statusCode == 401) {
        return AuthFailure(detail ?? 'Invalid credentials');
      }
      if (statusCode == 409) {
        return AuthFailure(detail ?? 'Email already registered');
      }
      return ServerFailure(detail ?? 'Server error ($statusCode)');
    }
    return const NetworkFailure('No internet connection');
  }
}
