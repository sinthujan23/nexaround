import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/domain/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import 'package:nexaround_app/core/services/social_auth_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SocialAuthService _socialAuthService = SocialAuthService();

  AuthBloc(this._authRepository) : super(const AuthInitial()) {
    on<AuthCheckStatus>(_onCheckStatus);
    on<AuthLoginRequested>(_onLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthGoogleLoginRequested>(_onGoogleLogin);
    on<AuthAppleLoginRequested>(_onAppleLogin);
    on<AuthLogoutRequested>(_onLogout);
    on<UpdateUserPreferences>(_onUpdatePreferences);
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

      final authentication = await googleUser.authentication;
      final idToken = authentication.idToken;

      if (idToken == null) {
        emit(const AuthError('Could not retrieve Google ID Token'));
        return;
      }

      final result = await _authRepository.googleLogin(idToken);
      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (tokens) => emit(AuthAuthenticated(
          user: tokens.user,
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
          user: tokens.user,
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
      final result = await _authRepository.updatePreferences(event.preferences);
      result.fold(
        (failure) => null, // Keep existing state on failure
        (updatedUser) => emit(AuthAuthenticated(
          user: updatedUser,
          accessToken: currentAuth.accessToken,
        )),
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
        (user) => emit(AuthAuthenticated(user: user, accessToken: '')),
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
      (failure) => emit(AuthError(failure.message)),
      (tokens) => emit(AuthAuthenticated(
        user: tokens.user,
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
      (failure) => emit(AuthError(failure.message)),
      (tokens) => emit(AuthAuthenticated(
        user: tokens.user,
        accessToken: tokens.accessToken,
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
