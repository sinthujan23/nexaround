import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserEntity user;
  final String accessToken;

  const AuthAuthenticated({required this.user, required this.accessToken});

  @override
  List<Object?> get props => [user, accessToken];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAccountDeleted extends AuthState {
  final String message;

  const AuthAccountDeleted([this.message = 'Your account has been permanently deleted.']);

  @override
  List<Object?> get props => [message];
}

class AuthOTPVerificationRequired extends AuthState {
  final String email;
  final String? message;

  const AuthOTPVerificationRequired({required this.email, this.message});

  @override
  List<Object?> get props => [email, message];
}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

class AuthForgotPasswordOTPRequired extends AuthState {
  final String email;
  final String message;

  const AuthForgotPasswordOTPRequired({required this.email, required this.message});

  @override
  List<Object?> get props => [email, message];
}

class AuthResetOTPVerified extends AuthState {
  final String email;
  final String resetToken;
  final String message;

  const AuthResetOTPVerified({
    required this.email,
    required this.resetToken,
    required this.message,
  });

  @override
  List<Object?> get props => [email, resetToken, message];
}

class AuthPasswordResetSuccess extends AuthState {
  final String message;

  const AuthPasswordResetSuccess(this.message);

  @override
  List<Object?> get props => [message];
}
