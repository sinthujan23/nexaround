import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';

/// The currency the traveller picked in their Profile, or null when they
/// haven't picked one (nothing sets it for them at sign-up).
String? chosenCurrency(AuthState state) {
  if (state is! AuthAuthenticated) return null;
  final chosen =
      state.user.preferences['currency']?.toString().trim().toUpperCase();
  return chosen == null || chosen.isEmpty ? null : chosen;
}
