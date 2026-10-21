import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/utils/preferred_currency.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// Builds a package's price with the US dollar amount in brackets.
///
/// The price is in the currency the traveller picked in their Profile, or,
/// when they haven't picked one, in the experience's own currency (what the
/// provider set): "LKR 45,395 ($137) / group (max 4)", "QAR 499 ($137) /
/// group (max 4)". Shown in dollars already, there is no bracket ("USD 40 /
/// person"). Conversions use today's rates. "Price on request", and a price
/// whose currency has no rate yet, use the server's own label - the
/// provider's price, which is better than a wrong one.
class ExperiencePriceBuilder extends StatelessWidget {
  final ExperiencePackageEntity package;
  final Widget Function(BuildContext context, String label) builder;

  const ExperiencePriceBuilder({
    super.key,
    required this.package,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final amount = package.priceAmount;
    final from = package.priceCurrency.trim().toUpperCase();
    if (amount == null || package.priceBasis == 'on_request' || from.isEmpty) {
      return builder(context, package.priceLabel);
    }

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final shown = chosenCurrency(authState) ?? from;

        // [perUsd]: units of each currency per one US dollar.
        String label(Map<String, double>? perUsd) {
          final fromRate = from == 'USD' ? 1.0 : perUsd?[from];
          if (fromRate == null || fromRate <= 0) return package.priceLabel;
          final usd = amount / fromRate;

          final shownRate = shown == 'USD' ? 1.0 : perUsd?[shown];
          final String currency;
          final double value;
          if (shown != from && shownRate != null && shownRate > 0) {
            currency = shown;
            value = usd * shownRate;
          } else {
            // The experience's own price: no Profile choice, the same
            // currency, or no rate for the traveller's currency.
            currency = from;
            value = amount;
          }
          return convertedPriceLabel(
            value,
            currency,
            package.priceBasis,
            maxPeople: package.maxParticipants,
            usd: currency == 'USD' ? null : usd,
          );
        }

        // Saved rates paint at once; only a first run waits for the network.
        final saved = CurrencyService.cachedExchangeRates('USD');
        if (saved != null) return builder(context, label(saved));
        return FutureBuilder<Map<String, double>>(
          future: CurrencyService.getExchangeRates('USD'),
          builder: (context, snapshot) => builder(context, label(snapshot.data)),
        );
      },
    );
  }
}

/// "INR 47,500 ($570) / person", "INR 7,500 ($90) / group (max 6)",
/// "From USD 40", "USD 12.50". A group price carries the group size, like
/// the server's label; [usd], when given, is the dollar amount in brackets.
String convertedPriceLabel(
  double amount,
  String currency,
  String basis, {
  int? maxPeople,
  double? usd,
}) {
  // Cents only where they matter: a small amount in a strong currency.
  String money(double value) => formatAmount(
        value,
        decimals: value < 20 && value != value.roundToDouble() ? 2 : 0,
      );
  final price = usd == null
      ? '$currency ${money(amount)}'
      : '$currency ${money(amount)} (\$${money(usd)})';
  switch (basis) {
    case 'per_person':
      return '$price / person';
    case 'per_group':
      return maxPeople != null && maxPeople > 0
          ? '$price / group (max $maxPeople)'
          : '$price / group';
    case 'from':
      return 'From $price';
    default:
      return price;
  }
}
