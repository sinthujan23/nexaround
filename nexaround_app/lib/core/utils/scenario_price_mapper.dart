/// Extracts a representative numeric value from a price string like
/// "USD 200 - 400" or "USD 120" (averages range bounds when present).
double? parseRepresentativePrice(String priceString) {
  final matches = RegExp(r'[\d,]+(\.\d+)?').allMatches(priceString);
  final values = matches
      .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')))
      .whereType<double>()
      .toList();
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Maps each strategy's price to a budget scenario tag ('minimum',
/// 'recommended', 'comfortable') based on relative price ranking.
/// Entries with no parseable price get a null tag.
List<String?> mapPricesToScenarios(List<double?> prices) {
  final result = List<String?>.filled(prices.length, null);
  final validIndices = [
    for (var i = 0; i < prices.length; i++)
      if (prices[i] != null) i,
  ];
  if (validIndices.isEmpty) return result;

  validIndices.sort((a, b) => prices[a]!.compareTo(prices[b]!));

  if (validIndices.length == 1) {
    result[validIndices.first] = 'recommended';
  } else if (validIndices.length == 2) {
    result[validIndices.first] = 'minimum';
    result[validIndices.last] = 'comfortable';
  } else {
    result[validIndices.first] = 'minimum';
    result[validIndices.last] = 'comfortable';
    result[validIndices[validIndices.length ~/ 2]] = 'recommended';
  }
  return result;
}
