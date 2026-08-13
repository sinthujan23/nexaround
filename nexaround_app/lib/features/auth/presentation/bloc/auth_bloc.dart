import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import 'package:nexaround_app/core/services/social_auth_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/data/models/user_model.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SocialAuthService _socialAuthService = SocialAuthService();

  AuthBloc(this._authRepository) : super(const AuthInitial()) {
    on<AuthCheckStatus>(_onCheckStatus);
    on<AuthLoginRequested>(_onLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthVerifyOTPRequested>(_onVerifyOTP);
    on<AuthResendOTPRequested>(_onResendOTP);
    on<AuthGoogleLoginRequested>(_onGoogleLogin);
    on<AuthAppleLoginRequested>(_onAppleLogin);
    on<AuthLogoutRequested>(_onLogout);
    on<UpdateUserPreferences>(_onUpdatePreferences);
  }

  UserEntity _mergeWithLocalPrefs(UserEntity user) {
    final localPrefs = CacheService.getUserPreferences();
    final Map<String, dynamic> mergedPrefs = {...user.preferences, ...localPrefs};
    CacheService.saveUserPreferences(mergedPrefs);
    return UserModel(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      preferences: mergedPrefs,
      language: user.language,
      isActive: user.isActive,
      isVerified: user.isVerified,
      createdAt: user.createdAt,
    );
  }

  Future<void> _onGoogleLogin(
    AuthGoogleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final googleUser = await _socialAuthService.signInWithGoogle();
      if (googleUser == null) {
        emit(const AuthUnauthenticated());
        return;
      }

      final authentication = googleUser.authentication;
      final idToken = authentication.idToken;

      if (idToken == null) {
        emit(const AuthError('Could not retrieve Google ID Token'));
        return;
      }

      final result = await _authRepository.googleLogin(idToken);
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (tokens) => emit(AuthAuthenticated(
          user: _mergeWithLocalPrefs(tokens.user),
          accessToken: tokens.accessToken,
        )),
      );
    } catch (e) {
      emit(AuthError('Google Sign-In failed: ${e.toString()}'));
    }
  }

  Future<void> _onAppleLogin(
    AuthAppleLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final credential = await _socialAuthService.signInWithApple();
      
      final result = await _authRepository.appleLogin(
        idToken: credential.identityToken ?? '',
        authorizationCode: credential.authorizationCode,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (tokens) => emit(AuthAuthenticated(
          user: _mergeWithLocalPrefs(tokens.user),
          accessToken: tokens.accessToken,
        )),
      );
    } catch (e) {
      emit(AuthError('Apple Sign-In failed: ${e.toString()}'));
    }
  }

  Future<void> _onUpdatePreferences(
    UpdateUserPreferences event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthAuthenticated) {
      final currentAuth = state as AuthAuthenticated;
      
      // Save locally first to guarantee immediate responsiveness and offline persistence
      await CacheService.saveUserPreferences(event.preferences);
      
      final updatedUser = UserModel(
        id: currentAuth.user.id,
        email: currentAuth.user.email,
        displayName: currentAuth.user.displayName,
        avatarUrl: currentAuth.user.avatarUrl,
        preferences: event.preferences,
        language: currentAuth.user.language,
        isActive: currentAuth.user.isActive,
        isVerified: currentAuth.user.isVerified,
        createdAt: currentAuth.user.createdAt,
      );

      emit(AuthAuthenticated(
        user: updatedUser,
        accessToken: currentAuth.accessToken,
      ));

      // Attempt remote save in background
      final result = await _authRepository.updatePreferences(event.preferences);
      result.fold(
        (failure) => null, 
        (serverUpdatedUser) {
          final Map<String, dynamic> mergedPrefs = {...serverUpdatedUser.preferences, ...event.preferences};
          final finalUser = UserModel(
            id: serverUpdatedUser.id,
            email: serverUpdatedUser.email,
            displayName: serverUpdatedUser.displayName,
            avatarUrl: serverUpdatedUser.avatarUrl,
            preferences: mergedPrefs,
            language: serverUpdatedUser.language,
            isActive: serverUpdatedUser.isActive,
            isVerified: serverUpdatedUser.isVerified,
            createdAt: serverUpdatedUser.createdAt,
          );
          emit(AuthAuthenticated(
            user: finalUser,
            accessToken: currentAuth.accessToken,
          ));
        },
      );
    }
  }

  Future<void> _onCheckStatus(
    AuthCheckStatus event,
    Emitter<AuthState> emit,
  ) async {
    final loggedIn = await _authRepository.isLoggedIn();
    if (loggedIn) {
      final result = await _authRepository.getCurrentUser();
      result.fold(
        (failure) => emit(const AuthUnauthenticated()),
        (user) => emit(AuthAuthenticated(
          user: _mergeWithLocalPrefs(user),
          accessToken: '',
        )),
      );
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLogin(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.login(
      email: event.email,
      password: event.password,
    );
    result.fold(
      (failure) {
        if (failure.message.toLowerCase().contains('not verified')) {
          emit(AuthOTPVerificationRequired(
            email: event.email,
            message: failure.message,
          ));
        } else {
          emit(AuthError(failure.message));
        }
      },
      (tokens) => emit(AuthAuthenticated(
        user: _mergeWithLocalPrefs(tokens.user),
        accessToken: tokens.accessToken,
      )),
    );
  }

  Future<void> _onRegister(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.register(
      email: event.email,
      password: event.password,
      displayName: event.displayName,
    );
    result.fold(
      (failure) {
        final msg = failure.message.toLowerCase();
        if (msg.contains('unverified') || msg.contains('already sent') || msg.contains('verify')) {
          emit(AuthOTPVerificationRequired(
            email: event.email,
            message: failure.message,
          ));
        } else {
          emit(AuthError(failure.message));
        }
      },
      (registeredEmail) => emit(AuthOTPVerificationRequired(
        email: registeredEmail,
        message: 'Verification OTP sent to your email address.',
      )),
    );
  }

  Future<void> _onVerifyOTP(
    AuthVerifyOTPRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.verifyOtp(
      email: event.email,
      otp: event.otp,
    );
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (tokens) => emit(AuthAuthenticated(
        user: _mergeWithLocalPrefs(tokens.user),
        accessToken: tokens.accessToken,
      )),
    );
  }

  Future<void> _onResendOTP(
    AuthResendOTPRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _authRepository.resendOtp(email: event.email);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (msg) => emit(AuthOTPVerificationRequired(
        email: event.email,
        message: msg,
      )),
    );
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logout();
    emit(const AuthUnauthenticated());
  }
}
