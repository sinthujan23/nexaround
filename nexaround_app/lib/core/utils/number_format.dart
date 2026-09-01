import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats a money/amount value with thousands separators.
/// e.g. 100000 -> "100,000", 1500 -> "1,500", 1234.5 (decimals: 2) -> "1,234.50".
String formatAmount(num value, {int decimals = 0}) {
  final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
  return NumberFormat(pattern, 'en_US').format(value);
}

/// A TextInputFormatter that automatically adds comma separators every 3 digits
/// (e.g. 5000 -> 5,000; 50000 -> 50,000) while typing or deleting digits.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final cleanDigits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final number = int.tryParse(cleanDigits);
    if (number == null) return oldValue;

    final formatted = formatAmount(number);

    // Calculate cursor position by counting digits before the cursor in newValue
    int digitsBeforeCursor = 0;
    for (int i = 0; i < newValue.selection.end && i < newValue.text.length; i++) {
      if (RegExp(r'\d').hasMatch(newValue.text[i])) {
        digitsBeforeCursor++;
      }
    }

    int newCursorPos = formatted.length;
    int digitCount = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        digitCount++;
      }
      if (digitCount == digitsBeforeCursor) {
        newCursorPos = i + 1;
        break;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPos.clamp(0, formatted.length)),
    );
  }
}

/// Takes a price or text string containing unformatted numbers (e.g. "LKR 100000 - 150000", "$111 / night", "₹2,387 / night")
/// and adds comma separators to all 4+ digit numbers while normalizing currency symbols (e.g. $, ₹ -> USD, INR).
String formatPriceString(String text, {String? targetCurrency}) {
  if (text.isEmpty) return text;
  var result = text;
  final currencyCode = (targetCurrency != null && targetCurrency.isNotEmpty)
      ? targetCurrency
      : 'USD';

  // Replace any currency symbol ($, ₹, €, £, ¥, Rs., Rs) with currency code (e.g. "₹2,387" -> "INR 2,387")
  result = result.replaceAllMapped(
    RegExp(r'(?:\$|₹|€|£|¥|Rs\.?)\s*([\d,]+)'),
    (match) => '$currencyCode ${match.group(1)}',
  );

  // Format 4+ digit numbers with comma separators (e.g. "100000" -> "100,000")
  return result.replaceAllMapped(RegExp(r'\b\d{4,}\b'), (match) {
    final val = int.tryParse(match.group(0)!) ?? 0;
    return formatAmount(val);
  });
}
