import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final Map<String, dynamic> preferences;
  final String language;
  final bool isActive;
  final bool isVerified;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.preferences = const {},
    this.language = 'en',
    this.isActive = true,
    this.isVerified = false,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        avatarUrl,
        preferences,
        language,
        isActive,
        isVerified,
        createdAt,
      ];
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final UserEntity user;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });
}
