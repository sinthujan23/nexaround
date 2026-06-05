import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';

class ConvertedCurrencyText extends StatelessWidget {
  final double? amount;
  final String? originalCurrency;
  final String? rawText; // If we want to convert a raw string like "USD 20"
  final String prefix;
  final String suffix;
  final TextStyle style;

  const ConvertedCurrencyText({
    super.key,
    this.amount,
    this.originalCurrency,
    this.rawText,
    this.prefix = '',
    this.suffix = '',
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        String targetCurrency = 'USD';
        if (authState is AuthAuthenticated) {
          targetCurrency = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
        }

        final originalText = _getOriginalText();

        return FutureBuilder<Map<String, double>>(
          future: CurrencyService.getExchangeRates(targetCurrency),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.hasError) {
              return Text('$prefix$originalText$suffix', style: style);
            }

            final rates = snapshot.data!;
            if (rawText != null) {
              final converted = CurrencyService.convertPriceText(
                rawText!,
                targetCurrency: targetCurrency,
                ratesOfTargetCurrency: rates,
                defaultOriginalCurrency: originalCurrency,
              );
              return Text('$prefix$converted$suffix', style: style);
            } else if (amount != null && originalCurrency != null) {
              final convertedAmount = CurrencyService.convert(
                amount: amount!,
                fromCurrency: originalCurrency!,
                toCurrency: targetCurrency,
                ratesOfToCurrency: rates,
              );
              final formatted = formatAmount(convertedAmount);
              return Text('$prefix$targetCurrency $formatted$suffix', style: style);
            }

            return Text('$prefix$originalText$suffix', style: style);
          },
        );
      },
    );
  }

  String _getOriginalText() {
    if (rawText != null) {
      return rawText!;
    }
    if (amount != null && originalCurrency != null) {
      return '$originalCurrency ${formatAmount(amount!)}';
    }
    return '';
  }
}
