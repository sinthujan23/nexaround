import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:nexaround_app/features/auth/domain/entities/user.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import 'package:nexaround_app/core/services/social_auth_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/config_key_service.dart';
import 'package:nexaround_app/features/auth/data/models/user_model.dart';
import 'package:nexaround_app/core/error/failures.dart';

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
    on<AuthForgotPasswordRequested>(_onForgotPassword);
    on<AuthVerifyResetOTPRequested>(_onVerifyResetOTP);
    on<AuthResetPasswordRequested>(_onResetPassword);
  }

  Future<UserEntity> _loadAndSyncUserPrefs(UserEntity user) async {
    await CacheService.loadUserPreferences(user);
    await CacheService.saveCachedUser(user);
    await CacheService.setLoggedIn(true);

    // Retry fetching public SDK keys (Mapbox, Google Maps) if they weren't
    // applied during startup (e.g. backend was cold-starting or network was
    // briefly offline). Fire-and-forget so it doesn't block the auth flow.
    if (!ConfigKeyService.isMapboxReady) {
      ConfigKeyService.fetchAndApplyKeys();
    }
    final userPrefs = CacheService.getUserPreferences();
    return UserModel(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      preferences: userPrefs,
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
      if (result.isRight()) {
        final tokens = result.getOrElse(() => throw Exception());
        final syncedUser = await _loadAndSyncUserPrefs(tokens.user);
        emit(AuthAuthenticated(
          user: syncedUser,
          accessToken: tokens.accessToken,
        ));
      } else {
        final failure = result.fold((l) => l, (r) => throw Exception());
        emit(AuthError(failure.message));
      }
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

      if (result.isRight()) {
        final tokens = result.getOrElse(() => throw Exception());
        final syncedUser = await _loadAndSyncUserPrefs(tokens.user);
        emit(AuthAuthenticated(
          user: syncedUser,
          accessToken: tokens.accessToken,
        ));
      } else {
        final failure = result.fold((l) => l, (r) => throw Exception());
        emit(AuthError(failure.message));
      }
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
      final cachedUser = CacheService.getCachedUser();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      final result = await _authRepository.getCurrentUser();
      if (result.isRight()) {
        final user = result.getOrElse(() => throw Exception());
        final syncedUser = await _loadAndSyncUserPrefs(user);
        emit(AuthAuthenticated(
          user: syncedUser,
          accessToken: token,
        ));
      } else {
        final failure = result.fold((l) => l, (r) => throw Exception());

        // Device is offline / connection error — DO NOT LOG OUT!
        if (failure is NetworkFailure) {
          if (cachedUser != null) {
            final syncedUser = await _loadAndSyncUserPrefs(cachedUser);
            debugPrint('📶 Session: Device is offline. Preserving authenticated session from cache.');
            emit(AuthAuthenticated(
              user: syncedUser,
              accessToken: token,
            ));
            return;
          } else {
            // Fallback user if token exists but cached user object was not saved
            final prefsMap = CacheService.getUserPreferences();
            final fallbackUser = UserModel(
              id: 'offline_user',
              email: '',
              displayName: 'Explorer',
              preferences: prefsMap,
              createdAt: DateTime.now(),
            );
            await CacheService.saveCachedUser(fallbackUser);
            debugPrint('📶 Session: Device is offline. Using fallback user session.');
            emit(AuthAuthenticated(
              user: fallbackUser,
              accessToken: token,
            ));
            return;
          }
        }

        // Access token expired (>1 hour) on server — attempt automatic refresh via 30-day refresh_token!
        try {
          final refreshToken = prefs.getString('refresh_token');
          if (refreshToken != null && refreshToken.isNotEmpty) {
            final refreshResult = await _authRepository.refreshToken(refreshToken);
            if (refreshResult.isRight()) {
              final tokens = refreshResult.getOrElse(() => throw Exception());
              final syncedUser = await _loadAndSyncUserPrefs(tokens.user);
              debugPrint('🔄 Session: Auto-refreshed session on app startup');
              emit(AuthAuthenticated(
                user: syncedUser,
                accessToken: tokens.accessToken,
              ));
              return;
            } else {
              final refreshFailure = refreshResult.fold((l) => l, (r) => throw Exception());
              if (refreshFailure is NetworkFailure) {
                // Refresh failed due to offline / network — KEEP USER LOGGED IN!
                if (cachedUser != null) {
                  final syncedUser = await _loadAndSyncUserPrefs(cachedUser);
                  debugPrint('📶 Session: Offline refresh error. Preserving cached session.');
                  emit(AuthAuthenticated(
                    user: syncedUser,
                    accessToken: token,
                  ));
                  return;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Session: Startup token refresh failed: $e');
        }

        // Only log out if both tokens are truly rejected/invalid on server
        debugPrint('🔒 Session: Token invalid or session expired. Logging out.');
        await _authRepository.logout();
        emit(const AuthUnauthenticated());
      }
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
    if (result.isRight()) {
      final tokens = result.getOrElse(() => throw Exception());
      final syncedUser = await _loadAndSyncUserPrefs(tokens.user);
      emit(AuthAuthenticated(
        user: syncedUser,
        accessToken: tokens.accessToken,
      ));
    } else {
      final failure = result.fold((l) => l, (r) => throw Exception());
      if (failure.message.toLowerCase().contains('not verified')) {
        emit(AuthOTPVerificationRequired(
          email: event.email,
          message: failure.message,
        ));
      } else {
        emit(AuthError(failure.message));
      }
    }
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
    if (result.isRight()) {
      final tokens = result.getOrElse(() => throw Exception());
      final syncedUser = await _loadAndSyncUserPrefs(tokens.user);
      emit(AuthAuthenticated(
        user: syncedUser,
        accessToken: tokens.accessToken,
      ));
    } else {
      final failure = result.fold((l) => l, (r) => throw Exception());
      emit(AuthError(failure.message));
    }
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
    await CacheService.clearUserData();
    emit(const AuthUnauthenticated());
  }

  Future<void> _onForgotPassword(
    AuthForgotPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.forgotPassword(email: event.email);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (msg) => emit(AuthForgotPasswordOTPRequired(
        email: event.email,
        message: msg,
      )),
    );
  }

  Future<void> _onVerifyResetOTP(
    AuthVerifyResetOTPRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.verifyResetOtp(
      email: event.email,
      otp: event.otp,
    );
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (resetToken) => emit(AuthResetOTPVerified(
        email: event.email,
        resetToken: resetToken,
        message: 'Code verified successfully. Please enter a new password.',
      )),
    );
  }

  Future<void> _onResetPassword(
    AuthResetPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    final result = await _authRepository.resetPassword(
      email: event.email,
      resetToken: event.resetToken,
      newPassword: event.newPassword,
    );
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (msg) => emit(AuthPasswordResetSuccess(msg)),
    );
  }
}
