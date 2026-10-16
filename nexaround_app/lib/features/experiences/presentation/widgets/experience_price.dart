import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/utils/preferred_currency.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/experiences/domain/entities/experience.dart';

/// Builds a package's price in the traveller's own currency.
///
/// The provider sets the price in their currency (QAR 499 / person); this
/// passes [builder] the same price converted with today's rates, in the same
/// shape the server writes it ("INR 47,500 / person", "From USD 40"), so
/// callers lay it out exactly as before. Until the rates are known, and for
/// "Price on request" or a price already in the traveller's currency, it
/// passes the server's own label.
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
        final target = preferredCurrency(authState);
        if (target == from) return builder(context, package.priceLabel);

        String label(Map<String, double>? rates) {
          // Without a rate for the provider's currency, the real price is
          // better than a wrong one.
          if (rates == null || (rates[from] ?? 0) <= 0) return package.priceLabel;
          final converted = CurrencyService.convert(
            amount: amount,
            fromCurrency: from,
            toCurrency: target,
            ratesOfToCurrency: rates,
          );
          return convertedPriceLabel(converted, target, package.priceBasis);
        }

        // Saved rates paint at once; only a first run waits for the network.
        final saved = CurrencyService.cachedExchangeRates(target);
        if (saved != null) return builder(context, label(saved));
        return FutureBuilder<Map<String, double>>(
          future: CurrencyService.getExchangeRates(target),
          builder: (context, snapshot) => builder(context, label(snapshot.data)),
        );
      },
    );
  }
}

/// "INR 47,500 / person", "INR 7,500 / group", "From USD 40", "USD 12.50".
String convertedPriceLabel(double amount, String currency, String basis) {
  // Cents only where they matter: a small amount in a strong currency.
  final decimals = amount < 20 && amount != amount.roundToDouble() ? 2 : 0;
  final price = '$currency ${formatAmount(amount, decimals: decimals)}';
  switch (basis) {
    case 'per_person':
      return '$price / person';
    case 'per_group':
      return '$price / group';
    case 'from':
      return 'From $price';
    default:
      return price;
  }
}
