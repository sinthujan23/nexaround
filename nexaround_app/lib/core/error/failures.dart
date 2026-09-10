abstract class Failure {
  final String message;

  /// HTTP status that produced this failure, when there was one. Lets a
  /// caller act on *what* failed ("session expired, go to login") without
  /// pattern-matching the message text, which is written for people.
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  bool get isSessionExpired => statusCode == 401;
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error occurred', super.statusCode]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed', super.statusCode]);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation error', super.statusCode]);
}
