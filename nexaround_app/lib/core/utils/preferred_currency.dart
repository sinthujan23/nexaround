import 'package:flutter/widgets.dart';
import 'package:nexaround_app/core/constants/country_currency.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';

/// The currency to show prices in for this traveller.
///
/// Their Profile choice when they made one; otherwise the usual currency of
/// the country their phone is set to (Qatar: QAR, India: INR); otherwise USD.
String preferredCurrency(AuthState state) {
  if (state is AuthAuthenticated) {
    final chosen =
        state.user.preferences['currency']?.toString().trim().toUpperCase();
    if (chosen != null && chosen.isNotEmpty) return chosen;
  }
  return regionCurrency() ?? 'USD';
}

/// The usual currency of the phone's region, when it is one the app offers.
String? regionCurrency() {
  final country = WidgetsBinding.instance.platformDispatcher.locale.countryCode
      ?.toUpperCase();
  if (country == null || country.isEmpty) return null;
  final code = kCountryCurrency[country];
  if (code == null) return null;
  final offered =
      CurrencyService.supportedCurrencies.any((c) => c['code'] == code);
  return offered ? code : null;
}
