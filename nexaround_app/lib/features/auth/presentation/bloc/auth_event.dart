import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String displayName;

  const AuthRegisterRequested({
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  List<Object?> get props => [email, password, displayName];
}

class AuthVerifyOTPRequested extends AuthEvent {
  final String email;
  final String otp;

  const AuthVerifyOTPRequested({required this.email, required this.otp});

  @override
  List<Object?> get props => [email, otp];
}

class AuthResendOTPRequested extends AuthEvent {
  final String email;

  const AuthResendOTPRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthCheckStatus extends AuthEvent {
  const AuthCheckStatus();
}

class UpdateUserPreferences extends AuthEvent {
  final Map<String, dynamic> preferences;

  const UpdateUserPreferences(this.preferences);

  @override
  List<Object?> get props => [preferences];
}

class AuthGoogleLoginRequested extends AuthEvent {
  const AuthGoogleLoginRequested();
}

class AuthAppleLoginRequested extends AuthEvent {
  const AuthAppleLoginRequested();
}

class AuthForgotPasswordRequested extends AuthEvent {
  final String email;

  const AuthForgotPasswordRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

class AuthVerifyResetOTPRequested extends AuthEvent {
  final String email;
  final String otp;

  const AuthVerifyResetOTPRequested({required this.email, required this.otp});

  @override
  List<Object?> get props => [email, otp];
}

class AuthResetPasswordRequested extends AuthEvent {
  final String email;
  final String resetToken;
  final String newPassword;

  const AuthResetPasswordRequested({
    required this.email,
    required this.resetToken,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [email, resetToken, newPassword];
}
