import 'package:dartz/dartz.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, AuthTokens>> register({
    required String email,
    required String password,
    required String displayName,
    String language,
  });

  Future<Either<Failure, AuthTokens>> login({
    required String email,
    required String password,
  });

  Future<Either<Failure, AuthTokens>> refreshToken(String refreshToken);

  Future<Either<Failure, UserEntity>> getCurrentUser();

  Future<Either<Failure, UserEntity>> updatePreferences(
      Map<String, dynamic> preferences);

  Future<void> logout();

  Future<bool> isLoggedIn();
}
