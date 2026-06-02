import 'package:intl/intl.dart';

/// Formats a money/amount value with thousands separators.
/// e.g. 100000 -> "100,000", 1500 -> "1,500", 1234.5 (decimals: 2) -> "1,234.50".
String formatAmount(num value, {int decimals = 0}) {
  final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
  return NumberFormat(pattern, 'en_US').format(value);
}
