import 'package:intl/intl.dart';

/// Formats a money/amount value with thousands separators.
/// e.g. 100000 -> "100,000", 1500 -> "1,500", 1234.5 (decimals: 2) -> "1,234.50".
String formatAmount(num value, {int decimals = 0}) {
  final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
  return NumberFormat(pattern, 'en_US').format(value);
}

/// Takes a price or text string containing unformatted numbers (e.g. "LKR 100000 - 150000", "Save LKR 50000")
/// and adds comma separators to all 4+ digit numbers.
/// e.g. "LKR 100000" -> "LKR 100,000"
String formatPriceString(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\b\d{4,}\b'), (match) {
    final val = int.tryParse(match.group(0)!) ?? 0;
    return formatAmount(val);
  });
}
